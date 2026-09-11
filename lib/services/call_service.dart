import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// BookNest Calls — 1:1 voice and video, pure peer-to-peer WebRTC.
///
/// Signaling rides BookNest's own Supabase Realtime channels (already part
/// of the stack, zero extra services): a private channel per call pair
/// carries ring/offer/answer/ICE/bye, and each reader keeps a personal
/// channel for incoming rings. Media flows device-to-device via WebRTC
/// with public STUN — calls work on open networks; symmetric-corporate
/// NATs without TURN may not connect (honestly surfaced in the UI).
enum CallStatus { idle, outgoing, ringing, connecting, active, ended }

class CallSession {
  final String peerId;
  final String peerName;
  final bool video;
  final bool incoming;

  CallSession({
    required this.peerId,
    required this.peerName,
    required this.video,
    required this.incoming,
  });
}

class CallService {
  CallService._();
  static final CallService instance = CallService._();

  CallStatus status = CallStatus.idle;
  CallSession? session;

  final ValueNotifier2<CallStatus> statusNotifier =
      ValueNotifier2<CallStatus>(CallStatus.idle);
  final ValueNotifier2<MediaStream?> remoteStream = ValueNotifier2<MediaStream?>(null);
  final ValueNotifier2<MediaStream?> localStream = ValueNotifier2<MediaStream?>(null);
  final ValueNotifier2<String?> statusText = ValueNotifier2<String?>(null);

  /// Incoming ring surfaced to the app shell (set by main).
  void Function(CallSession session)? onIncoming;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  MediaStream? _remote;
  RealtimeChannelPair? _pair;
  RealtimePersonal? _personal;
  bool _muted = false;
  bool _cameraOff = false;
  bool get muted => _muted;
  bool get cameraOff => _cameraOff;

  String get _me => SupabaseService().auth.currentUser?.id ?? '';

  /// The pair channel both devices dial into.
  static String pairKey(String a, String b) {
    final ids = [a, b]..sort();
    return 'bn_call_${ids.join('_').substring(0, 40)}';
  }

  String get _pairName => pairKey(_me, session?.peerId ?? '');

  /// Subscribes to the personal ring channel. Call once after login.
  Future<void> ensureInitialized() async {
    if (_personal != null || _me.isEmpty) return;
    _personal = RealtimePersonal(
      client: SupabaseService().client,
      channelName: 'bn_call_$_me',
      onRing: (payload) {
        if (status != CallStatus.idle) return;
        final from = payload['from']?.toString() ?? '';
        if (from.isEmpty) return;
        session = CallSession(
          peerId: from,
          peerName: payload['name']?.toString() ?? 'Reader',
          video: payload['video'] == true,
          incoming: true,
        );
        status = CallStatus.ringing;
        statusNotifier.value = status;
        onIncoming?.call(session!);
      },
    );
    await _personal!.subscribe();
  }

  Future<void> startCall({required String peerId, required String peerName, required bool video}) async {
    if (status != CallStatus.idle || _me.isEmpty) return;
    session = CallSession(peerId: peerId, peerName: peerName, video: video, incoming: false);
    status = CallStatus.outgoing;
    statusText.value = 'Calling ${peerName.split(' ').first}…';
    statusNotifier.value = status;
    try {
      _pair = RealtimeChannelPair(
          client: SupabaseService().client, channelName: _pairName);
      await _pair!.subscribe(onEvent: _onPairEvent);
      await _pair!.send('ring', {
        'from': _me,
        'name': peerNameForMe(),
        'video': video,
      });
      // If nothing answers, the call dies politely.
      Timer(const Duration(seconds: 45), () {
        if (status == CallStatus.outgoing || status == CallStatus.connecting) {
          statusText.value = 'No answer';
          Future.delayed(const Duration(seconds: 2), endCall);
        }
      });
    } catch (_) {
      statusText.value = 'Could not reach the network';
      Future.delayed(const Duration(seconds: 2), endCall);
    }
  }

