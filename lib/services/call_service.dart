import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend_api.dart';
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

  /// When media actually started flowing — the call timer's zero point.
  DateTime? connectedAt;

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
  bool _speakerOn = false;
  bool get muted => _muted;
  bool get cameraOff => _cameraOff;
  bool get speakerOn => _speakerOn;

  /// Call timer text, ticked by the ring/active loop.
  String get elapsedLabel {
    final at = session?.connectedAt;
    if (at == null) return '00:00';
    final d = DateTime.now().difference(at);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  // ── ringer: looping tone + haptic pulse while ringing/answering ──
  final AudioPlayer _ringer = AudioPlayer();
  Timer? _haptics;
  bool _ringerOn = false;

  Future<void> _startRinger() async {
    if (_ringerOn) return;
    _ringerOn = true;
    try {
      await _ringer.setReleaseMode(ReleaseMode.loop);
      await _ringer.setVolume(.75);
      await _ringer.play(AssetSource('sounds/call_ring.wav'));
    } catch (_) {}
    _haptics = Timer.periodic(const Duration(milliseconds: 800), (_) {
      HapticFeedback.mediumImpact();
    });
  }

  Future<void> _stopRinger() async {
    if (!_ringerOn) return;
    _ringerOn = false;
    _haptics?.cancel();
    _haptics = null;
    try {
      await _ringer.stop();
    } catch (_) {}
  }

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
        unawaited(_startRinger());
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
    unawaited(_startRinger());
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
    unawaited(_stopRinger());
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
    unawaited(_stopRinger());
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
    // Broadcast-grade capture: the OS noise suppressor, echo canceller
    // and auto-gain all on — the difference between "phone call" and
    // "sitting across the table".
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'channelCount': 1,
      },
      'video': (session?.video ?? false)
          ? {'facingMode': 'user', 'width': 1280, 'height': 720, 'frameRate': 30}
          : false,
    });
    localStream.value = _local;
    // WhatsApp convention: video calls live on the speakerphone, voice
    // calls start pinned to the earpiece.
    _speakerOn = session?.video == true;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
    statusNotifier.value = status; // nudge listeners for the button state
  }

  /// Upgrades the Opus audio line to 64 kbps stereo-capable — the default
  /// SDP negotiates a thin ~24 kbps mono channel; this is the single
  /// biggest clarity win a WebRTC call can get.
  String _applyOpusQuality(String sdp) {
    const boost = 'a=fmtp:111 '
        'minptime=10;useinbandfec=1;maxaveragebitrate=64000;stereo=1;'
        'sprop-stereo=1';
    final lines = sdp.split('\r\n');
    var fmtpIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('a=fmtp:111')) {
        fmtpIndex = i;
        break;
      }
    }
    if (fmtpIndex != -1) {
      if (lines[fmtpIndex].contains('maxaveragebitrate')) return sdp;
      lines[fmtpIndex] = boost;
    } else {
      // No fmtp line yet — add one right after the Opus rtpmap.
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('a=rtpmap:111 opus/')) {
          lines.insert(i + 1, boost);
          break;
        }
      }
    }
    return lines.join('\r\n');
  }

  /// STUN always; TURN relay with edge-minted ephemeral credentials as
  /// soon as the server has TURN_URL/TURN_SECRET — symmetric-NAT proof.
  /// Falls back to STUN-only on any failure so a call never blocks here.
  Future<List<Map<String, dynamic>>> _iceServers() async {
    const fallback = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
    try {
      final res = await BackendApi.instance.call('calls.ice');
      final list = res?['iceServers'];
      if (list is List && list.isNotEmpty) {
        final servers = <Map<String, dynamic>>[];
        for (final entry in list) {
          if (entry is! Map) continue;
          final server = <String, dynamic>{
            'urls': entry['urls']?.toString() ?? '',
          };
          if (entry['username'] != null) {
            server['username'] = entry['username'].toString();
          }
          if (entry['credential'] != null) {
            server['credential'] = entry['credential'].toString();
          }
          if ((server['urls'] as String).isNotEmpty) servers.add(server);
        }
        if (servers.isNotEmpty) return servers;
      }
    } catch (_) {}
    return fallback;
  }

  Future<void> _createPeer() async {
    _pc = await createPeerConnection({
      'iceServers': await _iceServers(),
      'iceCandidatePoolSize': 4,
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
    // The honest source of truth for "the call is live" — both sides
    // watch their own ICE state, so neither waits on a signaling event
    // that may never arrive.
    _pc!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _stopRinger();
        markActiveIfConnecting();
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        if (status == CallStatus.active) {
          statusText.value = 'Reconnecting…';
          statusNotifier.value = status;
        }
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (status == CallStatus.active ||
            status == CallStatus.connecting) {
          statusText.value = 'Reconnecting…';
          statusNotifier.value = status;
          try {
            _pc?.restartIce();
          } catch (_) {}
        }
      }
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
          final offerSdp = _applyOpusQuality(offer.sdp ?? '');
          await _pc!
              .setLocalDescription(RTCSessionDescription(offerSdp, offer.type));
          await _pair!.send('offer', {
            'from': _me,
            'sdp': offerSdp,
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
          final answerSdp = _applyOpusQuality(answer.sdp ?? '');
          await _pc!.setLocalDescription(
              RTCSessionDescription(answerSdp, answer.type));
          await _pair!.send('answer', {
            'from': _me,
            'sdp': answerSdp,
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
        _stopRinger();
        if (status == CallStatus.connecting) {
          status = CallStatus.active;
          session?.connectedAt ??= DateTime.now();
          statusText.value = null;
          statusNotifier.value = status;
        }
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
      session?.connectedAt = DateTime.now();
      statusText.value = null;
      statusNotifier.value = status;
      unawaited(_stopRinger());
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
    // Nudge the call screen so the button redraws its state.
    statusNotifier.value = status;
  }

  Future<void> toggleCamera() async {
    _cameraOff = !_cameraOff;
    final video = _local?.getVideoTracks();
    if (video != null && video.isNotEmpty) {
      video.first.enabled = !_cameraOff;
    }
    statusNotifier.value = status;
  }

  /// Switches the active camera on the fly and nudges the UI.
  Future<void> switchCamera() async {
    try {
      final video = _local?.getVideoTracks();
      if (video != null && video.isNotEmpty) {
        await Helper.switchCamera(video.first);
      }
    } catch (_) {}
    statusNotifier.value = status;
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
    await _stopRinger();
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
    _speakerOn = false;
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
