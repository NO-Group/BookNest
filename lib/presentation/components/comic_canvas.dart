import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:math' as math;
import 'dart:ui' show PathOperation;

import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// BookNest Anime Studio — the comic canvas engine.
///
/// A comic page is a tiny JSON document (panels, elements, transforms as
/// normalized floats), rendered live by this widget. No binary page blobs,
/// no game engines — native Flutter only: Stack, ClipRect, GestureDetector,
/// Transform and CustomPainter for the lettering.
///
/// Editing rules baked in:
///  • every element's geometry is normalized (0..1) to its panel, so a
///    page lays out identically on any screen;
///  • dragging/pinching/rotating rebuilds ONLY that element's subtree —
///    the canvas is never rebuilt during an active gesture;
///  • speech bubbles are vector paths (roundedBox / screamBurst /
///    thoughtCloud) with a draggable tail that re-draws the shape;
///  • serialization is lossless and tiny — toJson / fromJson.
/// ─────────────────────────────────────────────────────────────────────────

// ── State models ───────────────────────────────────────────────────────────

/// One element inside a panel: a picture, a speech bubble or a caption.
class ComicElementData {
  final String id;
  final String type; // 'image' | 'speech_bubble' | 'caption'
  final String src; // image only — a remote URL, never embedded bytes
  final String text; // bubble/caption lettering
  final String style; // roundedBox | screamBurst | thoughtCloud
  final double x; // center, normalized to the panel (0..1)
  final double y;
  final double width; // normalized footprint (0..1 of panel width)
  final double scale;
  final double rotation; // radians
  final double anchorX; // bubble tail tip, normalized to the panel
  final double anchorY; // (-1,-1) = no tail placed yet

  const ComicElementData({
    required this.id,
    required this.type,
    this.src = '',
    this.text = '',
    this.style = 'roundedBox',
    required this.x,
    required this.y,
    this.width = 0.44,
    this.scale = 1,
    this.rotation = 0,
    this.anchorX = -1,
    this.anchorY = -1,
  });

  ComicElementData copyWith({
    double? x,
    double? y,
    double? width,
    double? scale,
    double? rotation,
    double? anchorX,
    double? anchorY,
    String? text,
    String? style,
    String? src,
  }) =>
      ComicElementData(
        id: id,
        type: type,
        src: src ?? this.src,
        text: text ?? this.text,
        style: style ?? this.style,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
        anchorX: anchorX ?? this.anchorX,
        anchorY: anchorY ?? this.anchorY,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        if (type == 'image') 'src': src,
        if (type != 'image') ...{
          'text': text,
          'style': style,
        },
        'x': _num(x),
        'y': _num(y),
        'width': _num(width),
        'scale': _num(scale),
        'rotation': _num(rotation),
        if (type == 'speech_bubble') ...{
          'anchorX': _num(anchorX),
          'anchorY': _num(anchorY),
        },
      };

  factory ComicElementData.fromJson(Map<String, dynamic> j) =>
      ComicElementData(
        id: j['id']?.toString() ?? '',
        type: j['type']?.toString() ?? 'caption',
        src: j['src']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
        style: j['style']?.toString() ?? 'roundedBox',
        x: _asDouble(j['x'], 0.5),
        y: _asDouble(j['y'], 0.5),
        width: _asDouble(j['width'], 0.44),
        scale: _asDouble(j['scale'], 1).clamp(0.25, 4.0),
        rotation: _asDouble(j['rotation'], 0),
        anchorX: _asDouble(j['anchorX'], -1),
        anchorY: _asDouble(j['anchorY'], -1),
      );
}

/// One panel: a clipped rect of the page holding stacked elements.
class ComicPanelData {
  final String id;
  final double x, y, width, height; // normalized to the page (0..1)
  final List<ComicElementData> elements;

  const ComicPanelData({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.elements = const [],
  });

  ComicPanelData withElements(List<ComicElementData> next) => ComicPanelData(
      id: id, x: x, y: y, width: width, height: height, elements: next);

  Map<String, dynamic> toJson() => {
        'id': id,
        'bounds': {
          'x': _num(x),
          'y': _num(y),
          'width': _num(width),
          'height': _num(height),
        },
        'elements': elements.map((e) => e.toJson()).toList(),
      };

