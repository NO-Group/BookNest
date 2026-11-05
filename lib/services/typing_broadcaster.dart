import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'profile_cache.dart';
import 'supabase_service.dart';

/// What one person is doing in a chat right now.
@immutable
class TypingActivity {
  final String name;

  /// true = recording a voice note, false = typing.
  final bool recording;
  final DateTime until;

  const TypingActivity(
      {required this.name, required this.recording, required this.until});
}

/// WhatsApp-style live typing over Supabase Realtime broadcast (the same
/// transport call signaling uses): no database writes, nothing stored,
/// nothing to configure.
///
/// Two kinds of channel:
///  * a ROOM channel (`bn_room_<conversationId>`), joined while a chat is
///    open. Everyone in the chat sees "Ada is typing…" / "recording
///    audio…" under the title, plus animated dots in the message list;
///  * a personal INBOX channel (`bn_typing_<userId>`), so the chat LIST
///    shows "typing…" on a DM row before the chat is opened. In a DM the
///    composer pings the peer's inbox as well as the room.
///
/// Every state ends on its own: an explicit "stop" when the text is
/// cleared or sent, and a per-person timeout if pings stop arriving
/// (closed app, lost signal).
class TypingBroadcaster {
  TypingBroadcaster._();
  static final TypingBroadcaster instance = TypingBroadcaster._();

  static const String _roomPrefix = 'bn_room_';
  static const String _inboxPrefix = 'bn_typing_';

  /// One ping every 2.5 s while typing, so a person stays shown with
  /// pings in hand ([_peerTtl] covers two missed pings).
  static const Duration _sendThrottle = Duration(milliseconds: 2500);
  static const Duration _peerTtl = Duration(seconds: 6);

  dynamic _room;
  dynamic _peerInbox;
  dynamic _myInbox;
  String? _conversationId;
  String? _peerId;
  String? _myInboxId;
  String _myId = '';
  String _myName = '';
  String _lastState = 'stop';
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _sweep;
  Timer? _recordingPing;

  final Map<String, TypingActivity> _roomPeople = {};
  final Map<String, TypingActivity> _inboxChats = {};

  /// userId → activity, for everyone active in the OPEN chat.
  final ValueNotifier<Map<String, TypingActivity>> roomActivity =
      ValueNotifier<Map<String, TypingActivity>>(const {});

  /// conversationId → activity, for DM rows in the chat list.
  final ValueNotifier<Map<String, TypingActivity>> inboxActivity =
      ValueNotifier<Map<String, TypingActivity>>(const {});

  /// userId → name of everyone typing or recording in the open chat
  /// (kept for simple listeners).
  final ValueNotifier<Map<String, String>> typingPeers =
      ValueNotifier<Map<String, String>>(const {});

  // ── rooms ────────────────────────────────────────────────────────────

  /// Join the chat's room (idempotent; switches rooms when called with a
  /// new id). Pass [peerId] for a DM so the peer's chat list also
  /// lights up.
  void enter(String conversationId, {required String myId, String? peerId}) {
    if (_conversationId == conversationId) {
      if ((peerId ?? '').isNotEmpty && _peerId == null) _joinPeer(peerId!);
      return;
    }
    leave();
    _conversationId = conversationId;
    if (myId != _myId) _myName = '';
    _myId = myId;
    _loadMyName();
    try {
      final channel =
          SupabaseService().client.channel('$_roomPrefix$conversationId');
      channel.onBroadcast(
          event: 'typing',
          callback: (payload) => _receive(payload, _roomPeople, byConv: false));
      channel.subscribe();
      _room = channel;
    } catch (_) {
      // Realtime hiccup: typing states are a courtesy, never a blocker.
      _room = null;
    }
    if ((peerId ?? '').isNotEmpty) _joinPeer(peerId!);
  }

  void _joinPeer(String peerId) {
    if (peerId == _myId) return;
    _peerId = peerId;
    try {
      final channel = SupabaseService().client.channel('$_inboxPrefix$peerId');
      channel.subscribe();
      _peerInbox = channel;
    } catch (_) {
      _peerInbox = null;
    }
  }

  /// Close the room: tell the others we stopped, then clear everything.
  /// With [conversationId], only if that room is still the open one — on
  /// PC the old chat closes AFTER the next one opened.
  void leave([String? conversationId]) {
    if (conversationId != null && conversationId != _conversationId) return;
    stopped();
    _recordingPing?.cancel();
    _recordingPing = null;
    for (final channel in [_room, _peerInbox]) {
      if (channel == null) continue;
      try {
        SupabaseService().client.removeChannel(channel);
      } catch (_) {}
    }
    _room = null;
    _peerInbox = null;
    _peerId = null;
    _conversationId = null;
    _lastState = 'stop';
    _roomPeople.clear();
    _publish();
  }

  // ── the local reader's state ────────────────────────────────────────

  /// The composer's text changed and isn't empty.
  void iAmTyping() => _send('typing');

  /// The text was cleared or sent, or the chat closed.
  void stopped() {
    _recordingPing?.cancel();
    _recordingPing = null;
    if (_lastState != 'stop') _send('stop');
  }

  /// Kept for older call sites: same as [stopped].
  void iStopped() => stopped();

  /// The voice-note recorder opened. Pings keep going until [stopped].
  void startRecording() {
    _send('recording');
    _recordingPing?.cancel();
    _recordingPing =
        Timer.periodic(_sendThrottle, (_) => _send('recording', force: true));
  }

