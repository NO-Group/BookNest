import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/call_service.dart';

/// The call room: full-screen remote video (or a glowing avatar for voice
/// calls), local preview PIP, and the honest call state front and center.
class CallScreen extends StatelessWidget {
  const CallScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, __, ___) => const CallScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = CallService.instance;
    return Scaffold(
      backgroundColor: BookNestColors.navyDeep,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          service.statusNotifier,
          service.statusText,
        ]),
        builder: (context, _) {
          final session = service.session;
          if (session == null || service.status == CallStatus.idle) {
            // Call finished while the sheet was up.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });
          }
          final status = service.status;
          final statusLine = service.statusText.value ??
              switch (status) {
                CallStatus.ringing =>
                  'Incoming ${session!.video ? 'video' : 'voice'} call…',
                CallStatus.outgoing => 'Calling…',
                CallStatus.connecting => 'Connecting…',
                CallStatus.active =>
                  session!.video ? 'Video call' : 'Voice call',
                _ => 'Call ended',
              };

          return SafeArea(
            child: Stack(children: [
              // Remote video, full bleed.
              if (session!.video)
                const Positioned.fill(
                  child: _CallVideo(remote: true),
                )
              else
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [
                            BookNestColors.cyan.withOpacity(.25),
                            BookNestColors.cyan.withOpacity(.06),
                          ]),
                        ),
                        child: CircleAvatar(
                          radius: 58,
                          backgroundColor: BookNestColors.navy,
                          child: Text(
                            session.peerName.characters.isEmpty
                                ? '?'
                                : session.peerName.characters.first
                                    .toUpperCase(),
                            style: const TextStyle(
                                color: BookNestColors.cyan,
                                fontSize: 42,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Top status block.
              Positioned(
                top: 22,
                left: 0,
                right: 0,
                child: Column(children: [
                  Text(session.peerName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: status == CallStatus.active
                          ? BookNestColors.cyan.withOpacity(.16)
                          : Colors.white.withOpacity(.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(statusLine,
                        style: TextStyle(
                            color: status == CallStatus.active
                                ? BookNestColors.cyan
                                : Colors.white70,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),

              // Local preview PIP.
              if (session.video)
                Positioned(
                  top: 86,
                  right: 16,
                  child: Container(
                    width: 104,
                    height: 148,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: BookNestColors.cyan.withOpacity(.5)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(.4),
                            blurRadius: 16),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: const _CallVideo(remote: false),
                  ),
                ),

              // Controls.
              Positioned(
                left: 0,
                right: 0,
                bottom: 26,
                child: Column(children: [
                  if (status == CallStatus.ringing) ...[
                    const Text('BookNest is calling you',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _CallAction(
                        icon: Icons.close_rounded,
                        label: 'Decline',
                        background: const Color(0xFFB3261E),
                        onTap: () => service.declineIncoming(),
                      ),
                      const SizedBox(width: 34),
                      _CallAction(
                        icon: Icons.call_rounded,
                        label: 'Accept',
                        background: const Color(0xFF1E8E5A),
                        onTap: () => service.acceptIncoming(),
                      ),
                    ]),
                  ] else ...[
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (session.video) ...[
                        _CallAction(
                          icon: service.cameraOff
                              ? Icons.videocam_off_rounded
                              : Icons.videocam_rounded,
                          label: service.cameraOff ? 'Off' : 'Camera',
                          background: Colors.white.withOpacity(.12),
                          onTap: () => service.toggleCamera(),
                        ),
                        const SizedBox(width: 16),
                        _CallAction(
                          icon: Icons.flip_camera_android_rounded,
                          label: 'Flip',
                          background: Colors.white.withOpacity(.12),
                          onTap: () => service.switchCamera(),
                        ),
                        const SizedBox(width: 16),
                      ],
                      _CallAction(
                        icon: service.muted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: service.muted ? 'Muted' : 'Mic',
                        background: Colors.white.withOpacity(.12),
                        onTap: () => service.toggleMute(),
                      ),
                      const SizedBox(width: 16),
                      _CallAction(
                        icon: Icons.call_end_rounded,
                        label: 'End',
                        background: const Color(0xFFB3261E),
                        onTap: () => service.endCall(),
                      ),
                    ]),
                  ],
                  if (status == CallStatus.connecting) ...[
                    const SizedBox(height: 14),
                    Text('Peer-to-peer · encrypted by the transport',
                        style: TextStyle(
                            color: Colors.white.withOpacity(.45),
                            fontSize: 10.5)),
                  ],
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.icon,
    required this.label,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(.14)),
          ),
          child: Icon(icon, color: Colors.white, size: 25),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Binds a call stream into a live video renderer. `remote` picks the
/// peer's stream; otherwise the mirrored local preview.
class _CallVideo extends StatefulWidget {
  const _CallVideo({required this.remote});

  final bool remote;

  @override
  State<_CallVideo> createState() => _CallVideoState();
}

class _CallVideoState extends State<_CallVideo> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _renderer.initialize();
    final service = CallService.instance;
    void bind() {
      if (!mounted) return;
      _renderer.srcObject = (widget.remote
              ? service.remoteStream
              : service.localStream)
          .value;
      if (service.status == CallStatus.active) {
        service.markActiveIfConnecting();
      }
      if (mounted) setState(() => _ready = true);
    }

    (widget.remote ? service.remoteStream : service.localStream)
        .addListener(bind);
    bind();
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Container(
        color: BookNestColors.navy,
        child: const Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: BookNestColors.cyan),
        ),
      );
    }
    return RTCVideoView(
      _renderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      mirror: !widget.remote,
    );
  }
}
