import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// ───────────────────────────────────────────────────────────────────────────
/// The Page-Flip Runner — BookNest's micro-interaction loader.
///
/// An ice-white runner jogs across an isometric open book whose pages flip
/// on bent arc paths beneath the stride. `progress` (0–100) drives a
/// non-linear acceleration: past 30 the stride frequency multiplies, the
/// character leans into a sprint and sky-blue speed trails stretch off the
/// fast limbs. `isComplete` interrupts everything with a finish-line jump:
/// launch, mid-air tuck, then a glowing ocean-blue particle dissolve.
///
/// Motion contract (mirrored 1:1 by tools/page_flip_runner_proto.py and
/// docs/PAGE_FLIP_RUNNER_SPEC.md — keep the three in sync):
///   · stride freq: 2.0→2.6 Hz (jog 0–30), 2.6→5.2 Hz (sprint 30–90, cubic)
///   · page flips ride sin/cos arc paths, never flat rotations
///   · foot strikes fire ocean-blue kinetic sparks
///   · zero linear interpolation: every value rides a cubic ease
class PageFlipLoader extends StatefulWidget {
  const PageFlipLoader({
    super.key,
    this.progress = 0,
    this.isComplete = false,
    this.onCompleted,
    this.size = 240,
  });

  /// 0.0 – 100.0. Drives the jog → sprint acceleration curve.
  final double progress;

  /// Fire once to interrupt the run with the finish-line jump + dissolve.
  final bool isComplete;

  /// Called when the dissolve has fully played out.
  final VoidCallback? onCompleted;

  /// Square edge of the canvas in logical pixels.
  final double size;

  @override
  State<PageFlipLoader> createState() => _PageFlipLoaderState();
}