  Future<void> acceptIncoming() async {
    if (session == null || !session!.incoming) return;
    status = CallStatus.connecting;
    statusText.value = 'Connecting…';
    statusNotifier.value = status;
    try {
      _pair = RealtimeChannelPair(
          client: SupabaseService().client, channelName: _pairName);
      await _pair!.subscribe(onEvent: _onPairEvent);
      await _pair!.send('accepted', {'from': _me});
    } catch (_) {
      statusText.value = 'Connection failed';
      Future.delayed(const Duration(seconds: 2), endCall);
    }
  }

  Future<void> declineIncoming() async {
    try {
      final pair = RealtimeChannelPair(
          client: SupabaseService().client, channelName: _pairName);
      await pair.subscribe();
      await pair.send('declined', {'from': _me});
      await pair.teardown();
    } catch (_) {}
    await endCall(notifyPeer: false);
  }

  Future<void> _prepareMedia() async {
    final permissions = await [
      Permission.microphone,
      if (session?.video == true) Permission.camera,
    ].request();
    if (permissions[Permission.microphone]!.isDenied) {
      throw Exception('Microphone permission denied');
    }
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': (session?.video ?? false)
          ? {'facingMode': 'user', 'width': 1280, 'height': 720}
          : false,
    });
    localStream.value = _local;
  }

  Future<void> _createPeer() async {
    _pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    });
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remote = event.streams.first;
        remoteStream.value = _remote;
      }
    };
    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _pair?.send('ice', {
        'from': _me,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    if (_local != null) {
      for (final track in _local!.getTracks()) {
        await _pc!.addTrack(track, _local!);
      }
    }
  }

  Future<void> _onPairEvent(String event, Map<dynamic, dynamic> payload) async {
    final from = payload['from']?.toString() ?? '';
    if (from == _me) return; // our own echoes
    switch (event) {
      case 'accepted':
        if (status != CallStatus.outgoing) return;
        status = CallStatus.connecting;
        statusText.value = 'Connecting…';
        statusNotifier.value = status;
        try {
          await _prepareMedia();
          await _createPeer();
          final offer = await _pc!.createOffer();
          await _pc!.setLocalDescription(offer);
          await _pair!.send('offer', {
            'from': _me,
            'sdp': offer.sdp,
            'type': offer.type,
          });
        } catch (_) {
          statusText.value = 'Microphone or camera unavailable';
          Future.delayed(const Duration(seconds: 2), endCall);
        }
        break;
      case 'offer':
        if (status != CallStatus.connecting) return;
        try {
          await _prepareMedia();
          await _createPeer();
          await _pc!.setRemoteDescription(
              RTCSessionDescription(payload['sdp']?.toString() ?? '', 'offer'));
          final answer = await _pc!.createAnswer();
          await _pc!.setLocalDescription(answer);
          await _pair!.send('answer', {
            'from': _me,
            'sdp': answer.sdp,
            'type': answer.type,
          });
        } catch (_) {
          statusText.value = 'Microphone or camera unavailable';
          Future.delayed(const Duration(seconds: 2), endCall);
        }
        break;
      case 'answer':
        if (status != CallStatus.connecting) return;
        try {
          await _pc!.setRemoteDescription(
              RTCSessionDescription(payload['sdp']?.toString() ?? '', 'answer'));
        } catch (_) {}
        break;
      case 'ice':
        try {
          await _pc?.addCandidate(RTCIceCandidate(
            payload['candidate']?.toString() ?? '',
            payload['sdpMid']?.toString(),
            (payload['sdpMLineIndex'] as num?)?.toInt(),
          ));
        } catch (_) {}
        break;
      case 'connected':
        status = CallStatus.active;
        statusText.value = null;
        statusNotifier.value = status;
        break;
      case 'declined':
        statusText.value = 'Call declined';
        Future.delayed(const Duration(seconds: 2), endCall);
        break;
      case 'bye':
        statusText.value = 'Call ended';
        Future.delayed(const Duration(seconds: 1), endCall);
        break;
    }
  }

  /// The connecting side flips to active once media actually flows.
  void markActiveIfConnecting() {
    if (status == CallStatus.connecting) {
      status = CallStatus.active;
      statusText.value = null;
      statusNotifier.value = status;
      _pair?.send('connected', {'from': _me});
    }
  }

  bool get isConnected => status == CallStatus.active;

  Future<void> toggleMute() async {
    _muted = !_muted;
    final audio = _local?.getAudioTracks();
    if (audio != null && audio.isNotEmpty) {
      audio.first.enabled = !_muted;
    }
  }

  Future<void> toggleCamera() async {
    _cameraOff = !_cameraOff;
    final video = _local?.getVideoTracks();
    if (video != null && video.isNotEmpty) {
      video.first.enabled = !_cameraOff;
    }
  }

  Future<void> switchCamera() async {
    try {
      final video = _local?.getVideoTracks();
      if (video != null && video.isNotEmpty) {
        await Helper.switchCamera(video.first);
      }
    } catch (_) {}
  }

  Future<void> endCall({bool notifyPeer = true}) async {
    if (notifyPeer) {
      try {
        await _pair?.send('bye', {'from': _me});
      } catch (_) {}
    }
    try {
      await _pc?.close();
    } catch (_) {}
    try {
      await _local?.dispose();
    } catch (_) {}
    try {
      await _remote?.dispose();
    } catch (_) {}
    try {
      await _pair?.teardown();
    } catch (_) {}
    _pc = null;
    _local = null;
    _remote = null;
    _pair = null;
    _muted = false;
    _cameraOff = false;
    localStream.value = null;
    remoteStream.value = null;
    statusText.value = null;
    status = CallStatus.idle;
    session = null;
    statusNotifier.value = status;
  }
}

