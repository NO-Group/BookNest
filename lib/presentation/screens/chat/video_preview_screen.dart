import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../config/theme.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// The last look before a video leaves the phone. Both the BookNest
/// camera and the gallery land here: play it back, scrub it, then send
/// it or throw it away. Nothing is uploaded unseen.
/// ─────────────────────────────────────────────────────────────────────────────

/// Shows [path] in the send-preview screen. Resolves with the same path
/// when the user sends, or null when they discard it.
Future<String?> openVideoPreview(BuildContext context, String path) {
  return Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => VideoPreviewScreen(path: path),
    ),
  );
}

class VideoPreviewScreen extends StatefulWidget {
  final String path;
  const VideoPreviewScreen({super.key, required this.path});

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _muted = false;
  int _size = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      _size = await File(widget.path).length();
    } catch (_) {
      _size = 0;
    }
    final controller = VideoPlayerController.file(File(widget.path));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      await controller.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String get _sizeLabel {
    if (_size <= 0) return '';
    if (_size < 1024 * 1024) return '${(_size / 1024).round()} KB';
    return '${(_size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  String get _positionLabel {
    final c = _controller;
    if (c == null || !_ready) return '';
    final p = c.value.position;
    final d = c.value.duration;
    final pos = '${p.inMinutes}:${_two(p.inSeconds % 60)}';
    final dur = '${d.inMinutes}:${_two(d.inSeconds % 60)}';
    return '$pos / $dur';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = _ready && controller != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Preview',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16.5)),
        actions: [
          if (_sizeLabel.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(_sizeLabel,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12.5)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _failed
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.videocam_off_rounded,
                              color: Colors.white38, size: 44),
                          SizedBox(height: 12),
                          Text('This video could not be opened for preview.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    )
                  : !ready
                      ? const CircularProgressIndicator(
                          color: BookNestColors.cyan)
                      : GestureDetector(
                          onTap: () => setState(() {
                            controller!.value.isPlaying
                                ? controller!.pause()
                                : controller!.play();
                          }),
                          child: AspectRatio(
                            aspectRatio:
                                controller!.value.aspectRatio > 0
                                    ? controller!.value.aspectRatio
                                    : 16 / 9,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(controller),
                                if (!controller.value.isPlaying)
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: BookNestColors.navyDeep
                                          .withOpacity(.55),
                                    ),
                                    padding: const EdgeInsets.all(14),
                                    child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 40),
                                  ),
                              ],
                            ),
                          ),
                        ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_ready && controller != null) ...[
                    Row(
                      children: [
                        InkWell(
                          onTap: () => setState(() {
                            _muted = !_muted;
                            controller.setVolume(_muted ? 0 : 1);
                          }),
                          child: Icon(
                            _muted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3.5,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6),
                              overlayShape:
                                  const RoundSliderOverlayShape(
                                      overlayRadius: 11),
                            ),
                            child: ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: controller,
                              builder: (context, value, _) => Slider(
                                value: value.position.inMilliseconds
                                    .toDouble()
                                    .clamp(
                                        0,
                                        value.duration.inMilliseconds
                                            .toDouble()),
                                max: value.duration.inMilliseconds
                                        .toDouble() ==
                                        0
                                    ? 1
                                    : value.duration.inMilliseconds
                                        .toDouble(),
                                activeColor: BookNestColors.cyan,
                                inactiveColor: Colors.white24,
                                onChanged: (v) => controller.seekTo(
                                    Duration(milliseconds: v.round())),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_positionLabel,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11.5)),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          onPressed: () => Navigator.of(context).pop(null),
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 19),
                          label: const Text('Discard',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: BookNestColors.cyan,
                            foregroundColor: BookNestColors.navyDeep,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          onPressed:
                              _failed ? null : () => Navigator.of(context).pop(widget.path),
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('Send',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