class _PageFlipLoaderState extends State<PageFlipLoader>
    with SingleTickerProviderStateMixin {
  static const double _finishSeconds = 38 / 30; // 38 frames @30fps

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _simTime = 0;      // seconds while running
  double _phase = 0;        // stride phase accumulator [0,1)
  double _finishT = -1;     // <0 running; 0..1 the jump timeline
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(covariant PageFlipLoader old) {
    super.didUpdateWidget(old);
    if (widget.isComplete && !old.isComplete && _finishT < 0) {
      _finishT = 0;
    }
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    if (_finishT < 0) {
      _simTime += dt;
      final p = widget.progress.clamp(0.0, 100.0);
      _phase = (_phase + _strideFreq(p) * dt) % 1.0;
    } else if (_finishT < 1) {
      _finishT = math.min(1.0, _finishT + dt / _finishSeconds);
      if (_finishT >= 1 && !_fired) {
        _fired = true;
        widget.onCompleted?.call();
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ── motion curves (source of truth — mirrored in the proto + spec) ──────
  static double _strideFreq(double progress) {
    if (progress <= 30) return 2.0 + (progress / 30.0) * 0.6;
    return 2.6 + _easeInCubic((progress - 30) / 60.0) * 2.6;
  }

  static double _leanDeg(double progress) {
    if (progress <= 30) return 5 + (progress / 30.0) * 3;
    return 8 + _easeInCubic(((progress - 30) / 60.0).clamp(0.0, 1.0)) * 15;
  }

  static double _trail01(double progress) {
    if (progress <= 30) return 0.15 + (progress / 30.0) * 0.15;
    return 0.30 + _easeInCubic(((progress - 30) / 60.0).clamp(0.0, 1.0)) * 0.65;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _RunnerPainter(
          simTime: _simTime,
          phase: _phase,
          progress: widget.progress.clamp(0.0, 100.0),
          finishT: _finishT,
        ),
      ),
    );
  }
}

class _RunnerPainter extends CustomPainter {
  _RunnerPainter({
    required this.simTime,
    required this.phase,
    required this.progress,
    required this.finishT,
  });

  final double simTime;
  final double phase;
  final double progress;
  final double finishT;

  static const double _design = 480;
  static const double _cx = 240, _groundY = 322, _runnerLift = 30;
  static const double _bookHalf = 92;

  // Palette (asset contract): ice-white figure, sky/ocean accents.
  static const Color ice = Color(0xFFFFFFFF);
  static const Color iceBack = Color(0xFFD4E3F4);
  static const Color sky = Color(0xFF87CEEB);
  static const Color ocean = Color(0xFF0077BE);
  static const Color paper = Color(0xFFEEF4FC);
  static const Color paperEdge = Color(0xFF87CEEB);
  static const Color coverL = Color(0xFF1A2542);
  static const Color coverR = Color(0xFF212F52);

  static double _easeInCubic(double t) => t * t * t;
  static double _easeInOut(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
  static double _clamp(double v, double lo, double hi) =>
      math.max(lo, math.min(hi, v));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final s = size.width / _design;
    canvas.scale(s);

    final t = simTime;
    final double speed01, tuck, air, effFinish;
    if (finishT < 0) {
      effFinish = -1;
      speed01 = _clamp((progress - 30) / 60.0, 0, 1);
      tuck = 0;
      air = 0;
    } else {
      effFinish = finishT;
      speed01 = 1;
      tuck = _easeInOut(_clamp((effFinish - 0.10) / 0.32, 0, 1));
      air = effFinish > 0.08
          ? math.sin(_clamp((effFinish - 0.08) / 0.52, 0, 1) * math.pi) * 84
          : 0.0;
    }
    final effPhase = effFinish < 0 ? phase : 0.18 + effFinish * 0.35;
    final lean =
        (progress <= 30 ? 5 + (progress / 30) * 3 : 8 + _easeInCubic(
            _clamp((progress - 30) / 60, 0, 1)) * 15) * (1 - tuck * 0.6);
    final gy = _groundY - _runnerLift - air;

    _paintBook(canvas, effPhase, effFinish);
    _paintTrailsAndRunner(canvas, t, effPhase, effFinish, speed01, tuck,
        lean, gy);
    if (effFinish >= 0.40) _paintBurst(canvas, effFinish, gy);
    canvas.restore();
  }

  // ── isometric book ───────────────────────────────────────────────────────
  Offset _iso(double x, double y, double gy) =>
      Offset(_cx + (x - y), gy + (x + y) * 0.5 - 26);

  void _paintBook(Canvas canvas, double effPhase, double effFinish) {
    final gy = _groundY - _runnerLift;
    Offset iso(double x, double y) => _iso(x, y, gy);

    Path quadPath(List<Offset> q) =>
        Path()..addPolygon(q, true);

    final coverL = [
      iso(-_bookHalf - 9, -78), iso(1, -78), iso(1, 78), iso(-_bookHalf - 9, 78)
    ];
    final coverR = [
      iso(-1, -78), iso(_bookHalf + 9, -78), iso(_bookHalf + 9, 78), iso(-1, 78)
    ];
    final rim = sky.withOpacity(.51);
    canvas.drawPath(quadPath(coverL), Paint()..color = coverL);
    canvas.drawPath(quadPath(coverR), Paint()..color = coverR);
    for (final c in [coverL, coverR]) {
      final p = quadPath(c)..close();
      canvas.drawPath(p, Paint()..style = PaintingStyle.stroke..strokeWidth = 2
          ..color = rim);
    }
    final stack = Paint()..color = const Color(0xFFCDDCF0).withOpacity(.22);
    final stack2 = Paint()..color = const Color(0xFFC6D6EE).withOpacity(.19);
    for (final off in const [4.0, 8.0]) {
      canvas.drawPath(
          quadPath([
            iso(-_bookHalf - 9 + off * .6, -78 + off), iso(-2, -78 + off),
            iso(-2, 78 - off), iso(-_bookHalf - 9 + off * .6, 78 - off)
          ]),
          stack);
      canvas.drawPath(
          quadPath([
            iso(2, -78 + off), iso(_bookHalf + 9 - off * .6, -78 + off),
            iso(_bookHalf + 9 - off * .6, 78 - off), iso(2, 78 - off)
          ]),
          stack2);
    }
    final deck = Paint()..color = paper.withOpacity(.43);
    canvas.drawPath(
        quadPath([
          iso(-_bookHalf, -74), iso(-3, -74), iso(-3, 74), iso(-_bookHalf, 74)
        ]),
        deck);
    canvas.drawPath(
        quadPath([
          iso(3, -74), iso(_bookHalf, -74), iso(_bookHalf, 74), iso(3, 74)
        ]),
        deck);

    // flipping pages on bent arcs
    List<double> flips;
    if (effFinish < 0) {
      flips = [(effPhase * 0.9 + 0.00) % 1.0, (effPhase * 0.9 + 0.33) % 1.0,
        (effPhase * 0.9 + 0.66) % 1.0];
    } else {
      flips = [
        math.min(1.0, effFinish * 1.3),
        math.max(0.0, 0.5 - effFinish * 0.9),
        math.max(0.0, 0.85 - effFinish * 1.1)
      ];
    }
    for (final fpRaw in flips) {
      final fp = _clamp(fpRaw, 0, 1);
      final lift = math.sin(fp * math.pi);
      final side = math.cos(fp * math.pi);
      const rows = 8;
      final arc = <Offset>[];
      for (var i = 0; i <= rows; i++) {
        final tt = i / rows;
        final d = _bookHalf * (1 - 2 * tt);
        final z = lift * 96 * (0.55 + 0.45 * math.cos(tt * math.pi));
        final x = side * d * (0.82 + 0.18 * side);
        final y = -d * (0.25 + 0.20 * (1 - side.abs()));
        final p = iso(x, y);
        arc.add(Offset(p.dx, p.dy - z));
      }
      final paperPaint = Paint()..color = paper.withOpacity(1 - 0.26 * fp);
      final band = Path();
      for (var i = 0; i < rows; i++) {
        band
          ..moveTo(arc[i].dx, arc[i].dy)
          ..lineTo(arc[i + 1].dx, arc[i + 1].dy)
          ..lineTo(arc[i + 1].dx, arc[i + 1].dy + 6)
          ..lineTo(arc[i].dx, arc[i].dy + 6)
          ..close();
        canvas.drawPath(band, paperPaint);
        band.reset();
      }
      canvas.drawPath(
          Path()..addPolygon(arc, false),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..color = paperEdge.withOpacity(.82));
    }
    canvas.drawLine(iso(0, -78), iso(0, 78),
        Paint()..color = sky.withOpacity(.27)..strokeWidth = 2);
  }

  // ── runner ───────────────────────────────────────────────────────────────
  List<Offset> _pose(double ph, double lean, double speed01, double tuck,
      double air) {
    final s = math.sin(ph * 2 * math.pi);
    final bob = -s.abs() * 6 * (1 - tuck);
    Offset hip = Offset(0, -46 + bob - air);
    final sh = Offset(5 + lean * .24, -88 + bob * .8 - air + tuck * 7);
    final head = Offset(11 + lean * .42, -106 + bob * .7 - air + tuck * 9);
    final stride = 27 + speed01 * 17;
    final lift = 24 + speed01 * 15;
    return [
      hip,
      sh,
      head,
      Offset(s * stride * .62, 2 - lift * math.max(0, s) * (1 - tuck * .8)),
      Offset(s * stride, 30 - lift * math.max(0, s) * (1 - tuck * .9) - air * .15),
      Offset(-s * stride * .55, 2 - lift * math.max(0, -s) * .7 * (1 - tuck)),
      Offset(-s * stride * .92, 30 - lift * math.max(0, -s) * (1 - tuck) - air * .15),
      Offset(sh.dx + 15 + (-s * .95) * 9, sh.dy + 27 - tuck * 12),
      Offset(sh.dx + 24 + (-s * .95) * 15, sh.dy + 42 - tuck * 26 + (-s * .95) * 5),
      Offset(sh.dx - 11 + (-s * .95) * 7, sh.dy + 25 - tuck * 14),
      Offset(sh.dx - 18 + (-s * .95) * 13, sh.dy + 38 - tuck * 30 - (-s * .95) * 5),
    ];
  }

  void _paintTrailsAndRunner(Canvas canvas, double t, double ph,
      double effFinish, double speed01, double tuck, double lean, double gy) {
    final alive = effFinish < 0 || effFinish < 0.42;
    Offset? footWorld;
    if (!alive) return;
    final joints = _pose(ph, lean, speed01, tuck, air);
    // lean rotation about the hip
    final r = lean * math.pi / 180;
    final cr = math.cos(r), sr = math.sin(r);
    Offset rot(Offset p) {
      final ox = joints[0].dx, oy = joints[0].dy;
      return Offset((p.dx - ox) * cr - (p.dy - oy) * sr + ox,
          (p.dx - ox) * sr + (p.dy - oy) * cr + oy);
    }

    final hip = rot(joints[0]);
    final sh = rot(joints[1]);
    final head = rot(joints[2]);
    final kneeF = rot(joints[3]), footF = rot(joints[4]);
    final kneeB = rot(joints[5]), footB = rot(joints[6]);
    final elbowF = rot(joints[7]), handF = rot(joints[8]);
    final elbowB = rot(joints[9]), handB = rot(joints[10]);
    Offset T(Offset p) => Offset(_cx + p.dx, gy + p.dy);

    final back = Paint()
      ..color = iceBack
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final front = Paint()
      ..color = ice
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    final backArm = Paint()..color = iceBack..strokeWidth = 7..strokeCap =
        StrokeCap.round;
    final frontArm = Paint()..color = ice..strokeWidth = 9..strokeCap =
        StrokeCap.round;

    void limb(Offset a, Offset b, Offset c, Paint paint) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy);
      canvas.drawPath(path, paint);
    }

    limb(T(hip), T(kneeB), T(footB), back);
    limb(T(sh), T(elbowB), T(handB), backArm);

    // torso — tapered quad, real mass
    final perp = Offset(-(sh.dy - hip.dy), sh.dx - hip.dx);
    final plen = perp.distance;
    final n = plen == 0 ? Offset.zero : perp / plen;
    final torso = Path()
      ..addPolygon([
        T(sh + n * 10.5), T(sh - n * 10.5), T(hip - n * 6.5), T(hip + n * 6.5),
      ], true);
    canvas.drawPath(torso, Paint()..color = ice);

    // head + hair + twin scarf ribbons (secondary motion)
    final h = T(head);
    canvas.drawCircle(h, 13, Paint()..color = ice);
    final hair = Path()..moveTo(h.dx - 7, h.dy - 5);
    for (var seg = 1; seg <= 5; seg++) {
      hair.lineTo(h.dx - 7 - seg * (10 + speed01 * 7),
          h.dy - 5 + seg * 3.2 +
              math.sin(t * 14 + seg) * (2 + 4 * speed01));
    }
    canvas.drawPath(
        hair, Paint()..color = ice..strokeWidth = 5..strokeCap = StrokeCap.round);
    for (var ribbon = 0; ribbon < 2; ribbon++) {
      final pts = Path()..moveTo(T(sh).dx, T(sh).dy);
      for (var seg = 1; seg <= 6; seg++) {
        pts.lineTo(_cx + sh.dx - seg * (9 + speed01 * 9),
            gy + sh.dy + 4 + seg * 2.4 +
                math.sin(t * (11 + ribbon * 2.3) + seg * 1.1 + ribbon) *
                    (2 + 6 * speed01));
      }
      canvas.drawPath(
          pts,
          Paint()
            ..color = const Color(0xFFC6DEF6).withOpacity(.88)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round);
    }

    // speed trails: stretch back off the fast limbs with velocity
    if (effFinish < 0 && speed01 > 0.12) {
      final streak = _trail01Static(progress) * 130;
      final anchors = <Offset, double>{handF: 4, footF: 5};
      if (speed01 > 0.5) anchors[head] = 3;
      anchors.forEach((joint, wd) {
        final j = T(joint);
        final mid = Offset(j.dx - streak * .55, j.dy + 2 - speed01 * 2);
        final tip = Offset(j.dx - streak, j.dy + 5 - speed01 * 5);
        canvas.drawLine(
            j, mid,
            Paint()
              ..color = sky.withOpacity(.47 + .35 * speed01)
              ..strokeWidth = wd
              ..strokeCap = StrokeCap.round);
        canvas.drawLine(
            mid, tip,
            Paint()
              ..color = sky.withOpacity(.20 + .27 * speed01)
              ..strokeWidth = math.max(2, wd - 2)
              ..strokeCap = StrokeCap.round);
      });
    }

    limb(T(hip), T(kneeF), T(footF), front);
    limb(T(sh), T(elbowF), T(handF), frontArm);
    footWorld = T(footF);

    // kinetic sparks on the strike
    if (effFinish < 0 && footWorld != null) {
      final strike = math.sin(ph * 2 * math.pi);
      if (strike > 0.90) {
        final t0 = (strike - 0.90) / 0.10;
        for (var i = 0; i < 5; i++) {
          final ang = (-64 + i * 26) * math.pi / 180;
          final spd = 20.0 + (i % 3) * 9;
          final px = footWorld!.dx + math.cos(ang) * spd * t0 * 1.6;
          final py = footWorld.dy + math.sin(ang) * spd * t0 * 1.2 + 26 * t0 * t0;
          final r = 3.0 * (1 - t0) + 0.8;
          canvas.drawCircle(
              Offset(px, py), r,
              Paint()
                ..color = (i.isOdd ? ocean : sky).withOpacity(1 - t0));
        }
      }
    }
  }

  static double _trail01Static(double progress) {
    if (progress <= 30) return 0.15 + (progress / 30) * 0.15;
    return 0.30 + _easeInCubic(_clamp((progress - 30) / 60, 0, 1)) * 0.65;
  }

  // ── finish dissolve ──────────────────────────────────────────────────────
  void _paintBurst(Canvas canvas, double effFinish, double gyNow) {
    final airApex =
        math.sin(_clamp((0.42 - 0.08) / 0.52, 0, 1) * math.pi) * 84;
    final bx = _cx + 18;
    final by = _groundY - _runnerLift - airApex - 104;
    final bt = _clamp((effFinish - 0.40) / 0.60, 0, 1);
    if (bt < 0.32) {
      final k = bt / 0.32;
      final rect = Rect.fromCenter(
          center: Offset(bx, by),
          width: (14 + 86 * k) * 2,
          height: (14 + 86 * k) * 1.6);
      canvas.drawOval(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = ocean.withOpacity(1 - k));
    }
    for (var i = 0; i < 130; i++) {
      final j1 = (((i + 1) * 2654435761) % 1000) / 1000.0;
      final j2 = (((i + 1) * 40503) % 997) / 997.0;
      final j3 = (((i + 1) * 69069) % 991) / 991.0;
      final delay = 0.30 * j3;
      final ptT = _clamp((bt - delay) / math.max(0.001, 1.0 - delay), 0, 1);
      if (ptT <= 0) continue;
      final ang = 2 * math.pi * ((i * 0.6180339887) % 1.0) + (j1 - 0.5) * 0.5;
      final spd = 34 + 118 * j2;
      final dist = spd * ptT * (1.0 - 0.22 * ptT);
      final px = bx + math.cos(ang) * dist * 2.3;
      final py = by + math.sin(ang) * dist * 1.65 - 52 * ptT + 96 * ptT * ptT;
      final r = (1.6 + 3.0 * j2) * (1 - 0.7 * ptT) + 0.5;
      final fade = (1 - ptT) * (1 - bt * 0.35);
      final col = i % 3 == 0 ? sky : ocean;
      final tailT = math.max(0.0, ptT - 0.14);
      final tDist = spd * tailT * (1.0 - 0.22 * tailT);
      canvas.drawLine(
          Offset(bx + math.cos(ang) * tDist * 2.3,
              by + math.sin(ang) * tDist * 1.65 - 52 * tailT + 96 * tailT * tailT),
          Offset(px, py),
          Paint()
            ..color = col.withOpacity((fade * .5).clamp(0, 1))
            ..strokeWidth = math.max(2, r)
            ..strokeCap = StrokeCap.round);
      canvas.drawCircle(Offset(px, py), r,
          Paint()..color = col.withOpacity((fade * .94 + .06).clamp(0, 1)));
      if (i % 5 == 0 && ptT < 0.25) {
        canvas.drawCircle(
            Offset(px, py),
            math.max(0.5, r * 0.4),
            Paint()
              ..color = const Color(0xFFFFFFFF)
                  .withOpacity((1 - ptT * 4).clamp(0, 1)));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RunnerPainter old) =>
      old.simTime != simTime ||
      old.phase != phase ||
      old.progress != progress ||
      old.finishT != finishT;
}