  void _send(String state, {bool force = false}) {
    if (_room == null && _peerInbox == null) return;
    final now = DateTime.now();
    if (!force &&
        state != 'stop' &&
        state == _lastState &&
        now.difference(_lastSent) < _sendThrottle) {
      return;
    }
    _lastState = state;
    _lastSent = now;
    final payload = {
      'id': _myId,
      'name': _myName.isEmpty ? 'Someone' : _myName,
      'state': state,
      'conv': _conversationId ?? '',
    };
    for (final channel in [_room, _peerInbox]) {
      if (channel == null) continue;
      try {
        channel.sendBroadcastMessage(event: 'typing', payload: payload);
      } catch (_) {}
    }
  }

  // ── the chat list ───────────────────────────────────────────────────

  /// Listen on the reader's own inbox channel for "typing…" on DM rows.
  /// Idempotent; call it from the chat list.
  void listenInbox(String myId) {
    _watchSignOut();
    if (myId.isEmpty || _myInboxId == myId) return;
    stopInbox();
    _myInboxId = myId;
    if (_myId.isEmpty) _myId = myId;
    _loadMyName();
    try {
      final channel = SupabaseService().client.channel('$_inboxPrefix$myId');
      channel.onBroadcast(
          event: 'typing',
          callback: (payload) => _receive(payload, _inboxChats, byConv: true));
      channel.subscribe();
      _myInbox = channel;
    } catch (_) {
      _myInbox = null;
    }
  }

  StreamSubscription<dynamic>? _authSub;

  /// Signing out ends everything, so the next account on this device
  /// starts clean.
  void _watchSignOut() {
    if (_authSub != null) return;
    try {
      _authSub = SupabaseService().auth.onAuthStateChange.listen((change) {
        if (change.event != AuthChangeEvent.signedOut) return;
        leave();
        stopInbox();
        _myId = '';
        _myName = '';
      });
    } catch (_) {}
  }

  /// Signed out: stop listening.
  void stopInbox() {
    if (_myInbox != null) {
      try {
        SupabaseService().client.removeChannel(_myInbox);
      } catch (_) {}
    }
    _myInbox = null;
    _myInboxId = null;
    _inboxChats.clear();
    _publish();
  }

  // ── receiving ───────────────────────────────────────────────────────

  void _receive(dynamic payload, Map<String, TypingActivity> into,
      {required bool byConv}) {
    if (payload is! Map) return;
    final id = payload['id']?.toString() ?? '';
    if (id.isEmpty || id == _myId) return;
    final key = byConv ? (payload['conv']?.toString() ?? '') : id;
    if (key.isEmpty) return;
    final state = payload['state']?.toString() ?? 'typing';
    if (state == 'stop') {
      into.remove(key);
    } else {
      into[key] = TypingActivity(
        name: payload['name']?.toString() ?? 'Someone',
        recording: state == 'recording',
        until: DateTime.now().add(_peerTtl),
      );
    }
    _publish();
  }

  /// Drop people whose pings stopped, one by one.
  void _prune() {
    final now = DateTime.now();
    _roomPeople.removeWhere((_, a) => a.until.isBefore(now));
    _inboxChats.removeWhere((_, a) => a.until.isBefore(now));
    _publish();
  }

  void _publish() {
    roomActivity.value = Map.unmodifiable(_roomPeople);
    inboxActivity.value = Map.unmodifiable(_inboxChats);
    typingPeers.value = Map.unmodifiable(
        _roomPeople.map((id, a) => MapEntry(id, a.name)));
    final busy = _roomPeople.isNotEmpty || _inboxChats.isNotEmpty;
    if (busy && _sweep == null) {
      _sweep = Timer.periodic(const Duration(seconds: 1), (_) => _prune());
    } else if (!busy && _sweep != null) {
      _sweep!.cancel();
      _sweep = null;
    }
  }

  /// The reader's own display name, from the profile cache.
  Future<void> _loadMyName() async {
    final id = _myId.isNotEmpty ? _myId : (_myInboxId ?? '');
    if (id.isEmpty || _myName.isNotEmpty) return;
    try {
      final people = await ProfileCache.instance.lookup([id]);
      final me = people[id];
      final name = (me?['display_name'] ?? me?['username'])?.toString() ?? '';
      if (name.trim().isNotEmpty) _myName = name.trim();
    } catch (_) {}
  }

  // ── labels ──────────────────────────────────────────────────────────

  /// "typing…", "Ada is typing…", "Ada and Tunde are typing…",
  /// "Ada and 3 others are typing…", or "recording audio…".
  /// [group] = false for a DM, where names are left out.
  static String label(Map<String, TypingActivity> people, {bool group = true}) {
    if (people.isEmpty) return '';
    final list = people.values.toList();
    final recording = list.every((a) => a.recording);
    final verb = recording ? 'recording audio…' : 'typing…';
    if (!group) return verb;
    String first(String n) => n.split(' ').first;
    final names = list.map((a) => first(a.name)).toList();
    final doing = recording ? 'recording audio…' : 'typing…';
    if (names.length == 1) return '${names[0]} is $doing';
    if (names.length == 2) return '${names[0]} and ${names[1]} are $doing';
    return '${names[0]} and ${names.length - 1} others are $doing';
  }
}