  factory ComicPanelData.fromJson(Map<String, dynamic> j) {
    final b = (j['bounds'] as Map?) ?? const {};
    return ComicPanelData(
      id: j['id']?.toString() ?? '',
      x: _asDouble(b['x'], 0),
      y: _asDouble(b['y'], 0),
      width: _asDouble(b['width'], 1),
      height: _asDouble(b['height'], 1),
      elements: ((j['elements'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ComicElementData.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// One page. [aspectRatio] is width:height of the whole sheet.
class ComicPageData {
  final int pageNumber;
  final String aspectRatio;
  final List<ComicPanelData> panels;

  const ComicPageData({
    required this.pageNumber,
    this.aspectRatio = '3:4',
    this.panels = const [],
  });

  ComicPageData withPanels(List<ComicPanelData> next) => ComicPageData(
      pageNumber: pageNumber, aspectRatio: aspectRatio, panels: next);

  Map<String, dynamic> toJson() => {
        'pageNumber': pageNumber,
        'aspectRatio': aspectRatio,
        'panels': panels.map((p) => p.toJson()).toList(),
      };

  factory ComicPageData.fromJson(Map<String, dynamic> j) => ComicPageData(
        pageNumber: (j['pageNumber'] as num?)?.toInt() ?? 1,
        aspectRatio: j['aspectRatio']?.toString() ?? '3:4',
        panels: ((j['panels'] as List?) ?? const [])
            .whereType<Map>()
            .map((p) => ComicPanelData.fromJson(Map<String, dynamic>.from(p)))
            .toList(),
      );

  static List<ComicPageData> listFromJson(List<dynamic> raw) => raw
      .whereType<Map>()
      .map((p) => ComicPageData.fromJson(Map<String, dynamic>.from(p)))
      .toList();

  static List<Map<String, dynamic>> listToJson(List<ComicPageData> pages) =>
      pages.map((p) => p.toJson()).toList();
}

double _num(double v) => double.parse(v.toStringAsFixed(4));
double _asDouble(dynamic v, double fallback) =>
    v is num ? v.toDouble() : fallback;

/// Grid presets the studio offers (Tier 1 — no drawing needed).
const Map<String, List<List<double>>> kComicGrids = {
  'Full scene': [
    [0, 0, 1, 1],
  ],
  'Top & bottom': [
    [0, 0, 1, 0.5],
    [0, 0.5, 1, 0.5],
  ],
  'Two columns': [
    [0, 0, 0.5, 1],
    [0.5, 0, 0.5, 1],
  ],
  'Classic 2×2': [
    [0, 0, 0.5, 0.5],
    [0.5, 0, 0.5, 0.5],
    [0, 0.5, 0.5, 0.5],
    [0.5, 0.5, 0.5, 0.5],
  ],
  'Manga rows': [
    [0, 0, 1, 0.34],
    [0, 0.34, 0.58, 0.33],
    [0.58, 0.34, 0.42, 0.33],
    [0, 0.67, 1, 0.33],
  ],
};

List<ComicPanelData> panelsForGrid(String name, {String tag = 'p'}) {
  final cells = kComicGrids[name] ?? kComicGrids['Full scene']!;
  return List.generate(
    cells.length,
    (i) => ComicPanelData(
      id: '$tag${i + 1}',
      x: cells[i][0],
      y: cells[i][1],
      width: cells[i][2],
      height: cells[i][3],
    ),
    growable: false,
  );
}

// ── The speech-bubble painter ──────────────────────────────────────────────

/// Draws the bubble BODY around [rect] with a tail that reaches a target
/// expressed relative to the rect's CENTER (so callers never need to know
/// the laid-out height in advance). Pure vector — crisp at every zoom.
class SpeechBubblePainter extends CustomPainter {
  final String style; // roundedBox | screamBurst | thoughtCloud
  final Rect rect;
  final Offset tailFromCenter; // tail tip in rect-center-relative coords
  final bool hasTail;
  final Color fill;
  final Color outline;
  final double strokeWidth;

  SpeechBubblePainter({
    required this.style,
    required this.rect,
    this.tailFromCenter = Offset.zero,
    this.hasTail = false,
    this.fill = Colors.white,
    this.outline = const Color(0xFF0B1531),
    this.strokeWidth = 2.2,
  });

  Offset get _tip => rect.center + tailFromCenter;

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final body = Path();
    switch (style) {
      case 'screamBurst':
        _burst(body, rect, spikes: 16, depth: 0.16);
        break;
      case 'thoughtCloud':
        _cloud(body, rect);
        break;
      case 'roundedBox':
      default:
        _rounded(body, rect);
    }
    if (!hasTail) {
      canvas.drawPath(body, fillPaint);
      canvas.drawPath(body, stroke);
      return;
    }

    final tail = Path();
    if (style == 'thoughtCloud') {
      _bubbleTail(tail, rect, _tip);
    } else {
      _straightTail(tail, rect, _tip);
    }
    // One silhouette: fill body+tail together, then stroke each.
    final merged = Path.combine(PathOperation.union, body, tail);
    canvas.drawPath(merged, fillPaint);
    canvas.drawPath(body, stroke);
    canvas.drawPath(tail, stroke);
  }

  void _rounded(Path p, Rect r) =>
      p.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(16)));

  void _burst(Path p, Rect r, {required int spikes, required double depth}) {
    final c = r.center;
    final rx = r.width / 2;
    final ry = r.height / 2;
    for (var i = 0; i < spikes * 2; i++) {
      final outer = i.isEven;
      final angle = (math.pi * 2 * i) / (spikes * 2) - math.pi / 2;
      final k = outer ? 1.0 : 1.0 - depth;
      final point = Offset(
          c.dx + rx * k * math.cos(angle), c.dy + ry * k * math.sin(angle));
      if (i == 0) {
        p.moveTo(point.dx, point.dy);
      } else {
        p.lineTo(point.dx, point.dy);
      }
    }
    p.close();
  }

  void _cloud(Path p, Rect r) {
    final c = r.center;
    final rx = r.width / 2;
    final ry = r.height / 2;
    const bumps = 9;
    final cloud = Path();
    for (var i = 0; i < bumps; i++) {
      final a = (math.pi * 2 * i) / bumps;
      final bump = Offset(
          c.dx + rx * 0.78 * math.cos(a), c.dy + ry * 0.78 * math.sin(a));
      cloud.addOval(Rect.fromCircle(
          center: bump, radius: math.min(rx, ry) * 0.40));
    }
    cloud.addOval(
        Rect.fromCenter(center: c, width: rx * 1.5, height: ry * 1.5));
    p.addPath(Path.combine(PathOperation.union, cloud, Path()), Offset.zero);
  }

  /// Sharp triangular tail (speech + scream).
  void _straightTail(Path p, Rect r, Offset tip) {
    final start = _tailRoot(r, tip);
    final dir = tip - start;
    if (dir.distance < 2) return;
    final normal = Offset(-dir.dy, dir.dx) * (0.16 / dir.distance);
    p.moveTo(start.dx + normal.dx, start.dy + normal.dy);
    p.lineTo(tip.dx, tip.dy);
    p.lineTo(start.dx - normal.dx, start.dy - normal.dy);
    p.close();
  }

  /// Trailing bubble circles for the thought cloud.
  void _bubbleTail(Path p, Rect r, Offset tip) {
    final root = _tailRoot(r, tip);
    final mid = Offset.lerp(root, tip, 0.55)!;
    p.addOval(Rect.fromCircle(center: mid, radius: 5.5));
    p.addOval(
        Rect.fromCircle(center: Offset.lerp(mid, tip, 0.8)!, radius: 3.4));
  }

  /// Where the tail leaves the body, aimed at the tip.
  Offset _tailRoot(Rect r, Offset tip) {
    final c = r.center;
    final dir = tip - c;
    if (dir.distance < 1) return Offset(r.left + r.width * 0.2, r.bottom);
    final scale = math.min(
      (r.width / 2) / dir.dx.abs().clamp(0.001, double.infinity),
      (r.height / 2) / dir.dy.abs().clamp(0.001, double.infinity),
    );
    return c + dir * math.min(scale, 1.35);
  }

  @override
  bool shouldRepaint(covariant SpeechBubblePainter old) =>
      old.style != style ||
      old.rect != rect ||
      old.tailFromCenter != tailFromCenter ||
      old.hasTail != hasTail ||
      old.fill != fill ||
      old.outline != outline;
}

// ── The vector bubble body (shape + wrapped lettering) ────────────────────

/// A speech bubble whose shape is drawn by [SpeechBubblePainter] around the
/// laid-out text. The tail tip is [tailFromCenter] in center-relative local
/// coordinates — computed by the caller from panel-space anchors.
class SpeechBubbleView extends StatelessWidget {
  final String text;
  final String style;
  final Offset tailFromCenter;
  final bool hasTail;
  final double maxWidth;
  final Color? fill;
  final Color? outline;
  final Color? textColor;
  final bool editMode;
  final VoidCallback? onTapEdit;
  final VoidCallback? onGestureStart;
  final void Function(Offset delta)? onPan;
  final void Function(double scale, double angle)? onScale;
  final VoidCallback? onGestureEnd;

  const SpeechBubbleView({
    super.key,
    required this.text,
    required this.style,
    required this.maxWidth,
    this.tailFromCenter = Offset.zero,
    this.hasTail = false,
    this.fill,
    this.outline,
    this.textColor,
    this.editMode = false,
    this.onTapEdit,
    this.onGestureStart,
    this.onPan,
    this.onScale,
    this.onGestureEnd,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final useFill = fill ?? (dark ? const Color(0xFF10203A) : Colors.white);
    final useOutline =
        outline ?? (dark ? BookNestColors.cyan : const Color(0xFF0B1531));
    final body = CustomPaint(
      painter: SpeechBubblePainter(
        style: style,
        rect: Rect.zero, // set at paint time from the laid-out child
        tailFromCenter: tailFromCenter,
        hasTail: hasTail,
        fill: useFill,
        outline: useOutline,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: math.max(maxWidth, 70)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor ??
                  (dark ? Colors.white : const Color(0xFF0B1531)),
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
    if (!editMode) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: onTapEdit,
      onScaleStart: (_) => onGestureStart?.call(),
      onScaleUpdate: (d) {
        if (d.pointerCount == 1) {
          onPan?.call(d.focalPointDelta);
        } else {
          onScale?.call(d.scale, d.rotation);
        }
      },
      onScaleEnd: (_) => onGestureEnd?.call(),
      child: body,
    );
  }
}

// ── Transformable element (images + bubbles + captions) ───────────────────

/// Wraps one element with its own gesture life: single-finger pan,
/// two-finger pinch-scale, a rotate handle, a delete handle and — for
/// bubbles — a draggable tail. All transform state lives HERE; the parent
/// canvas is never rebuilt during a gesture, only told the final geometry.
class TransformableElementWidget extends StatefulWidget {
  final ComicElementData data;
  final Size panelSize;
  final bool editMode;
  final VoidCallback? onGestureStart;
  final ValueChanged<ComicElementData>? onGestureEnd;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const TransformableElementWidget({
    super.key,
    required this.data,
    required this.panelSize,
    required this.editMode,
    this.onGestureStart,
    this.onGestureEnd,
    this.onDelete,
    this.onEdit,
  });

  @override
  State<TransformableElementWidget> createState() =>
      _TransformableElementWidgetState();
}

class _TransformableElementWidgetState
    extends State<TransformableElementWidget> {
  late double _x = widget.data.x;
  late double _y = widget.data.y;
  late double _scale = widget.data.scale;
  late double _rotation = widget.data.rotation;
  late double _anchorX = widget.data.anchorX;
  late double _anchorY = widget.data.anchorY;
  bool _active = false;

  static const double _kHandle = 44; // minimum touch target, per spec

  ComicElementData get data => widget.data;
  Size get _panel => widget.panelSize;

  Offset get _centerPx =>
      Offset(_x * _panel.width, _y * _panel.height);
  Offset get _anchorPx =>
      Offset(_anchorX * _panel.width, _anchorY * _panel.height);

  void _begin() {
    if (!_active) {
      _active = true;
      widget.onGestureStart?.call();
    }
  }

  void _commit() {
    if (!_active) return;
    _active = false;
    widget.onGestureEnd?.call(data.copyWith(
      x: _x.clamp(0.02, 0.98),
      y: _y.clamp(0.02, 0.98),
      scale: _scale.clamp(0.25, 4.0),
      rotation: _rotation,
      anchorX: _anchorX,
      anchorY: _anchorY,
    ));
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount == 1) {
      setState(() {
        _x += d.focalPointDelta.dx / _panel.width;
        _y += d.focalPointDelta.dy / _panel.height;
      });
    } else {
      setState(() {
        _scale = (_scale * d.scale).clamp(0.25, 4.0);
        if (data.type != 'speech_bubble') _rotation += d.rotation;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (data.type == 'image') return _buildImage(context);
    return _buildTextElement(context);
  }

  // ── images ──
  Widget _buildImage(BuildContext context) {
    final base = data.width * _panel.width * _scale;
    return Positioned(
      left: _centerPx.dx - base / 2,
      top: _centerPx.dy - base / 2,
      child: Transform.rotate(
        angle: _rotation,
        child: _gestures(
          child: SizedBox(
            width: base,
            height: base,
            child: Stack(children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: data.src.startsWith('http')
                      ? Image.network(
                          data.src,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.black12,
                            child:
                                const Icon(Icons.broken_image_outlined),
                          ),
                        )
                      : Container(
                          color: Colors.black12,
                          child: const Icon(Icons.image_outlined, size: 30),
                        ),
                ),
              ),
              if (widget.editMode) ..._imageHandles(base),
            ]),
          ),
        ),
      ),
    );
  }

  // ── speech bubbles + captions (vector shape via painter) ──
  Widget _buildTextElement(BuildContext context) {
    final isCaption = data.type == 'caption';
    final w = data.width * _panel.width * _scale;
    final hasTail = !isCaption && _anchorX >= 0 && _anchorY >= 0;
    // Tail tip relative to the bubble's eventual center: anchor minus the
    // element center, in panel pixels. The painter adds its own center.
    final tailFromCenter =
        hasTail ? _anchorPx - _centerPx - const Offset(0, 26) : Offset.zero;

    final bubble = SpeechBubbleView(
      text: data.text,
      style: isCaption ? 'captionBox' : data.style,
      maxWidth: w,
      fill: isCaption ? const Color(0xE60B1531) : null,
      outline: isCaption ? Colors.white24 : null,
      textColor: isCaption ? Colors.white : null,
      tailFromCenter: tailFromCenter,
      hasTail: hasTail,
      editMode: widget.editMode,
      onTapEdit: widget.onEdit,
      onGestureStart: _begin,
      onPan: (delta) => setState(() {
        _x += delta.dx / _panel.width;
        _y += delta.dy / _panel.height;
      }),
      onScale: (scale, angle) => setState(() {
        _scale = (_scale * scale).clamp(0.5, 3.0);
        if (isCaption) _rotation += angle;
      }),
      onGestureEnd: _commit,
    );

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Transform.rotate(angle: isCaption ? _rotation : 0, child: bubble),
        if (widget.editMode && data.type == 'speech_bubble')
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _begin(),
            onPanUpdate: (d) => setState(() {
              _anchorX = (_anchorX < 0 ? _x : _anchorX);
              _anchorY = (_anchorY < 0 ? _y + 0.14 : _anchorY);
              _anchorX =
                  (_anchorX + d.delta.dx / _panel.width).clamp(0.0, 1.0);
              _anchorY =
                  (_anchorY + d.delta.dy / _panel.height).clamp(0.0, 1.0);
            }),
            onPanEnd: (_) => _commit(),
            child: const SizedBox(
              width: _kHandle,
              height: _kHandle,
              child: Icon(Icons.arrow_downward_rounded,
                  size: 20, color: BookNestColors.cyan),
            ),
          ),
      ],
    );

    return Positioned(
      left: _centerPx.dx - w / 2,
      top: _centerPx.dy - 40 * _scale,
      child: column,
    );
  }

