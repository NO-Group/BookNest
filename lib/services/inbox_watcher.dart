import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_api.dart';
import 'background_link.dart';
import 'media_storage.dart';
import 'notification_service.dart';
import 'punishment_gate.dart';
import 'push_service.dart';
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
      await _sweepEvents(me);
      await _heartbeat(me);
      await refreshPunishmentGate();
      _primed = true;
    } catch (_) {
      // Never let the watcher crash the loop; next tick tries again.
    } finally {
      // Prove the app is alive, so the background link stays quiet and
      // leaves the banners to us.
      LinkService.instance.ping();
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
      _autoSaveMedia('dm.messages', id, last, known, '$sender|$text');
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
      _autoSaveMedia('chat.messages', id, last, known, '$sender|$text');
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

  final Set<String> _mediaFetched = <String>{};

  /// New media in a chat the reader has not opened: save it to the BookNest
  /// media folder now, long before the server copy expires (photos 30
  /// days, files/voice notes/videos 3 days). Reads only — never marks read.
  void _autoSaveMedia(String action, String conversationId, Object? last,
      String? known, String signature) {
    if (!MediaStorage.autoSave || last is! Map) return;
    const media = {'image', 'video', 'file', 'voice', 'audio'};
    if (!media.contains(last['type']?.toString())) return;
    if (known == signature) return; // nothing new since the last sweep
    final at = DateTime.tryParse(last['createdAt']?.toString() ?? '');
    if (at != null && DateTime.now().difference(at) > const Duration(days: 4)) {
      return; // older than the relay window — nothing left to rescue
    }
    if (!_mediaFetched.add('$conversationId|$signature')) return;
    unawaited(() async {
      try {
        final res = await BackendApi.instance
            .callFresh(action, {'conversationId': conversationId});
        final list = res?['messages'];
        if (list is! List) return;
        MediaStorage.autoSaveFrom([
          for (final m in list)
            if (m is Map) Map<String, dynamic>.from(m),
        ]);
      } catch (_) {}
    }());
  }

  DateTime? _lastBeat;
  static const Duration _beatInterval = Duration(minutes: 3);

  /// Presence heartbeat: the edge stamps user_prefs.lastActive so the
  /// moderator's insight screen can count who is online right now.
  Future<void> _heartbeat(String me) async {
    final now = DateTime.now();
    final last = _lastBeat;
    if (last != null && now.difference(last) < _beatInterval) return;
    _lastBeat = now;
    try {
      await BackendApi.instance.heartbeat();
    } catch (_) {
      // Presence is a courtesy; never disturb the sweep.
    }
  }

  DateTime? _lastEventSweep;
  static const Duration _eventInterval = Duration(minutes: 10);

  /// Upcoming group events (next 24 h) become quiet local reminders —
  /// 24 h, 2 h and 15 min before the start, each fired once per event.
  Future<void> _sweepEvents(String me) async {
    final now = DateTime.now();
    final last = _lastEventSweep;
    if (last != null && now.difference(last) < _eventInterval) return;
    _lastEventSweep = now;
    final res = await BackendApi.instance.callFresh('groups.events.reminders');
    final events = res?['events'];
    if (events is! List || events.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final row in events) {
      if (row is! Map) continue;
      final e = Map<String, dynamic>.from(row);
      final id = e['id']?.toString() ?? '';
      final at = DateTime.tryParse(e['at']?.toString() ?? '');
      if (id.isEmpty || at == null) continue;
      final untilStart = at.difference(now);
      final sameDay = at.year == now.year &&
          at.month == now.month &&
          at.day == now.day;
      String? bucket;
      if (untilStart.inMinutes <= 15 && untilStart.inMinutes > -1) {
        bucket = '15m';
      } else if (sameDay && untilStart.inMinutes > 15) {
        // Same-calendar-day events get their own single nudge.
        bucket = 'today';
      } else if (untilStart.inHours <= 2 && untilStart.inMinutes > 15) {
        bucket = '2h';
      } else if (untilStart.inHours <= 24 && untilStart.inMinutes > 120) {
        bucket = '24h';
      }
      if (bucket == null) continue;
      final key = 'bn_evt_$id$bucket';
      if (prefs.getBool(key) == true) continue;
      await prefs.setBool(key, true);
      final title = e['title']?.toString() ?? 'Group event';
      final group = e['groupName']?.toString() ?? '';
      final when = switch (bucket) {
        '15m' => 'Starting any moment now',
        'today' => 'Happens today',
        '2h' => 'Starts within 2 hours',
        _ => 'Starts within 24 hours',
      };
      NotificationService.instance.showInstant(
        id: ('$id$bucket').hashCode & 0x7fffffff,
        title: '📅 $title',
        body: group.isEmpty ? when : '$when · $group',
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
    // With push active, alerts outside the app come from push (Android
    // shows them even when the app is closed) — never both.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final onScreen = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (PushService.instance.active && !onScreen) return;
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
