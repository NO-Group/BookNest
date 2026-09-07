import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:image_picker/image_picker.dart';

import '../../../config/theme.dart';

/// Snap → polish → send. A lightweight camera editor: live filter
/// previews (all pure ColorMatrix math — Original, Mono, Noir, Warm,
/// Cool, Vivid, Fade) plus brightness and contrast, then exports the
/// finished pixels for upload. No external image libraries.
class PhotoEditScreen extends StatefulWidget {
  final XFile photo;

  const PhotoEditScreen({super.key, required this.photo});

  @override
  State<PhotoEditScreen> createState() => _PhotoEditScreenState();
}

class _PhotoEditScreenState extends State<PhotoEditScreen> {
  Uint8List? _bytes;
  int _filterIndex = 0;
  double _brightness = 1; // 0.5 – 1.5
  double _contrast = 1; // 0.5 – 1.5
  bool _exporting = false;

  static const List<({String label, IconData icon, List<double> matrix})>
      _filters = [
    (
      label: 'Original',
      icon: Icons.image_outlined,
      matrix: [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0],
    ),
    (
      label: 'Mono',
      icon: Icons.filter_b_and_w_rounded,
      matrix: [
        .33, .59, .11, 0, 0, .33, .59, .11, 0, 0, .33, .59, .11, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
    (
      label: 'Noir',
      icon: Icons.dark_mode_outlined,
      matrix: [
        .30, .55, .15, 0, -18, .30, .55, .15, 0, -18, .30, .55, .15, 0,
        -18, 0, 0, 0, 1, 0,
      ],
    ),
    (
      label: 'Warm',
      icon: Icons.wb_sunny_outlined,
      matrix: [
        1.12, .06, 0, 0, 8, .04, 1.04, 0, 0, 2, 0, 0, .94, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
    (
      label: 'Cool',
      icon: Icons.ac_unit_rounded,
      matrix: [
        .96, 0, .08, 0, 0, 0, 1.0, .04, 0, 0, .04, 0, 1.1, 0, 8,
        0, 0, 0, 1, 0,
      ],
    ),
    (
      label: 'Vivid',
      icon: Icons.bolt_rounded,
      matrix: [
        1.25, -.1, -.1, 0, 0, -.1, 1.25, -.1, 0, 0, -.1, -.1, 1.25, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
    (
      label: 'Fade',
      icon: Icons.blur_off_outlined,
      matrix: [
        .82, .1, .08, 0, 26, .1, .82, .08, 0, 26, .08, .1, .82, 0, 26,
        0, 0, 0, 1, 0,
      ],
    ),
      (
      label: 'Sepia',
      icon: Icons.energy_savings_leaf_outlined,
      matrix: [
        .39, .77, .19, 0, 0, .35, .69, .27, 0, 0, .27, .63, .35, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
    (
      label: 'Fade',
      icon: Icons.blur_on_rounded,
      matrix: [
        .84, .1, .06, 0, 26, .1, .82, .08, 0, 26, .08, .1, .8, 0, 26,
        0, 0, 0, 1, 0,
      ],
    ),
    (
      label: 'Mint',
      icon: Icons.eco_outlined,
      matrix: [
        .88, .04, .04, 0, 0, .02, 1.06, .02, 0, 6, .02, .04, .96, 0, 4,
        0, 0, 0, 1, 0,
      ],
    ),
    (
      label: 'Cyan',
      icon: Icons.water_drop_outlined,
      matrix: [
        .82, .02, .18, 0, 4, .02, .98, .06, 0, 2, .1, .1, 1.12, 0, 10,
        0, 0, 0, 1, 0,
      ],
    ),
    (
      label: 'Sunset',
      icon: Icons.wb_twilight_outlined,
      matrix: [
        1.14, .02, 0, 0, 10, .02, .88, .12, 0, 0, .02, .06, .86, 0, 0,
        0, 0, 0, 1, 0,
      ],
    ),
    (
      label: 'Dream',
      icon: Icons.auto_awesome_outlined,
      matrix: [
        1.06, .06, .04, 0, 16, .04, 1.04, .06, 0, 12, .06, .04, 1.08, 0,
        18, 0, 0, 0, 1, 0,
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await widget.photo.readAsBytes();
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  List<double> get _combinedMatrix {
    final f = _filters[_filterIndex].matrix;
    final b = _brightness;
    final c = _contrast;
    // Contrast around mid-grey, then brightness offset.
    final List<double> cm = [
      c, 0.0, 0.0, 0.0, (0.5 * (1 - c)) * 255 + (b - 1) * 96,
      0.0, c, 0.0, 0.0, (0.5 * (1 - c)) * 255 + (b - 1) * 96,
      0.0, 0.0, c, 0.0, (0.5 * (1 - c)) * 255 + (b - 1) * 96,
      0.0, 0.0, 0.0, 1.0, 0.0,
    ];
    return _multiply(f, cm);
  }

  static List<double> _multiply(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[r * 5 + k] * b[k * 5 + c];
        }
        out[r * 5 + c] = sum + (c == 4 ? a[r * 5 + 4] : 0);
      }
    }
    return out;
  }

  Future<void> _usePhoto() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final boundary =
          _renderKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) throw 'no-boundary';
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final png = byteData?.buffer.asUint8List();
      if (!mounted) return;
      if (png == null || png.isEmpty) throw 'export-failed';
      Navigator.of(context).pop(png);
    } catch (_) {
      if (!mounted) return;
      // Fallback: send the untouched original — honest and always works.
      Navigator.of(context).pop(_bytes);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  final GlobalKey _renderKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: CircularProgressIndicator(color: BookNestColors.cyan)),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Edit photo',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: TextButton.icon(
              onPressed: _exporting ? null : _usePhoto,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: BookNestColors.cyan))
                  : const Icon(Icons.check_rounded, size: 19),
              label: const Text('Use photo',
                  style: TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: RepaintBoundary(
                key: _renderKey,
                child: ColorFiltered(
                  colorFilter:
                      ColorFilter.matrix(_combinedMatrix),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: const Color(0xFF0A1224),
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
            child: Column(
              children: [
                // Filter strip
                SizedBox(
                  height: 76,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: _filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final filter = _filters[index];
                      final selected = index == _filterIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _filterIndex = index),
                        child: Column(
                          children: [
                            Container(
                              width: 52,
                              height: 42,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? BookNestColors.cyan
                                      : Colors.white24,
                                  width: selected ? 2 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: ColorFiltered(
                                  colorFilter:
                                      ColorFilter.matrix(filter.matrix),
                                  child: Image.memory(bytes,
                                      fit: BoxFit.cover,
                                      width: 52,
                                      height: 42),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              filter.label,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: selected
                                    ? BookNestColors.cyan
                                    : Colors.white70,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Brightness / contrast
                Row(
                  children: [
                    const Icon(Icons.brightness_6_outlined,
                        color: Colors.white70, size: 18),
                    Expanded(
                      child: Slider(
                        value: _brightness,
                        min: 0.5,
                        max: 1.5,
                        activeColor: BookNestColors.cyan,
                        onChanged: (v) => setState(() => _brightness = v),
                      ),
                    ),
                    const Icon(Icons.contrast_rounded,
                        color: Colors.white70, size: 18),
                    Expanded(
                      child: Slider(
                        value: _contrast,
                        min: 0.5,
                        max: 1.5,
                        activeColor: BookNestColors.cyan,
                        onChanged: (v) => setState(() => _contrast = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

