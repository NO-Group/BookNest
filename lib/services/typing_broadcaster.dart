import 'dart:async';

import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// Live typing states for chat rooms, over BookNest's own Supabase
/// Realtime broadcast (the same transport the call signaling uses — no
/// extra infrastructure, no database writes, nothing to configure).
///
/// The open chat enters a room channel; the composer pings "typing"
/// (throttled) while its reader is writing; everyone else in the room
/// sees the names appear and expire on their own.
class TypingBroadcaster {
  TypingBroadcaster._();
  static final TypingBroadcaster instance = TypingBroadcaster._();

  static const String _prefix = 'bn_room_';
  static const Duration _sendThrottle = Duration(seconds: 2);
  static const Duration _peerTtl = Duration(seconds: 4);

  dynamic _channel;
  String? _conversationId;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _expiryTimer;
  String _myId = '';

  /// userId → display name, for everyone currently typing in the open
  /// room. Listen for the "typing…" line under the chat title.
  final ValueNotifier<Map<String, String>> typingPeers =
      ValueNotifier<Map<String, String>>({});

  /// Start listening for typing in this conversation (idempotent per
  /// room; switches rooms when called again).
  void enter(String conversationId, {required String myId}) {
    if (_conversationId == conversationId) return;
    leave();
    _conversationId = conversationId;
    _myId = myId;
    try {
      final client = SupabaseService().client;
      final channel = client.channel('$_prefix$conversationId');
      channel.onBroadcast(event: 'typing', callback: (payload) {
        if (payload is! Map) return;
        final id = payload['id']?.toString() ?? '';
        if (id.isEmpty || id == _myId) return;
        final name = payload['name']?.toString() ?? 'Someone';
        typingPeers.value = {...typingPeers.value, id: name};
        _scheduleExpiry();
      });
      channel.subscribe();
      _channel = channel;
    } catch (_) {
      // Realtime hiccup: typing states are a courtesy, never a blocker.
      _channel = null;
    }
  }

  /// Stop listening and clear the state (chat closed).
  void leave() {
    if (_channel != null) {
      try {
        SupabaseService().client.removeChannel(_channel);
      } catch (_) {}
    }
    _channel = null;
    _conversationId = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    typingPeers.value = const {};
  }

  /// Call from the composer while the local reader is typing. Throttled
  /// so fast typists don't flood the transport.
  void iAmTyping(String name) {
    if (_channel == null || _conversationId == null) return;
    final now = DateTime.now();
    if (now.difference(_lastSent) < _sendThrottle) return;
    _lastSent = now;
    try {
      _channel.sendBroadcastMessage(event: 'typing', payload: {
        'id': _myId,
        'name': name,
      });
    } catch (_) {}
  }

  /// Also announce a last ping when a message goes out, so the indicator
  /// clears quickly for the author's own fresh message.
  void iStopped() {
    _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    _expiryTimer = Timer(_peerTtl, () {
      if (typingPeers.value.isEmpty) return;
      // Names simply fade if no fresh ping arrives; the next ping
      // re-adds them.
      typingPeers.value = const {};
    });
  }
}
