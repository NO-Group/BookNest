import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../config/theme.dart';
import 'photo_edit_screen.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// The BookNest camera. A live in-app viewfinder — no hand-off to the
/// phone's camera app. Shutter → the studio (PhotoEditScreen) with the
/// designed filter and lens presets → the finished picture goes to chat.
/// ─────────────────────────────────────────────────────────────────────────────

/// Presents the camera and resolves with the edited photo bytes,
/// or null when the reader backed out.
Future<Uint8List?> openBookNestCamera(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<Uint8List>(
    fullscreenDialog: true,
    builder: (_) => const CameraScreen(),
  ));
}

/// Presents the camera in video mode and resolves with the recorded
/// clip's file path (sound included), or null when the reader backed out.
Future<String?> openBookNestCameraForVideo(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (_) => const CameraScreen(mode: CameraMode.video),
    ),
  );
}

enum CameraMode { photo, video }

enum _CamStage { asking, denied, live, failed }

class CameraScreen extends StatefulWidget {
  final CameraMode mode;
  const CameraScreen({super.key, this.mode = CameraMode.photo});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _which = 0;
  double _zoom = 1;
  double _maxZoom = 1;
  FlashMode _flash = FlashMode.off;
  _CamStage _stage = _CamStage.asking;
  bool _capturing = false;
  late CameraMode _mode = widget.mode;
  bool _recording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prepare();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _start(_cameras[_which]);
    }
  }

  Future<void> _prepare() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _stage = _CamStage.denied);
      return;
    }
    try {
      _cameras = await availableCameras();
      if (!mounted) return;
      if (_cameras.isEmpty) {
        setState(() => _stage = _CamStage.failed);
        return;
      }
      final back = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      await _start(_cameras[back == -1 ? 0 : back]);
    } on CameraException {
      if (mounted) setState(() => _stage = _CamStage.failed);
    }
  }

  Future<void> _start(CameraDescription camera) async {
    final previous = _controller;
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true, // videos record with sound.
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setFlashMode(_flash);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _stage = _CamStage.live);
      final max = await controller.getMaxZoomLevel();
      if (mounted) setState(() => _maxZoom = max.toDouble());
    } on CameraException {
      if (_controller == controller) {
        unawaited(controller.dispose());
        if (mounted) setState(() => _stage = _CamStage.failed);
      }
    } finally {
      if (previous != null && previous != _controller) {
        await previous.dispose();
      }
    }
  }

  Future<void> _flip() async {
    if (_cameras.length < 2 || _capturing) return;
    final next = (_which + 1) % _cameras.length;
    setState(() {
      _which = next;
      _zoom = 1;
    });
    await _start(_cameras[next]);
  }

  Future<void> _setFlash(FlashMode mode) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFlashMode(mode);
      if (mounted) setState(() => _flash = mode);
    } on CameraException {
      // Flash unavailable on this lens — leave the mode unchanged.
    }
  }

  Future<void> _setZoom(double value) async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _zoom = value);
    try {
      await controller.setZoomLevel(value);
    } on CameraException {
      // Some lenses ignore zoom — the slider simply does nothing.
    }
  }

  Future<void> _toggleVideo() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!_recording) {
      if (_capturing) return;
      try {
        await controller.startVideoRecording();
        if (!mounted) return;
        setState(() {
          _recording = true;
          _recordSeconds = 0;
          _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() => _recordSeconds += 1);
          });
        });
      } on CameraException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Recording could not start — please try again.')));
        }
      }
      return;
    }
    // Stop and hand the clip to the chat.
    try {
      _recordTimer?.cancel();
      final file = await controller.stopVideoRecording();
      if (!mounted) return;
      setState(() => _recording = false);
      Navigator.of(context).pop(file.path);
    } on CameraException {
      if (mounted) {
        setState(() => _recording = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('The clip could not be saved — please try again.')));
      }
    }
  }

  String get _recordLabel {
    final m = _recordSeconds ~/ 60;
    final sec = _recordSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _snap() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) return;
    if (_mode == CameraMode.video) {
      await _toggleVideo();
      return;
    }
    setState(() => _capturing = true);
    try {
      final shot = await controller.takePicture();
      if (!mounted) return;
      final edited = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PhotoEditScreen(photo: shot),
      ));
      if (!mounted) return;
      Navigator.of(context).pop(edited);
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('The shot could not be taken — please try again.')));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (_stage) {
        _CamStage.asking || _CamStage.denied => _Gate(
            denied: _stage == _CamStage.denied,
            onRetry: () {
              setState(() => _stage = _CamStage.asking);
              _prepare();
            },
          ),
        _CamStage.failed => const _Gate(
            denied: false,
            broken: true,
          ),
        _CamStage.live => _viewfinder(),
      },
    );
  }

  Widget _viewfinder() {
    final controller = _controller!;
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                          color: Colors.black38, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _setFlash(
                        _flash == FlashMode.off
                            ? FlashMode.torch
                            : FlashMode.off),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                          color: Colors.black38, shape: BoxShape.circle),
                      child: Icon(
                        _flash == FlashMode.off
                            ? Icons.flash_off_rounded
                            : Icons.flash_on_rounded,
                        color: _flash == FlashMode.off
                            ? Colors.white
                            : BookNestColors.cyan,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (_maxZoom > 1.05)
                Container(
                  margin: const EdgeInsets.only(bottom: 10, left: 44, right: 44),
                  child: Row(
                    children: [
                      const Icon(Icons.zoom_in_rounded,
                          color: Colors.white70, size: 18),
                      Expanded(
                        child: Slider(
                          min: 1,
                          max: _maxZoom,
                          value: _zoom.clamp(1, _maxZoom),
                          activeColor: BookNestColors.cyan,
                          inactiveColor: Colors.white24,
                          onChanged: _setZoom,
                        ),
                      ),
                      Text('${_zoom.toStringAsFixed(1)}×',
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 76),
                  // Shutter — the big cyan ring.
                  GestureDetector(
                    onTap: _snap,
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: BookNestColors.cyan, width: 4),
                        color: _capturing
                            ? BookNestColors.cyan.withOpacity(.35)
                            : Colors.transparent,
                      ),
                      child: Center(
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _capturing
                                ? Colors.white24
                                : BookNestColors.cyan,
                          ),
                          child: _capturing
                              ? const Padding(
                                  padding: EdgeInsets.all(18),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white),
                                )
                              : _recording
                                  ? const Icon(Icons.stop_rounded,
                                      color: Colors.white, size: 30)
                                  : Icon(
                                      _mode == CameraMode.video
                                          ? Icons.videocam_rounded
                                          : Icons.camera_alt_rounded,
                                      color: BookNestColors.navyDeep,
                                      size: 26),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 64,
                    child: IconButton(
                      onPressed: _flip,
                      icon: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                            color: Colors.black38, shape: BoxShape.circle),
                        child: const Icon(Icons.cameraswitch_rounded,
                            color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_recording)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(_recordLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ModeSwitch(
                    icon: Icons.photo_camera_rounded,
                    label: 'Photo',
                    selected: _mode == CameraMode.photo,
                    onTap: _recording
                        ? null
                        : () => setState(() => _mode = CameraMode.photo),
                  ),
                  const SizedBox(width: 14),
                  _ModeSwitch(
                    icon: Icons.videocam_rounded,
                    label: 'Video',
                    selected: _mode == CameraMode.video,
                    onTap: _recording
                        ? null
                        : () => setState(() => _mode = CameraMode.video),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _mode == CameraMode.video
                    ? 'BookNest camera  ·  video with sound'
                    : 'BookNest camera  ·  filters on the next step',
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _Gate extends StatelessWidget {
  final bool denied;
  final bool broken;
  final VoidCallback? onRetry;

  const _Gate({required this.denied, this.broken = false, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: [BookNestColors.navy, BookNestColors.navyDeep]),
              ),
              child: Icon(
                broken
                    ? Icons.camera_alt_outlined
                    : Icons.photo_camera_outlined,
                color: BookNestColors.cyan,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              broken
                  ? 'Camera unavailable'
                  : denied
                      ? 'Camera permission needed'
                      : 'Opening the camera…',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              broken
                  ? 'This device has no usable camera, so shots cannot be taken here.'
                  : denied
                      ? 'BookNest takes pictures inside the app with your filters. '
                          'Allow camera access to continue.'
                      : '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, height: 1.45),
            ),
            if (!broken) ...[
              const SizedBox(height: 22),
              SizedBox(
                width: 160,
                child: TextButton(
                  onPressed: () {
                    if (denied) {
                      openAppSettings();
                    } else {
                      onRetry?.call();
                    }
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: BookNestColors.cyan,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    denied ? 'Open settings' : 'Try again',
                    style: const TextStyle(
                        color: BookNestColors.navyDeep,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


class _ModeSwitch extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _ModeSwitch({
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected ? BookNestColors.cyan : Colors.black38,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? BookNestColors.navyDeep : Colors.white70),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color:
                        selected ? BookNestColors.navyDeep : Colors.white70)),
          ],
        ),
      ),
    );
  }
}