String peerNameForMe() {
  // Lightweight display name for the ring payload; the full profile is
  // already on the other side's directory.
  final email = SupabaseService().auth.currentUser?.email ?? '';
  return email.split('@').first.isNotEmpty ? email.split('@').first : 'A reader';
}

/// ── Realtime plumbing (Supabase broadcast channels) ─────────────────────
typedef RealtimeEvent = void Function(String event, Map<dynamic, dynamic> payload);

class RealtimeChannelPair {
  RealtimeChannelPair({required this.client, required this.channelName});

  final SupabaseClient client;
  final String channelName;
  dynamic _channel;
  RealtimeEvent? _onEvent;

  Future<void> subscribe({RealtimeEvent? onEvent}) async {
    _onEvent = onEvent;
    _channel = client.channel(channelName);
    for (final event in const [
      'ring', 'accepted', 'offer', 'answer', 'ice', 'connected',
      'declined', 'bye',
    ]) {
      _channel.onBroadcast(event: event, callback: (payload) {
        if (payload is Map && _onEvent != null) {
          _onEvent!(event, payload);
        }
      });
    }
    await _channel.subscribe();
  }

  Future<void> send(String event, Map<String, dynamic> payload) async {
    try {
      await _channel?.sendBroadcastMessage(event: event, payload: payload);
    } catch (_) {}
  }

  Future<void> teardown() async {
    try {
      await client.removeChannel(_channel);
    } catch (_) {}
    _channel = null;
  }
}

class RealtimePersonal {
  RealtimePersonal({
    required this.client,
    required this.channelName,
    required this.onRing,
  });

  final SupabaseClient client;
  final String channelName;
  final void Function(Map<dynamic, dynamic> payload) onRing;
  dynamic _channel;

  Future<void> subscribe() async {
    _channel = client.channel(channelName);
    _channel.onBroadcast(event: 'ring', callback: (payload) {
      if (payload is Map) onRing(payload);
    });
    await _channel.subscribe();
  }
}

/// A tiny ValueNotifier that reads clearly at the call sites.
class ValueNotifier2<T> extends ChangeNotifier2<T> {
  ValueNotifier2(super.value);
}

class ChangeNotifier2<T> extends ChangeNotifier {
  ChangeNotifier2(this._value);
  T _value;
  T get value => _value;
  set value(T v) {
    if (identical(v, _value)) return;
    _value = v;
    notifyListeners();
  }
}