  Widget _gestures({required Widget child}) {
    if (!widget.editMode) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (_) => _begin(),
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: (_) => _commit(),
      child: child,
    );
  }

  List<Widget> _imageHandles(double boxSize) {
    return [
      // delete — top-right, 44dp target
      Positioned(
        right: -6,
        top: -6,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onDelete,
          child: const SizedBox(
            width: _kHandle,
            height: _kHandle,
            child: Icon(Icons.cancel_rounded,
                size: 22, color: Colors.redAccent),
          ),
        ),
      ),
      // rotate — bottom-right, 44dp target
      Positioned(
        right: -6,
        bottom: -6,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _begin(),
          onPanUpdate: (d) {
            setState(() {
              _rotation += d.delta.dx / 120;
            });
          },
          onPanEnd: (_) => _commit(),
          child: const SizedBox(
            width: _kHandle,
            height: _kHandle,
            child: Icon(Icons.rotate_right_rounded,
                size: 20, color: BookNestColors.cyan),
          ),
        ),
      ),
    ];
  }
}

// ── The canvas itself ──────────────────────────────────────────────────────

/// Renders one comic page. In edit mode every element gains handles and
/// gestures; in read-only mode it is pure ink. Changes flow back through
/// [onPanelsChanged] — once per completed gesture, never per frame.
class ComicCanvasWidget extends StatelessWidget {
  final ComicPageData page;
  final bool editMode;
  final ValueChanged<List<ComicPanelData>>? onPanelsChanged;
  final VoidCallback? onElementGestureStart;
  final VoidCallback? onElementGestureEnd;
  final Future<String?> Function(ComicPanelData panel)? addArt;
  final Future<ComicElementData?> Function(ComicElementData current)?
      editLettering;

