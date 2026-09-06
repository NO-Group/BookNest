import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// The BookNest watermark canvas — a soft, tiled open-book + quill glyph
/// pattern painted behind content. Used on the chat screens and anywhere
/// that deserves a quiet, branded backdrop (message lists, reading
/// surfaces). Pure CustomPainter: no assets, crisp at every DPI.
///
/// The watermark deliberately sits *under* [child] and never intercepts
/// pointers, so it composes with lists, scroll views and inputs.
class WatermarkBackground extends StatelessWidget {
  final Widget child;

  /// Glyph strength. Keep it whisper-quiet: ~0.05 in dark, ~0.06 in light.
  final double opacity;

  /// Tile size in logical pixels. Larger → sparser pattern.
  final double spacing;

  /// Glyph tint. Defaults to white in dark mode, navy in light mode.
  final Color? color;

  const WatermarkBackground({
    super.key,
    required this.child,
    this.opacity = 0.05,
    this.spacing = 132,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _WatermarkPainter(
              color: color ??
                  (dark ? const Color(0xFFFFFFFF) : BookNestColors.navyDeep),
              opacity: opacity,
              spacing: spacing,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  final Color color;
  final double opacity;
  final double spacing;

  _WatermarkPainter({
    required this.color,
    required this.opacity,
    required this.spacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-14 * math.pi / 180);
    canvas.translate(-size.width / 2, -size.height / 2);

    // Paint a generous over-scan so the rotated tiles always cover the view.
    final double step = spacing;
    final int cols = (size.width / step).ceil() + 3;
    final int rows = (size.height / step).ceil() + 3;

    for (int row = -1; row < rows; row++) {
      for (int col = -1; col < cols; col++) {
        // Brick offset: every other row shifts half a tile.
        final double dx = col * step + (row.isOdd ? step / 2 : 0);
        final double dy = row * step;
        _drawOpenBook(canvas, Offset(dx, dy), paint);
        _drawSparkle(canvas, Offset(dx + step / 2, dy + step / 2), paint);
      }
    }

    canvas.restore();
  }

  /// A small open book: two page arcs meeting at a spine, drawn ~34px wide.
  void _drawOpenBook(Canvas canvas, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx - 17, center.dy - 8)
      // left page top edge
      ..quadraticBezierTo(center.dx - 9, center.dy - 13, center.dx, center.dy - 9)
      // right page top edge
      ..quadraticBezierTo(center.dx + 9, center.dy - 13, center.dx + 17, center.dy - 8)
      // right page outer edge + bottom
      ..lineTo(center.dx + 17, center.dy + 8)
      ..quadraticBezierTo(center.dx + 9, center.dy + 4, center.dx, center.dy + 8)
      ..quadraticBezierTo(center.dx - 9, center.dy + 4, center.dx - 17, center.dy + 8)
      ..close();
    canvas.drawPath(path, paint);
    // spine
    canvas.drawLine(Offset(center.dx, center.dy - 9), Offset(center.dx, center.dy + 8), paint);
    // page fold hints
    canvas.drawLine(
      Offset(center.dx - 11, center.dy - 5),
      Offset(center.dx - 11, center.dy + 5),
      paint..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(center.dx + 11, center.dy - 5),
      Offset(center.dx + 11, center.dy + 5),
      paint..strokeWidth = 1,
    );
  }

  /// A four-point sparkle that fills the gaps between books.
  void _drawSparkle(Canvas canvas, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - 5)
      ..quadraticBezierTo(center.dx + 1.2, center.dy - 1.2, center.dx + 5, center.dy)
      ..quadraticBezierTo(center.dx + 1.2, center.dy + 1.2, center.dx, center.dy + 5)
      ..quadraticBezierTo(center.dx - 1.2, center.dy + 1.2, center.dx - 5, center.dy)
      ..quadraticBezierTo(center.dx - 1.2, center.dy - 1.2, center.dx, center.dy - 5)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WatermarkPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity ||
      oldDelegate.spacing != spacing;
}
