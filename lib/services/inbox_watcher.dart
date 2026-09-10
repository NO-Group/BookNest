import 'dart:async';

import 'backend_api.dart';
import 'notification_service.dart';
import 'supabase_service.dart';

/// Zero-external message notifications. While BookNest is alive — in hand
/// or in recents — a light sweep of the delivery queue every 30 seconds
/// surfaces new direct and club messages as local notifications. No
/// Firebase, no OneSignal, no third party, nothing to configure: the only
/// thing a device push service adds is waking a *killed* app, and this
/// watcher honestly covers everything up to that line.
class InboxWatcher {
  InboxWatcher._();
  static final InboxWatcher instance = InboxWatcher._();

  static const Duration _interval = Duration(seconds: 30);

  Timer? _timer;
  bool _sweeping = false;
  bool _primed = false;
  final Set<String> _viewing = {}; // conversations open on screen
  final Map<String, String> _seen = {}; // convId -> lastMessage signature
  final Map<String, String> _names = {}; // userId -> display name

  /// The watcher will not buzz about a conversation the reader is
  /// literally looking at.
  void enter(String conversationId) => _viewing.add(conversationId);

  void leave(String conversationId) => _viewing.remove(conversationId);

  /// Starts the sweep loop (idempotent). First pass primes the baseline
  /// silently so launch never replays old messages as banners.
  void start() {
    if (_timer != null) return;
    _timer = Timer(const Duration(seconds: 6), _sweep);
  }

  void _schedule() {
    _timer = Timer(_interval, _sweep);
  }

  Future<void> _sweep() async {
    if (_sweeping) {
      _schedule();
      return;
    }
    _sweeping = true;
    try {
      if (!BackendApi.instance.available) return;
      final me = SupabaseService().auth.currentUser?.id;
      if (me == null) return;
      await _sweepDirects(me);
      await _sweepClubs(me);
      _primed = true;
    } catch (_) {
      // Never let the watcher crash the loop; next tick tries again.
    } finally {
      _sweeping = false;
      _schedule();
    }
  }

  Future<void> _sweepDirects(String me) async {
    final res = await BackendApi.instance.callFresh('dm.list');
    final conversations = res?['conversations'];
    if (conversations is! List) return;
    for (final row in conversations) {
      if (row is! Map) continue;
      final conv = Map<String, dynamic>.from(row);
      final id = conv['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final last = conv['lastMessage'];
      final sender = last is Map ? (last['senderId']?.toString() ?? '') : '';
      final text = last is Map ? (last['text']?.toString() ?? '') : '';
      final known = _seen[id];
      _seen[id] = '$sender|$text';
      if (!_primed || known == null || known == '$sender|$text') continue;
      if (sender == me || sender.isEmpty) continue;
      if (_viewing.contains(id)) continue;
      final name = await _nameOf(conv['peerId']?.toString() ?? '');
      _notify(id,
          title: name.isEmpty ? 'New message' : name,
          body: _preview(text, fallback: 'Sent a message'));
    }
  }

  Future<void> _sweepClubs(String me) async {
    final res = await BackendApi.instance.callFresh('chat.rooms');
    final rooms = res?['rooms'];
    if (rooms is! List) return;
    for (final row in rooms) {
      if (row is! Map) continue;
      final room = Map<String, dynamic>.from(row);
      final id = room['conversationId']?.toString() ?? '';
      if (id.isEmpty) continue;
      final last = room['lastMessage'];
      final sender = last is Map ? (last['senderId']?.toString() ?? '') : '';
      final text = last is Map ? (last['text']?.toString() ?? '') : '';
      final known = _seen['club:$id'];
      _seen['club:$id'] = '$sender|$text';
      if (!_primed || known == null || known == '$sender|$text') continue;
      if (sender == me || sender.isEmpty) continue;
      if (_viewing.contains(id)) continue;
      _notify(
        'club:$id',
        title: room['title']?.toString().isNotEmpty == true
            ? room['title'].toString()
            : 'Group chat',
        body: _preview(text, fallback: 'New message in the club'),
      );
    }
  }

  String _preview(String text, {required String fallback}) {
    if (text.startsWith('e1|')) return '🔒 Encrypted message';
    final clean = text.trim();
    if (clean.isEmpty) return fallback;
    return clean.length > 120 ? '${clean.substring(0, 117)}…' : clean;
  }

  void _notify(String conversationId,
      {required String title, required String body}) {
    // Deterministic id per conversation: follow-ups replace instead of
    // stacking a banner tower.
    NotificationService.instance.showInstant(
      id: conversationId.hashCode & 0x7fffffff,
      title: title,
      body: body,
    );
  }

  Future<String> _nameOf(String peerId) async {
    if (peerId.isEmpty) return '';
    final cached = _names[peerId];
    if (cached != null) return cached;
    try {
      final rows = await SupabaseService()
          .client
          .from('profiles')
          .select('display_name, username')
          .eq('id', peerId)
          .limit(1);
      if (rows is List && rows.isNotEmpty) {
        final person = Map<String, dynamic>.from(rows.first as Map);
        final display = person['display_name']?.toString() ?? '';
        final username = person['username']?.toString() ?? '';
        final name = display.isNotEmpty ? display : username;
        _names[peerId] = name;
        return name;
      }
    } catch (_) {
      // Name resolution is a courtesy; the banner works without it.
    }
    return '';
  }
}