  const ComicCanvasWidget({
    super.key,
    required this.page,
    this.editMode = false,
    this.onPanelsChanged,
    this.onElementGestureStart,
    this.onElementGestureEnd,
    this.addArt,
    this.editLettering,
  });

  double _ratio(String tag, {required double fallback}) {
    final parts = tag.split(':');
    if (parts.length == 2) {
      final a = double.tryParse(parts[0]);
      final b = double.tryParse(parts[1]);
      if (a != null && b != null && a > 0 && b > 0) return a / b;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AspectRatio(
      aspectRatio: _ratio(page.aspectRatio, fallback: 3 / 4),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF0A1322) : Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final pageSize =
              Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final panel in page.panels)
                _panel(context, panel, pageSize, dark),
            ],
          );
        }),
      ),
    );
  }

  Widget _panel(BuildContext context, ComicPanelData panel, Size pageSize,
      bool dark) {
    final rect = Rect.fromLTWH(
      panel.x * pageSize.width,
      panel.y * pageSize.height,
      panel.width * pageSize.width,
      panel.height * pageSize.height,
    );
    final inner = Size(rect.width, rect.height);
    return Positioned(
      left: rect.left,
      top: rect.top,
      child: ClipRect(
        // Hard gutters: nothing leaks out of a panel, per spec.
        child: Container(
          width: rect.width,
          height: rect.height,
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF0D1729) : Colors.white,
            border: Border.all(
                color: dark ? Colors.white : const Color(0xFF0B1531),
                width: 2.5),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (final element in panel.elements)
                TransformableElementWidget(
                  key: ValueKey(element.id),
                  data: element,
                  panelSize: inner,
                  editMode: editMode,
                  onGestureStart: onElementGestureStart,
                  onGestureEnd: (next) => _elementChanged(panel, next),
                  onDelete: () => _elementRemoved(panel, element),
                  onEdit: () => _elementEdited(panel, element),
                ),
              if (editMode && panel.elements.isEmpty)
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => addArt?.call(panel),
                        icon: const Icon(Icons.add_photo_alternate_outlined,
                            color: BookNestColors.cyan),
                        tooltip: 'Add art',
                      ),
                      IconButton(
                        onPressed: () => _addBubble(panel),
                        icon: const Icon(Icons.chat_bubble_outline_rounded,
                            color: BookNestColors.cyan),
                        tooltip: 'Add lettering',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _emit(List<ComicPanelData> panels) => onPanelsChanged?.call(panels);

  void _elementChanged(ComicPanelData panel, ComicElementData next) {
    _emit([
      for (final p in page.panels)
        if (p.id == panel.id)
          p.withElements([
            for (final e in p.elements) e.id == next.id ? next : e,
          ])
        else
          p,
    ]);
  }

  void _elementRemoved(ComicPanelData panel, ComicElementData element) {
    _emit([
      for (final p in page.panels)
        if (p.id == panel.id)
          p.withElements([
            for (final e in p.elements)
              if (e.id != element.id) e,
          ])
        else
          p,
    ]);
  }

  Future<void> _elementEdited(
      ComicPanelData panel, ComicElementData element) async {
    final edited = await editLettering?.call(element);
    if (edited == null) return;
    if (edited.text.trim().isEmpty) {
      _elementRemoved(panel, element);
      return;
    }
    _elementChanged(panel, edited);
  }

  Future<void> _addBubble(ComicPanelData panel) async {
    final el = ComicElementData(
      id: 'e${DateTime.now().microsecondsSinceEpoch % 100000000}',
      type: 'speech_bubble',
      style: 'roundedBox',
      text: 'Say something…',
      x: 0.5,
      y: 0.26,
      width: 0.52,
      anchorX: 0.5,
      anchorY: 0.6,
    );
    final edited = await editLettering?.call(el);
    if (edited == null || edited.text.trim().isEmpty) return;
    _emit([
      for (final p in page.panels)
        if (p.id == panel.id) p.withElements([...p.elements, edited]) else p,
    ]);
  }
}

// Serialization helper for whole canvases kept outside this file:
String comicPagesToJson(List<ComicPageData> pages) =>
    jsonEncode(ComicPageData.listToJson(pages));
List<ComicPageData> comicPagesFromJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is List) return ComicPageData.listFromJson(decoded);
  return const [];
}
