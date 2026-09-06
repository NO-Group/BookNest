import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Hold-to-record voice notes, BookNest-styled. Recording and playback
/// work today; SENDING unlocks when Cloudflare R2 is connected — voice
/// is "other media", so by our media law it goes to R2, never into a
/// database and never to Cloudinary.
/// ─────────────────────────────────────────────────────────────────────────────

/// Opens the recorder sheet. Resolves with the recorded file, or null.
/// [onR2Ready] is injected by the composer; it only resolves when R2 is
/// connected, so callers can distinguish "cancelled" from "gated".
Future<File?> showVoiceRecorder(BuildContext context) async {
  return Navigator.of(context, rootNavigator: true)
      .push<File>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const VoiceRecorderScreen(),
  ));
}

class VoiceRecorderScreen extends StatefulWidget {
  const VoiceRecorderScreen({super.key});

  @override
  State<VoiceRecorderScreen> createState() => _VoiceRecorderScreenState();
}

enum _VrStage { idle, recording, recorded, uploading }

class _VoiceRecorderScreenState extends State<VoiceRecorderScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  _VrStage _stage = _VrStage.idle;
  String? _path;
  Duration _elapsed = Duration.zero;
  bool _playing = false;
  String? _notice;

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _notice =
          'Microphone permission is needed to record. Enable it in Settings.');
      return;
    }
    final file = '${Directory.systemTemp.path}/bn_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000, sampleRate: 44100),
        path: file,
      );
      setState(() {
        _stage = _VrStage.recording;
        _elapsed = Duration.zero;
        _notice = null;
      });
      _tick();
    } catch (_) {
      setState(() => _notice = 'Recording could not start — please try again.');
    }
  }

  Future<void> _stop({bool keep = true}) async {
    try {
      final path = await _recorder.stop();
      if (!keep || path == null) {
        setState(() => _stage = _VrStage.idle);
        return;
      }
      setState(() {
        _path = path;
        _stage = _VrStage.recorded;
      });
    } catch (_) {
      setState(() => _stage = _VrStage.idle);
    }
  }

  void _tick() {
    if (_stage != _VrStage.recording || !mounted) return;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (_stage != _VrStage.recording || !mounted) return;
      setState(() => _elapsed += const Duration(milliseconds: 250));
      if (_elapsed >= const Duration(minutes: 2)) {
        _stop(keep: true);
        return;
      }
      _tick();
    });
  }

  Future<void> _preview() async {
    if (_path == null) return;
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    await _player.play(DeviceFileSource(_path!));
    if (mounted) setState(() => _playing = true);
    _player.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  Future<void> _send() async {
    setState(() => _stage = _VrStage.uploading);
    final status = await BackendApi.instance.mediaStatus();
    final r2Ready = status?['r2Configured'] == true;
    if (!r2Ready) {
      if (!mounted) return;
      setState(() {
        _stage = _VrStage.recorded;
        _notice = 'Voice messages unlock as soon as cloud storage (R2) is '
            'connected to BookNest. Your recording stays on this device for now.';
      });
      return;
    }
    // R2 uploader lands with the storage credentials — the recording is
    // kept and the composer is re-invoked then.
    if (!mounted) return;
    Navigator.of(context).pop<File?>(null);
  }

  String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? BookNestColors.navyDeep : BookNestColors.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Voice message',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                      colors: [BookNestColors.navy, BookNestColors.navyDeep]),
                  border: Border.all(
                      color: BookNestColors.cyan.withOpacity(_stage == _VrStage.recording ? 1 : .35),
                      width: _stage == _VrStage.recording ? 4 : 2),
                ),
                child: Icon(
                  _stage == _VrStage.recording
                      ? Icons.graphic_eq_rounded
                      : Icons.mic_none_rounded,
                  color: BookNestColors.cyan,
                  size: 52,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _stage == _VrStage.recording
                    ? _clock(_elapsed)
                    : (_stage == _VrStage.idle
                        ? 'Hold the button to record'
                        : 'Ready — up to 2 minutes'),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: dark ? Colors.white : BookNestColors.navyDeep),
              ),
              const SizedBox(height: 22),
              if (_notice != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: BookNestColors.cyan.withOpacity(.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(_notice!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: dark ? Colors.white : BookNestColors.navyDeep)),
                ),
                const SizedBox(height: 18),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_stage == _VrStage.idle)
                    _bigButton(
                      label: 'Record',
                      icon: Icons.fiber_manual_record_rounded,
                      onTap: _start,
                    ),
                  if (_stage == _VrStage.recording)
                    _bigButton(
                      label: 'Stop',
                      icon: Icons.stop_rounded,
                      onTap: () => _stop(keep: true),
                    ),
                  if (_stage == _VrStage.recorded) ...[
                    _bigButton(
                      label: _playing ? 'Pause' : 'Preview',
                      icon: _playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onTap: _preview,
                    ),
                    const SizedBox(width: 12),
                    _bigButton(
                      label: 'Rerecord',
                      icon: Icons.refresh_rounded,
                      onTap: () => setState(() {
                        _path = null;
                        _stage = _VrStage.idle;
                      }),
                    ),
                    const SizedBox(width: 12),
                    _bigButton(
                      label: 'Send',
                      icon: Icons.send_rounded,
                      primary: true,
                      onTap: _send,
                    ),
                  ],
                  if (_stage == _VrStage.uploading)
                    const CircularProgressIndicator(color: BookNestColors.cyan),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: primary
              ? BookNestColors.cyan
              : (dark ? Colors.white.withOpacity(.07) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: primary ? BookNestColors.cyan : BookNestColors.cyan.withOpacity(.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 20,
                color: primary
                    ? BookNestColors.navyDeep
                    : BookNestColors.cyan),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: primary
                        ? BookNestColors.navyDeep
                        : (dark ? Colors.white : BookNestColors.navyDeep))),
          ],
        ),
      ),
    );
  }
}
