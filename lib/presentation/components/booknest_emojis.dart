import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// BookNest Emotes — our own emoji set, drawn entirely in code in the
/// BookNest visual language (navy / cyan / white / mint / lavender).
/// 36 static + 12 animated emotes. Nothing here is a system glyph:
/// every face and object is painted by [BookNestEmojiPainter], and the
/// animated ones are driven live in the chat.
/// ─────────────────────────────────────────────────────────────────────────────

enum EmojiEyes { dot, happy, closed, wink, star, heart, sunglasses, glasses, sleepy }

enum EmojiMouth { smile, grin, smallO, tongue, flat, frown, catSmile }

enum EmojiAccessory { none, halo, wizardHat, headphones }

enum EmojiObject {
  openBook,
  bookStack,
  quill,
  bookmark,
  owl,
  bookHeart,
  lamp,
  coffee,
  moon,
  star,
  heart,
  sparkles,
  bookworm,
  shelf,
  scroll,
  medal,
  comet,
}

enum EmojiEffect {
  none,
  bounce,
  winkLoop,
  spin,
  pulse,
  shake,
  heartbeat,
  orbit,
  floatUp,
  drip,
  shine,
  twinkle,
  floatZ,
}

class EmojiDef {
  final String code;
  final String label;
  final EmojiEyes? eyes;
  final EmojiMouth? mouth;
  final EmojiAccessory accessory;
  final Color face;
  final EmojiObject? object;
  final EmojiEffect effect;

  const EmojiDef({
    required this.code,
    required this.label,
    this.eyes,
    this.mouth,
    this.accessory = EmojiAccessory.none,
    this.face = BookNestEmojiPalette.cyan,
    this.object,
    this.effect = EmojiEffect.none,
  });

  bool get isAnimated => effect != EmojiEffect.none;
}

abstract class BookNestEmojiPalette {
  static const cyan = Color(0xFF00E5FF);
  static const navy = Color(0xFF102A56);
  static const navyDeep = Color(0xFF071A3D);
  static const white = Color(0xFFF7FAFF);
  static const mint = Color(0xFF7BF1D9);
  static const lavender = Color(0xFFC3B7FF);
  static const skyBlue = Color(0xFF8FC6FF);
  static const blushPink = Color(0xFFFF9EC0);
}

const List<EmojiDef> bookNestEmotes = [
  // ── faces ──
  EmojiDef(code: 'bookjoy', label: 'Book joy', eyes: EmojiEyes.happy, mouth: EmojiMouth.smile),
  EmojiDef(code: 'booklaugh', label: 'Laughing', eyes: EmojiEyes.happy, mouth: EmojiMouth.grin, face: BookNestEmojiPalette.navy),
  EmojiDef(code: 'booklove', label: 'Book love', eyes: EmojiEyes.heart, mouth: EmojiMouth.smile, face: BookNestEmojiPalette.lavender),
  EmojiDef(code: 'bookwink', label: 'Wink', eyes: EmojiEyes.wink, mouth: EmojiMouth.catSmile),
  EmojiDef(code: 'bookcool', label: 'Cool reader', eyes: EmojiEyes.sunglasses, mouth: EmojiMouth.smile, face: BookNestEmojiPalette.navy),
  EmojiDef(code: 'booksleepy', label: 'Sleepy', eyes: EmojiEyes.sleepy, mouth: EmojiMouth.flat, face: BookNestEmojiPalette.lavender),
  EmojiDef(code: 'bookcry', label: 'Crying', eyes: EmojiEyes.closed, mouth: EmojiMouth.frown, face: BookNestEmojiPalette.skyBlue),
  EmojiDef(code: 'bookshock', label: 'Shocked', eyes: EmojiEyes.dot, mouth: EmojiMouth.smallO, face: BookNestEmojiPalette.white),
  EmojiDef(code: 'booktongue', label: 'Cheeky', eyes: EmojiEyes.happy, mouth: EmojiMouth.tongue, face: BookNestEmojiPalette.mint),
  EmojiDef(code: 'booknerd', label: 'Nerd', eyes: EmojiEyes.glasses, mouth: EmojiMouth.smile, face: BookNestEmojiPalette.white),
  EmojiDef(code: 'booksmile', label: 'Smile', eyes: EmojiEyes.dot, mouth: EmojiMouth.smile, face: BookNestEmojiPalette.white),
  EmojiDef(code: 'bookthink', label: 'Thinking', eyes: EmojiEyes.dot, mouth: EmojiMouth.flat, face: BookNestEmojiPalette.mint),
  EmojiDef(code: 'bookangry', label: 'Grumpy', eyes: EmojiEyes.dot, mouth: EmojiMouth.frown, face: BookNestEmojiPalette.navyDeep),
  EmojiDef(code: 'bookhalo', label: 'Angel', eyes: EmojiEyes.happy, mouth: EmojiMouth.smile, accessory: EmojiAccessory.halo, face: BookNestEmojiPalette.white),
  EmojiDef(code: 'bookwizard', label: 'Story wizard', eyes: EmojiEyes.happy, mouth: EmojiMouth.smile, accessory: EmojiAccessory.wizardHat, face: BookNestEmojiPalette.navy),
  EmojiDef(code: 'bookphones', label: 'Audiobook time', eyes: EmojiEyes.closed, mouth: EmojiMouth.smile, accessory: EmojiAccessory.headphones),
  EmojiDef(code: 'bookstarry', label: 'Starstruck', eyes: EmojiEyes.star, mouth: EmojiMouth.smallO),
  EmojiDef(code: 'bookzzz', label: 'Asleep', eyes: EmojiEyes.closed, mouth: EmojiMouth.flat, face: BookNestEmojiPalette.navy),
  // ── objects ──
  EmojiDef(code: 'openbook', label: 'Open book', object: EmojiObject.openBook),
  EmojiDef(code: 'bookstack', label: 'Book stack', object: EmojiObject.bookStack),
  EmojiDef(code: 'quill', label: 'Quill', object: EmojiObject.quill),
  EmojiDef(code: 'bookmark', label: 'Bookmark', object: EmojiObject.bookmark),
  EmojiDef(code: 'owl', label: 'BookNest owl', object: EmojiObject.owl),
  EmojiDef(code: 'bookheart', label: 'Book heart', object: EmojiObject.bookHeart),
  EmojiDef(code: 'lamp', label: 'Reading lamp', object: EmojiObject.lamp),
  EmojiDef(code: 'coffee', label: 'Coffee break', object: EmojiObject.coffee),
  EmojiDef(code: 'moon', label: 'Late-night read', object: EmojiObject.moon),
  EmojiDef(code: 'star', label: 'Star', object: EmojiObject.star),
  EmojiDef(code: 'heart', label: 'Heart', object: EmojiObject.heart),
  EmojiDef(code: 'sparkles', label: 'Sparkles', object: EmojiObject.sparkles),
  EmojiDef(code: 'bookworm', label: 'Bookworm', object: EmojiObject.bookworm),
  EmojiDef(code: 'shelf', label: 'Library shelf', object: EmojiObject.shelf),
  EmojiDef(code: 'scroll', label: 'Scroll', object: EmojiObject.scroll),
  EmojiDef(code: 'medal', label: 'Reading medal', object: EmojiObject.medal),
  EmojiDef(code: 'comet', label: 'Comet', object: EmojiObject.comet),
  EmojiDef(code: 'nest', label: 'The Nest', object: EmojiObject.bookStack, face: BookNestEmojiPalette.cyan),
  // ── animated ──
  EmojiDef(code: 'bounce-heart', label: 'Bouncing heart', object: EmojiObject.heart, effect: EmojiEffect.bounce),
  EmojiDef(code: 'wink-loop', label: 'Winking', eyes: EmojiEyes.wink, mouth: EmojiMouth.catSmile, effect: EmojiEffect.winkLoop),
  EmojiDef(code: 'spin-star', label: 'Spinning star', object: EmojiObject.star, effect: EmojiEffect.spin),
  EmojiDef(code: 'pulse-moon', label: 'Glowing moon', object: EmojiObject.moon, effect: EmojiEffect.pulse),
  EmojiDef(code: 'shake-laugh', label: 'Cracking up', eyes: EmojiEyes.happy, mouth: EmojiMouth.grin, face: BookNestEmojiPalette.navy, effect: EmojiEffect.shake),
  EmojiDef(code: 'heartbeat', label: 'Heartbeat', object: EmojiObject.heart, effect: EmojiEffect.heartbeat),
  EmojiDef(code: 'party-book', label: 'Party book', object: EmojiObject.openBook, effect: EmojiEffect.orbit),
  EmojiDef(code: 'rocket-quill', label: 'Quill taking off', object: EmojiObject.quill, effect: EmojiEffect.floatUp),
  EmojiDef(code: 'cry-loop', label: 'Tears', eyes: EmojiEyes.closed, mouth: EmojiMouth.frown, face: BookNestEmojiPalette.skyBlue, effect: EmojiEffect.drip),
  EmojiDef(code: 'cool-shine', label: 'Shine', eyes: EmojiEyes.sunglasses, mouth: EmojiMouth.smile, face: BookNestEmojiPalette.navy, effect: EmojiEffect.shine),
  EmojiDef(code: 'magic-sparkle', label: 'Magic', object: EmojiObject.sparkles, effect: EmojiEffect.twinkle),
  EmojiDef(code: 'dream-z', label: 'Dreaming', eyes: EmojiEyes.sleepy, mouth: EmojiMouth.flat, face: BookNestEmojiPalette.lavender, effect: EmojiEffect.floatZ),
  // ── pack v2: new custom emotes ──
  EmojiDef(code: 'bookfever', label: 'Page fever', eyes: EmojiEyes.star, mouth: EmojiMouth.grin, face: BookNestEmojiPalette.lavender),
  EmojiDef(code: 'bookhug', label: 'Book hug', eyes: EmojiEyes.happy, mouth: EmojiMouth.catSmile, face: BookNestEmojiPalette.mint),
  EmojiDef(code: 'booksip', label: 'Tea & chapters', eyes: EmojiEyes.happy, mouth: EmojiMouth.smallO, face: BookNestEmojiPalette.white),
  EmojiDef(code: 'bookmystery', label: 'Mystery', eyes: EmojiEyes.glasses, mouth: EmojiMouth.flat, face: BookNestEmojiPalette.navy),
  EmojiDef(code: 'bookfair', label: 'Book fair', eyes: EmojiEyes.dot, mouth: EmojiMouth.smile, accessory: EmojiAccessory.halo, face: BookNestEmojiPalette.mint),
  EmojiDef(code: 'poet', label: 'Poet', eyes: EmojiEyes.closed, mouth: EmojiMouth.smile, face: BookNestEmojiPalette.skyBlue),
  EmojiDef(code: 'bookpilot', label: 'Night flight reader', eyes: EmojiEyes.sunglasses, mouth: EmojiMouth.smallO, face: BookNestEmojiPalette.navyDeep),
  EmojiDef(code: 'lantern', label: 'Lantern', object: EmojiObject.lamp, face: BookNestEmojiPalette.lavender),
  EmojiDef(code: 'glasses', label: 'Reading glasses', object: EmojiObject.bookStack, face: BookNestEmojiPalette.skyBlue),
  EmojiDef(code: 'bookmarklet', label: 'Little bookmark', object: EmojiObject.bookmark, face: BookNestEmojiPalette.mint),
  EmojiDef(code: 'nightowl', label: 'Night owl', object: EmojiObject.owl, face: BookNestEmojiPalette.lavender),
  EmojiDef(code: 'loveletter', label: 'Love letter', object: EmojiObject.scroll, face: BookNestEmojiPalette.blushPink),
  // ── pack v2: twelve more animated ──
  EmojiDef(code: 'wow-shock', label: 'Wow!', eyes: EmojiEyes.dot, mouth: EmojiMouth.smallO, face: BookNestEmojiPalette.white, effect: EmojiEffect.bounce),
  EmojiDef(code: 'nerd-spin', label: 'Big brain', eyes: EmojiEyes.glasses, mouth: EmojiMouth.smile, face: BookNestEmojiPalette.white, effect: EmojiEffect.spin),
  EmojiDef(code: 'halo-float', label: 'Floating angel', eyes: EmojiEyes.happy, mouth: EmojiMouth.smile, accessory: EmojiAccessory.halo, face: BookNestEmojiPalette.white, effect: EmojiEffect.floatUp),
  EmojiDef(code: 'grumpy-shake', label: 'Grumpy', eyes: EmojiEyes.dot, mouth: EmojiMouth.frown, face: BookNestEmojiPalette.navyDeep, effect: EmojiEffect.shake),
  EmojiDef(code: 'tongue-out', label: 'Cheeky', eyes: EmojiEyes.happy, mouth: EmojiMouth.tongue, face: BookNestEmojiPalette.mint, effect: EmojiEffect.winkLoop),
  EmojiDef(code: 'starstruck-twinkle', label: 'Starstruck', eyes: EmojiEyes.star, mouth: EmojiMouth.smallO, effect: EmojiEffect.twinkle),
  EmojiDef(code: 'wizard-orbit', label: 'Casting stories', eyes: EmojiEyes.happy, mouth: EmojiMouth.smile, accessory: EmojiAccessory.wizardHat, face: BookNestEmojiPalette.navy, effect: EmojiEffect.orbit),
  EmojiDef(code: 'coffee-steam', label: 'Fresh coffee', object: EmojiObject.coffee, effect: EmojiEffect.pulse),
  EmojiDef(code: 'owl-bounce', label: 'Owl bounce', object: EmojiObject.owl, effect: EmojiEffect.bounce),
  EmojiDef(code: 'medal-shine', label: 'Shining medal', object: EmojiObject.medal, effect: EmojiEffect.shine),
  EmojiDef(code: 'comet-fly', label: 'Comet', object: EmojiObject.comet, effect: EmojiEffect.floatUp),
  EmojiDef(code: 'bookworm-wiggle', label: 'Wiggly worm', object: EmojiObject.bookworm, effect: EmojiEffect.shake),
];

EmojiDef? emojiByCode(String code) {
  for (final e in bookNestEmotes) {
    if (e.code == code) return e;
  }
  return null;
}

/// The quick-reaction row (long-press a message).
const List<String> quickReactionCodes = [
  'heart',
  'bookjoy',
  'booklaugh',
  'booklove',
  'bookshock',
  'booksleepy',
  'bookcry',
  'bounce-heart',
];

/// The heart used by the double-tap instant reaction.
const String doubleTapReactionCode = 'heart';

// ─────────────────────────────────────────────────────────────────────────────
// The widget
// ─────────────────────────────────────────────────────────────────────────────

/// A motion style per emote family — chosen from the def so faces,
/// objects and effects each move the way viewers expect.
enum _EmojiMotion { float, heartbeat, bounce, twinkle, flicker, sway }

_EmojiMotion _motionFor(EmojiDef def) {
  switch (def.effect) {
    case EmojiEffect.bounce:
    case EmojiEffect.shake:
    case EmojiEffect.orbit:
      return _EmojiMotion.bounce;
    case EmojiEffect.twinkle:
    case EmojiEffect.shine:
      return _EmojiMotion.twinkle;
    case EmojiEffect.floatUp:
    case EmojiEffect.drip:
      return _EmojiMotion.flicker;
    case EmojiEffect.pulse:
    case EmojiEffect.heartbeat:
      return _EmojiMotion.heartbeat;
    case EmojiEffect.spin:
    case EmojiEffect.winkLoop:
    case EmojiEffect.floatZ:
      return _EmojiMotion.sway;
    case EmojiEffect.none:
      break;
  }
  if (def.object == EmojiObject.heart || def.code.contains('love')) {
    return _EmojiMotion.heartbeat;
  }
  if (def.object == EmojiObject.star ||
      def.object == EmojiObject.sparkles) {
    return _EmojiMotion.twinkle;
  }
  if (def.code.contains('laugh') || def.code.contains('joy')) {
    return _EmojiMotion.bounce;
  }
  return _EmojiMotion.float;
}

Color _dominantColor(EmojiDef def) {
  if (def.face != BookNestEmojiPalette.cyan || def.object == null) {
    return def.face;
  }
  switch (def.object!) {
    case EmojiObject.heart:
      return BookNestEmojiPalette.blushPink;
    case EmojiObject.star:
    case EmojiObject.sparkles:
    case EmojiObject.lamp:
      return BookNestEmojiPalette.cyan;
    case EmojiObject.moon:
      return BookNestEmojiPalette.lavender;
    default:
      return BookNestEmojiPalette.cyan;
  }
}

/// The living BookNest emote: the hand-drawn painter wrapped in a
/// cinematic layer — a breathing glow under the artwork, a light sweep
/// across its rim, a springy entrance, and per-emote motion (heartbeats
/// double-thump, fires flicker, stars twinkle, laughs bounce).
class BookNestEmojiView extends StatefulWidget {
  final String code;
  final double size;

  /// Animated emotes only move when this is true (grids can stay calm,
  /// chat bubbles play them live).
  final bool animate;

  const BookNestEmojiView(
    this.code, {
    super.key,
    this.size = 34,
    this.animate = true,
  });

  @override
  State<BookNestEmojiView> createState() => _BookNestEmojiViewState();
}

class _BookNestEmojiViewState extends State<BookNestEmojiView>
    with TickerProviderStateMixin {
  AnimationController? _loop;
  AnimationController? _entrance;
  late final EmojiDef _def;

  EmojiDef _resolve() =>
      emojiByCode(widget.code) ??
      bookNestEmotes.firstWhere((e) => e.code == 'heart');

  @override
  void initState() {
    super.initState();
    _def = _resolve();
    if (widget.animate) {
      _loop = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2100),
      )..repeat();
      _entrance = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 420),
      )..forward();
    }
  }

  @override
  void didUpdateWidget(covariant BookNestEmojiView old) {
    super.didUpdateWidget(old);
    if (widget.animate && _loop == null) {
      _loop = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2100),
      )..repeat();
      _entrance = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 420),
      )..forward();
    }
  }

  @override
  void dispose() {
    _loop?.dispose();
    _entrance?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final def = _def;
    final size = Size(widget.size, widget.size);
    final loop = _loop?.value ?? 0;
    final entrance = _entrance == null
        ? 1.0
        : Curves.easeOutBack.transform(_entrance!.value);
    final motion = _motionFor(def);

    // ── per-motion transform ──
    var scale = entrance;
    var dy = 0.0;
    var dx = 0.0;
    var rotation = 0.0;
    var opacity = 1.0;
    switch (motion) {
      case _EmojiMotion.heartbeat:
        final beat = loop % 1.0;
        final thump = beat < .14
            ? math.sin(beat / .14 * math.pi)
            : (beat > .22 && beat < .40
                ? math.sin((beat - .22) / .18 * math.pi) * .7
                : 0.0);
        scale *= 1 + .17 * thump;
      case _EmojiMotion.bounce:
        final b = (loop * 1.5) % 1.0;
        final hop = math.sin(b * math.pi);
        dy = -size.height * .12 * hop;
        // squash & stretch
        scale *= 1 + .08 * hop;
      case _EmojiMotion.twinkle:
        final tw = (math.sin(loop * 2 * math.pi) + 1) / 2;
        opacity = .72 + .28 * tw;
        scale *= .94 + .10 * tw;
        rotation = .10 * math.sin(loop * 2 * math.pi);
      case _EmojiMotion.flicker:
        final f = loop * 3.0;
        final flick =
            (math.sin(f * math.pi) * .5 + math.sin(f * 2.7 * math.pi) * .5);
        scale *= 1 + .05 * flick;
        dy = -size.height * .03 * (1 + math.sin(f * math.pi));
      case _EmojiMotion.sway:
        rotation = .16 * math.sin(loop * 2 * math.pi);
        dx = size.width * .03 * math.sin(loop * 2 * math.pi);
      case _EmojiMotion.float:
        final idle = math.sin(loop * 2 * math.pi);
        dy = -size.height * .05 * idle;
        rotation = .06 * math.sin(loop * 2 * math.pi + .6);
        scale *= 1 + .03 * ((math.sin(loop * 4 * math.pi) + 1) / 2);
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: rotation,
            child: Transform.scale(
              scale: scale,
              child: CustomPaint(
                painter: _EmojiAuraPainter(
                  def: def,
                  t: loop,
                  motion: motion,
                ),
                foregroundPainter: _EmojiShinePainter(t: loop),
                child: CustomPaint(
                  painter: BookNestEmojiPainter(def, t: loop),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Breathing glow + rim light painted behind the emote.
class _EmojiAuraPainter extends CustomPainter {
  final EmojiDef def;
  final double t;
  final _EmojiMotion motion;

  _EmojiAuraPainter({
    required this.def,
    required this.t,
    required this.motion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.width * .52;
    final color = _dominantColor(def);
    final breath = .30 + .22 * ((math.sin(t * 2 * math.pi) + 1) / 2);
    final glow = Paint()
      ..color = color.withOpacity((motion == _EmojiMotion.flicker
              ? breath * 1.25
              : breath) *
          .55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .42);
    canvas.drawCircle(c, radius * .92, glow);
    // crisp rim
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .02
      ..color = Colors.white.withOpacity(.16);
    canvas.drawCircle(c, radius * .84, rim);
  }

  @override
  bool shouldRepaint(_EmojiAuraPainter old) =>
      old.t != t || old.def != def || old.motion != motion;
}

/// A light streak that sweeps across the emote — the "premium" tell.
class _EmojiShinePainter extends CustomPainter {
  final double t;
  _EmojiShinePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.width * .5;
    // The streak orbits once per loop; it only crosses the face part of
    // the time so the emote gets a periodic sparkle, not a strobe.
    final angle = t * 2 * math.pi - math.pi / 2;
    final visible = (t % 1.0) < .42;
    if (!visible) return;
    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .075
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: angle,
        endAngle: angle + 1.15,
        colors: [
          Colors.white.withOpacity(0),
          Colors.white.withOpacity(.42),
          Colors.white.withOpacity(0),
        ],
        transform: GradientRotation(angle),
      ).createShader(Rect.fromCircle(center: c, radius: radius));
    canvas.drawCircle(c, radius * .74, sweepPaint);
  }

  @override
  bool shouldRepaint(_EmojiShinePainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// The painter — every emote drawn from primitives
// ─────────────────────────────────────────────────────────────────────────────

class BookNestEmojiPainter extends CustomPainter {
  final EmojiDef def;

  /// Animation phase in [0,1). 0 for static emotes.
  final double t;

  BookNestEmojiPainter(this.def, {this.t = 0});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    _applyEffect(canvas, size);
    if (def.object != null) {
      _paintObject(canvas, size, def.object!);
    } else {
      _paintFace(canvas, size);
    }
    canvas.restore();
  }

  void _applyEffect(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    switch (def.effect) {
      case EmojiEffect.none:
        // Idle life: a soft bob and a gentle sway.
        final idle = math.sin(t * 2 * math.pi);
        canvas.translate(0, -size.height * .035 * idle);
        canvas.translate(c.dx, c.dy);
        canvas.rotate(.05 * idle);
        canvas.translate(-c.dx, -c.dy);
      case EmojiEffect.bounce:
        final bounce = (1 - (2 * t - 1).abs()); // 0→1→0
        canvas.translate(0, -size.height * .14 * bounce);
      case EmojiEffect.spin:
        canvas.translate(c.dx, c.dy);
        canvas.rotate(t * 6.2832);
        canvas.translate(-c.dx, -c.dy);
      case EmojiEffect.pulse:
        final glow = .5 + .5 * (1 - (2 * t - 1).abs());
        canvas.drawCircle(
          c,
          size.width * .46,
          Paint()
            ..color = BookNestEmojiPalette.cyan.withOpacity(.25 * glow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      case EmojiEffect.shake:
        canvas.translate(size.width * .05 * (t < .5 ? 1 : -1), 0);
      case EmojiEffect.heartbeat:
        final beat = t < .3
            ? 1 + .22 * (1 - (t / .3 * 2 - 1).abs())
            : (t > .45 && t < .75
                ? 1 + .16 * (1 - ((t - .45) / .3 * 2 - 1).abs())
                : 1);
        canvas.translate(c.dx, c.dy);
        canvas.scale(beat.toDouble());
        canvas.translate(-c.dx, -c.dy);
      case EmojiEffect.floatUp:
        final float = (1 - (2 * t - 1).abs());
        canvas.translate(0, -size.height * .18 * float);
      case EmojiEffect.drip || EmojiEffect.orbit || EmojiEffect.shine ||
            EmojiEffect.twinkle || EmojiEffect.floatZ || EmojiEffect.winkLoop:
        break; // handled while drawing details
    }
  }

  // ── faces ──

  void _paintFace(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * .54),
      width: size.width * .8,
      height: size.height * .8,
    );
    final radius = rect.width / 2;

    // Soft drop shadow so the face lifts off the bubble.
    canvas.drawCircle(
      rect.center.translate(0, radius * .1),
      radius,
      Paint()
        ..color = BookNestEmojiPalette.navyDeep.withOpacity(.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Body: a lit sphere, not a flat circle.
    final facePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.35, -.45),
        radius: 1.15,
        colors: [
          Color.lerp(def.face, Colors.white, .55)!,
          def.face,
          Color.lerp(def.face, BookNestEmojiPalette.navyDeep, .28)!,
        ],
        stops: const [0, .55, 1],
      ).createShader(rect);
    canvas.drawCircle(rect.center, radius, facePaint);

    // Scene-glow rim on the lower edge.
    canvas.drawCircle(
      rect.center,
      radius * .985,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .035
        ..color = BookNestEmojiPalette.cyan.withOpacity(.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Crisp sticker outline.
    canvas.drawCircle(
      rect.center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .028
        ..color = BookNestEmojiPalette.navyDeep.withOpacity(.75),
    );

    // Glossy highlight, top-left.
    canvas.save();
    canvas.clipPath(Path()
      ..addOval(Rect.fromCircle(center: rect.center, radius: radius)));
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rect.center.dx - radius * .32, rect.center.dy - radius * .45),
        width: radius * 1.05,
        height: radius * .62,
      ),
      Paint()
        ..color = Colors.white.withOpacity(.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();

    final dark = def.face == BookNestEmojiPalette.navy ||
        def.face == BookNestEmojiPalette.navyDeep;
    final ink = dark ? Colors.white : BookNestEmojiPalette.navyDeep;
    final eyeY = rect.center.dy - rect.height * .1;
    final eyeDx = rect.width * .19;
    final eyeR = rect.width * .075;
    // Every dot-eyed face blinks once per idle cycle.
    final blinkPhase = def.eyes == EmojiEyes.dot && t > .82 && t < .92;
    final winkPhase = def.effect == EmojiEffect.winkLoop
        ? (t < .15 || (t > .5 && t < .65))
        : false;

    void eye(double dx) {
      final x = rect.center.dx + dx;
      if (blinkPhase) {
        canvas.drawLine(
          Offset(x - eyeR, eyeY),
          Offset(x + eyeR, eyeY),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = eyeR * .9
            ..strokeCap = StrokeCap.round
            ..color = ink,
        );
        return;
      }
      switch (def.eyes!) {
        case EmojiEyes.dot:
          // Two-tone pupils with a catchlight.
          canvas.drawCircle(Offset(x, eyeY), eyeR, Paint()..color = ink);
          canvas.drawCircle(
              Offset(x - eyeR * .3, eyeY - eyeR * .35),
              eyeR * .32,
              Paint()..color = Colors.white.withOpacity(.9));
        case EmojiEyes.happy:
          canvas.drawArc(
            Rect.fromCircle(center: Offset(x, eyeY + eyeR * .8), radius: eyeR * 1.4),
            3.5,
            2.4,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = eyeR * .9
              ..strokeCap = StrokeCap.round
              ..color = ink,
          );
        case EmojiEyes.closed || EmojiEyes.sleepy:
          canvas.drawLine(
            Offset(x - eyeR, eyeY),
            Offset(x + eyeR, eyeY),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = eyeR * .9
              ..strokeCap = StrokeCap.round
              ..color = ink,
          );
        case EmojiEyes.wink:
          if (dx < 0 || winkPhase) {
            canvas.drawLine(
              Offset(x - eyeR, eyeY),
              Offset(x + eyeR, eyeY),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = eyeR * .9
                ..strokeCap = StrokeCap.round
                ..color = ink,
            );
          } else {
            canvas.drawCircle(Offset(x, eyeY), eyeR, Paint()..color = ink);
          }
        case EmojiEyes.star:
          _drawStar(canvas, Offset(x, eyeY), eyeR * 2.2, ink);
          canvas.drawCircle(Offset(x + eyeR * .4, eyeY - eyeR * .5),
              eyeR * .28, Paint()..color = Colors.white.withOpacity(.95));
        case EmojiEyes.heart:
          _drawHeart(canvas, Offset(x, eyeY), eyeR * 2.4,
              BookNestEmojiPalette.blushPink,
              outline: BookNestEmojiPalette.navyDeep.withOpacity(.55));
        case EmojiEyes.sunglasses:
          break; // drawn as the accessory band below
        case EmojiEyes.glasses:
          _circleOutline(canvas, Offset(x, eyeY), eyeR * 1.9, ink, eyeR * .55);
      }
    }

    eye(-eyeDx);
    eye(eyeDx);

    if (def.eyes == EmojiEyes.sunglasses) {
      final band = RRect.fromRectAndCorners(
        Rect.fromLTRB(rect.center.dx - eyeDx - eyeR * 1.7, eyeY - eyeR * 1.5,
            rect.center.dx + eyeDx + eyeR * 1.7, eyeY + eyeR * 1.5),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      );
      canvas.drawRRect(band, Paint()..color = BookNestEmojiPalette.navyDeep);
      if (def.effect == EmojiEffect.shine) {
        final glint = (1 - (2 * t - 1).abs());
        canvas.drawLine(
          Offset(rect.center.dx - eyeDx + eyeR, eyeY - eyeR),
          Offset(rect.center.dx - eyeDx + eyeR * 2, eyeY + eyeR),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = eyeR * .7
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withOpacity(.9 * glint),
        );
      }
    }

    // blush
    if (def.face == BookNestEmojiPalette.lavender ||
        def.face == BookNestEmojiPalette.white) {
      final blush = Paint()..color = BookNestEmojiPalette.blushPink.withOpacity(.5);
      canvas.drawCircle(
          Offset(rect.center.dx - eyeDx * 1.7, eyeY + eyeR * 2.6), eyeR * .8, blush);
      canvas.drawCircle(
          Offset(rect.center.dx + eyeDx * 1.7, eyeY + eyeR * 2.6), eyeR * .8, blush);
    }

    // mouth
    final mouthY = rect.center.dy + rect.height * .18;
    final mw = rect.width * .3;
    final mp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * .045
      ..strokeCap = StrokeCap.round
      ..color = ink;
    switch (def.mouth!) {
      case EmojiMouth.smile:
        // Open smile: a filled half-moon with a hint of tongue — warm at
        // every size, from keyboard thumb to bubble.
        final smilePath = Path()
          ..moveTo(rect.center.dx - mw * .42, mouthY - mw * .16)
          ..quadraticBezierTo(
              rect.center.dx, mouthY + mw * .78, rect.center.dx + mw * .42, mouthY - mw * .16)
          ..quadraticBezierTo(
              rect.center.dx, mouthY + mw * .1, rect.center.dx - mw * .42, mouthY - mw * .16)
          ..close();
        canvas.drawPath(smilePath, Paint()..color = ink);
        canvas.save();
        canvas.clipPath(smilePath);
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(rect.center.dx, mouthY + mw * .52),
              width: mw * .5,
              height: mw * .42),
          Paint()..color = BookNestEmojiPalette.blushPink,
        );
        canvas.restore();
      case EmojiMouth.catSmile:
        // The classic :3 — two bumps meeting at the centre, whisker-tipped.
        final w = mw * .52;
        canvas.drawArc(
            Rect.fromCenter(
                center: Offset(rect.center.dx - w, mouthY - w * .55),
                width: w * 2,
                height: w * 2),
            .45, 2.25, false, mp);
        canvas.drawArc(
            Rect.fromCenter(
                center: Offset(rect.center.dx + w, mouthY - w * .55),
                width: w * 2,
                height: w * 2),
            .45, 2.25, false, mp);
      case EmojiMouth.grin:
        final path = Path()
          ..moveTo(rect.center.dx - mw / 2, mouthY - mw * .2)
          ..quadraticBezierTo(rect.center.dx, mouthY + mw * .75, rect.center.dx + mw / 2, mouthY - mw * .2)
          ..close();
        canvas.drawPath(path, Paint()..color = ink);
        canvas.save();
        canvas.clipPath(path);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(rect.center.dx, mouthY + mw * .38), width: mw * .6, height: mw * .5),
          Paint()..color = BookNestEmojiPalette.blushPink,
        );
        canvas.restore();
      case EmojiMouth.smallO:
        canvas.drawCircle(Offset(rect.center.dx, mouthY), mw * .28, Paint()..color = ink);
      case EmojiMouth.tongue:
        canvas.drawArc(Rect.fromCenter(center: Offset(rect.center.dx, mouthY - mw * .3), width: mw, height: mw), .35, 2.45, false, mp);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(rect.center.dx + mw * .1, mouthY + mw * .18), width: mw * .5, height: mw * .55),
          Paint()..color = BookNestEmojiPalette.blushPink,
        );
        // The crease gives the tongue its curl.
        canvas.drawLine(
          Offset(rect.center.dx + mw * .1, mouthY + mw * .12),
          Offset(rect.center.dx + mw * .1, mouthY + mw * .42),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = mw * .05
            ..strokeCap = StrokeCap.round
            ..color = BookNestEmojiPalette.blushPink
                .withRed((BookNestEmojiPalette.blushPink.red * .6).round()),
        );
      case EmojiMouth.flat:
        canvas.drawLine(Offset(rect.center.dx - mw * .4, mouthY), Offset(rect.center.dx + mw * .4, mouthY), mp);
      case EmojiMouth.frown:
        canvas.drawArc(Rect.fromCenter(center: Offset(rect.center.dx, mouthY + mw * .45), width: mw, height: mw), 3.55, 2.3, false, mp);
    }

    // Rosy cheeks — the signature of every BookNest face.
    if (def.eyes != null) {
      final blushY = rect.center.dy + rect.height * .1;
      final blushPaint = Paint()
        ..color = BookNestEmojiPalette.blushPink
            .withOpacity(dark ? .5 : .42);
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(rect.center.dx - rect.width * .27, blushY),
            width: rect.width * .17,
            height: rect.height * .08),
        blushPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(rect.center.dx + rect.width * .27, blushY),
            width: rect.width * .17,
            height: rect.height * .08),
        blushPaint,
      );
    }

    // accessories
    switch (def.accessory) {
      case EmojiAccessory.none:
        break;
      case EmojiAccessory.halo:
        canvas.drawOval(
          Rect.fromCenter(center: Offset(rect.center.dx, rect.top - size.height * .06), width: rect.width * .55, height: rect.height * .12),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = rect.width * .05
            ..color = BookNestEmojiPalette.cyan,
        );
      case EmojiAccessory.wizardHat:
        final brim = Rect.fromCenter(center: Offset(rect.center.dx, rect.top + rect.height * .06), width: rect.width * 1.05, height: rect.height * .1);
        canvas.drawOval(brim, Paint()..color = BookNestEmojiPalette.navyDeep);
        final hat = Path()
          ..moveTo(rect.center.dx - rect.width * .18, brim.top + rect.height * .02)
          ..lineTo(rect.center.dx + rect.width * .05, rect.top - rect.height * .38)
          ..lineTo(rect.center.dx + rect.width * .2, brim.top + rect.height * .02)
          ..close();
        canvas.drawPath(hat, Paint()..color = BookNestEmojiPalette.navyDeep);
        canvas.drawCircle(Offset(rect.center.dx + rect.width * .05, rect.top - rect.height * .38), rect.width * .04, Paint()..color = BookNestEmojiPalette.cyan);
      case EmojiAccessory.headphones:
        canvas.drawArc(
          Rect.fromCenter(center: rect.center, width: rect.width * .95, height: rect.height * .95),
          3.5,
          2.2,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = rect.width * .06
            ..color = BookNestEmojiPalette.navyDeep,
        );
        for (final dx in [-1.0, 1.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(rect.center.dx + dx * rect.width * .46, rect.center.dy), width: rect.width * .12, height: rect.height * .22),
              const Radius.circular(4),
            ),
            Paint()..color = BookNestEmojiPalette.cyan,
          );
        }
    }

    // animated details
    if (def.effect == EmojiEffect.drip) {
      final dropY = (t * 2) % 1;
      canvas.drawCircle(
        Offset(rect.center.dx + eyeDx, eyeY + eyeR * 2 + rect.height * .3 * dropY),
        rect.width * .035,
        Paint()..color = BookNestEmojiPalette.cyan.withOpacity(1 - dropY * .4),
      );
    }
    if (def.effect == EmojiEffect.floatZ) {
      final zz = ['z', 'Z', 'Z'];
      for (var i = 0; i < 3; i++) {
        final phase = (t + i * .33) % 1;
        _drawLetter(
          canvas,
          zz[i],
          Offset(rect.center.dx + rect.width * (.3 + .08 * i), rect.top - rect.height * (.04 + .16 * phase)),
          rect.width * (.09 + .03 * i),
          BookNestEmojiPalette.white.withOpacity(1 - phase * .7),
        );
      }
    }
  }

  // ── objects ──

  void _paintObject(Canvas canvas, Size size, EmojiObject object) {
    final c = Offset(size.width / 2, size.height / 2);
    final w = size.width;
    // Grounding shadow.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx, c.dy + w * .38),
        width: w * .5,
        height: w * .1,
      ),
      Paint()
        ..color = BookNestEmojiPalette.navyDeep.withOpacity(.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    switch (object) {
      case EmojiObject.openBook:
        final path = Path()
          ..moveTo(c.dx, c.dy - w * .18)
          ..quadraticBezierTo(c.dx - w * .3, c.dy - w * .3, c.dx - w * .42, c.dy - w * .2)
          ..lineTo(c.dx - w * .42, c.dy + w * .26)
          ..quadraticBezierTo(c.dx - w * .3, c.dy + w * .17, c.dx, c.dy + w * .3)
          ..quadraticBezierTo(c.dx + w * .3, c.dy + w * .17, c.dx + w * .42, c.dy + w * .26)
          ..lineTo(c.dx + w * .42, c.dy - w * .2)
          ..quadraticBezierTo(c.dx + w * .3, c.dy - w * .3, c.dx, c.dy - w * .18)
          ..close();
        canvas.drawPath(path, Paint()..color = BookNestEmojiPalette.white);
        canvas.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .03
          ..color = BookNestEmojiPalette.navyDeep);
        canvas.drawLine(Offset(c.dx, c.dy - w * .18), Offset(c.dx, c.dy + w * .3), Paint()
          ..color = BookNestEmojiPalette.navyDeep.withOpacity(.6)
          ..strokeWidth = w * .025);
        // Page block under the cover.
        canvas.drawLine(
          Offset(c.dx - w * .4, c.dy + w * .27),
          Offset(c.dx + w * .4, c.dy + w * .27),
          Paint()
            ..color = BookNestEmojiPalette.navyDeep.withOpacity(.45)
            ..strokeWidth = w * .035
            ..strokeCap = StrokeCap.round,
        );
        for (final sx in [-1.0, 1.0]) {
          for (var i = 0; i < 3; i++) {
            canvas.drawLine(
              Offset(c.dx + sx * w * (.1 + i * .09), c.dy - w * (.1 - i * .01)),
              Offset(c.dx + sx * w * (.1 + i * .09), c.dy + w * (.12 - i * .01)),
              Paint()
                ..color = BookNestEmojiPalette.cyan.withOpacity(.75)
                ..strokeWidth = w * .022
                ..strokeCap = StrokeCap.round,
            );
          }
        }
      case EmojiObject.bookStack:
        final colors = [BookNestEmojiPalette.cyan, BookNestEmojiPalette.lavender, BookNestEmojiPalette.mint];
        for (var i = 0; i < 3; i++) {
          final r = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(c.dx + (i == 1 ? w * .04 : 0), c.dy + w * (.22 - i * .17)), width: w * (.72 - i * .06), height: w * .13),
            const Radius.circular(3),
          );
          canvas.drawRRect(r, Paint()..color = colors[i]);
          canvas.drawRRect(r, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * .025
            ..color = BookNestEmojiPalette.navyDeep);
        }
      case EmojiObject.quill:
        final path = Path()
          ..moveTo(c.dx - w * .26, c.dy + w * .32)
          ..quadraticBezierTo(c.dx - w * .05, c.dy, c.dx + w * .22, c.dy - w * .34)
          ..quadraticBezierTo(c.dx + w * .18, c.dy - w * .02, c.dx - w * .12, c.dy + w * .26)
          ..close();
        canvas.drawPath(path, Paint()..color = BookNestEmojiPalette.white);
        canvas.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .028
          ..color = BookNestEmojiPalette.navyDeep);
        canvas.drawLine(Offset(c.dx - w * .26, c.dy + w * .32), Offset(c.dx - w * .18, c.dy + w * .18), Paint()
          ..color = BookNestEmojiPalette.navyDeep
          ..strokeWidth = w * .03
          ..strokeCap = StrokeCap.round);
        if (def.effect == EmojiEffect.floatUp) {
          for (var i = 0; i < 3; i++) {
            final phase = (t + i * .33) % 1;
            canvas.drawCircle(
              Offset(c.dx - w * .28 + i * w * .05, c.dy + w * .4 - phase * w * .1),
              w * .03,
              Paint()..color = BookNestEmojiPalette.cyan.withOpacity(1 - phase),
            );
          }
        }
      case EmojiObject.bookmark:
        final path = Path()
          ..moveTo(c.dx - w * .2, c.dy - w * .34)
          ..lineTo(c.dx + w * .2, c.dy - w * .34)
          ..lineTo(c.dx + w * .2, c.dy + w * .34)
          ..lineTo(c.dx, c.dy + w * .16)
          ..lineTo(c.dx - w * .2, c.dy + w * .34)
          ..close();
        canvas.drawPath(path, Paint()..color = BookNestEmojiPalette.cyan);
        canvas.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .028
          ..color = BookNestEmojiPalette.navyDeep);
      case EmojiObject.owl:
        canvas.drawOval(
          Rect.fromCenter(center: c, width: w * .62, height: w * .72),
          Paint()..color = BookNestEmojiPalette.navy,
        );
        canvas.drawCircle(Offset(c.dx - w * .14, c.dy - w * .1), w * .13, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(c.dx + w * .14, c.dy - w * .1), w * .13, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(c.dx - w * .14, c.dy - w * .1), w * .055, Paint()..color = BookNestEmojiPalette.navyDeep);
        canvas.drawCircle(Offset(c.dx + w * .14, c.dy - w * .1), w * .055, Paint()..color = BookNestEmojiPalette.navyDeep);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(c.dx, c.dy - w * .27), width: w * .14, height: w * .18),
          Paint()..color = BookNestEmojiPalette.cyan,
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(c.dx, c.dy + w * .2), width: w * .4, height: w * .3),
          Paint()..color = BookNestEmojiPalette.cyan.withOpacity(.35),
        );
      case EmojiObject.bookHeart:
        _drawHeart(canvas, Offset(c.dx, c.dy), w * .72, BookNestEmojiPalette.blushPink);
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(c.dx, c.dy + w * .02), width: w * .3, height: w * .2),
          const Radius.circular(2),
        );
        canvas.drawRRect(r, Paint()..color = BookNestEmojiPalette.white);
      case EmojiObject.lamp:
        canvas.drawLine(Offset(c.dx, c.dy - w * .02), Offset(c.dx, c.dy + w * .3), Paint()
          ..color = BookNestEmojiPalette.navyDeep
          ..strokeWidth = w * .045);
        canvas.drawLine(Offset(c.dx - w * .12, c.dy + w * .3), Offset(c.dx + w * .12, c.dy + w * .3), Paint()
          ..color = BookNestEmojiPalette.navyDeep
          ..strokeWidth = w * .045
          ..strokeCap = StrokeCap.round);
        final path = Path()
          ..moveTo(c.dx - w * .26, c.dy - w * .04)
          ..lineTo(c.dx + w * .26, c.dy - w * .04)
          ..lineTo(c.dx + w * .14, c.dy - w * .3)
          ..lineTo(c.dx - w * .14, c.dy - w * .3)
          ..close();
        canvas.drawPath(path, Paint()..color = BookNestEmojiPalette.cyan);
      case EmojiObject.coffee:
        final r = RRect.fromRectAndCorners(
          Rect.fromLTWH(c.dx - w * .24, c.dy - w * .16, w * .48, w * .44),
          bottomLeft: const Radius.circular(6),
          bottomRight: const Radius.circular(6),
        );
        canvas.drawRRect(r, Paint()..color = BookNestEmojiPalette.white);
        canvas.drawRRect(r, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .028
          ..color = BookNestEmojiPalette.navyDeep);
        final handle = Rect.fromCenter(center: Offset(c.dx + w * .28, c.dy + w * .05), width: w * .16, height: w * .18);
        canvas.drawArc(handle, -1.4, 2.8, false, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .04
          ..color = BookNestEmojiPalette.navyDeep);
        canvas.drawLine(Offset(c.dx - w * .18, c.dy - w * .04), Offset(c.dx + w * .18, c.dy - w * .04), Paint()
          ..color = BookNestEmojiPalette.lavender
          ..strokeWidth = w * .05);
      case EmojiObject.moon:
        final glow = def.effect == EmojiEffect.pulse ? .5 + .5 * (1 - (2 * t - 1).abs()) : .8;
        canvas.drawCircle(c, w * .34, Paint()..color = BookNestEmojiPalette.cyan.withOpacity(.3 * glow));
        final outer = Path()..addOval(Rect.fromCircle(center: c, radius: w * .3));
        final bite = Path()
          ..addOval(Rect.fromCircle(center: Offset(c.dx + w * .14, c.dy - w * .08), radius: w * .26));
        canvas.drawPath(
            Path.combine(PathOperation.difference, outer, bite),
            Paint()..color = BookNestEmojiPalette.cyan);
        _drawStar(canvas, Offset(c.dx + w * .3, c.dy - w * .28), w * .12, Colors.white);
      case EmojiObject.star:
        _drawStar(canvas, c, w * .62, BookNestEmojiPalette.cyan);
      case EmojiObject.heart:
        _drawHeart(canvas, c, w * .72, BookNestEmojiPalette.blushPink);
      case EmojiObject.sparkles:
        final tw = def.effect == EmojiEffect.twinkle
            ? [t, (t + .33) % 1, (t + .66) % 1].map((p) => .35 + .65 * (1 - (2 * p - 1).abs())).toList()
            : [1.0, .7, .85];
        _drawStar(canvas, Offset(c.dx - w * .18, c.dy - w * .14), w * .3, BookNestEmojiPalette.cyan.withOpacity(tw[0]));
        _drawStar(canvas, Offset(c.dx + w * .2, c.dy + w * .05), w * .22, Colors.white.withOpacity(tw[1]));
        _drawStar(canvas, Offset(c.dx - w * .02, c.dy + w * .28), w * .16, BookNestEmojiPalette.lavender.withOpacity(tw[2]));
      case EmojiObject.bookworm:
        canvas.drawOval(
          Rect.fromCenter(center: Offset(c.dx, c.dy + w * .05), width: w * .7, height: w * .5),
          Paint()..color = BookNestEmojiPalette.mint,
        );
        canvas.drawCircle(Offset(c.dx - w * .16, c.dy - w * .12), w * .16, Paint()..color = BookNestEmojiPalette.mint);
        _circleOutline(canvas, Offset(c.dx - w * .2, c.dy - w * .14), w * .07, BookNestEmojiPalette.navyDeep, w * .02);
        _circleOutline(canvas, Offset(c.dx - w * .11, c.dy - w * .14), w * .07, BookNestEmojiPalette.navyDeep, w * .02);
        canvas.drawCircle(Offset(c.dx - w * .2, c.dy - w * .14), w * .02, Paint()..color = BookNestEmojiPalette.navyDeep);
        canvas.drawCircle(Offset(c.dx - w * .11, c.dy - w * .14), w * .02, Paint()..color = BookNestEmojiPalette.navyDeep);
      case EmojiObject.shelf:
        canvas.drawRect(
          Rect.fromLTWH(c.dx - w * .34, c.dy - w * .32, w * .68, w * .64),
          Paint()..color = BookNestEmojiPalette.navy,
        );
        for (var i = 0; i < 3; i++) {
          canvas.drawRect(
            Rect.fromLTWH(c.dx - w * .26 + i * w * .2, c.dy - w * .24, w * .07, w * .28),
            Paint()..color = [BookNestEmojiPalette.cyan, BookNestEmojiPalette.lavender, BookNestEmojiPalette.mint][i],
          );
        }
        canvas.drawLine(Offset(c.dx - w * .34, c.dy + w * .06), Offset(c.dx + w * .34, c.dy + w * .06), Paint()
          ..color = BookNestEmojiPalette.white
          ..strokeWidth = w * .03);
      case EmojiObject.scroll:
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(c.dx - w * .26, c.dy - w * .3, w * .52, w * .6), const Radius.circular(4)),
          Paint()..color = BookNestEmojiPalette.white,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(c.dx - w * .26, c.dy - w * .3, w * .52, w * .6), const Radius.circular(4)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * .028
            ..color = BookNestEmojiPalette.navyDeep,
        );
        for (var i = 0; i < 3; i++) {
          canvas.drawLine(
            Offset(c.dx - w * .16, c.dy - w * .14 + i * w * .14),
            Offset(c.dx + w * .16, c.dy - w * .14 + i * w * .14),
            Paint()
              ..color = BookNestEmojiPalette.cyan
              ..strokeWidth = w * .03
              ..strokeCap = StrokeCap.round,
          );
        }
      case EmojiObject.medal:
        canvas.drawCircle(Offset(c.dx, c.dy - w * .05), w * .24, Paint()..color = BookNestEmojiPalette.cyan);
        canvas.drawCircle(Offset(c.dx, c.dy - w * .05), w * .24, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .03
          ..color = BookNestEmojiPalette.navyDeep);
        _drawStar(canvas, Offset(c.dx, c.dy - w * .05), w * .22, BookNestEmojiPalette.white);
        for (final dx in [-1.0, 1.0]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(c.dx + dx * w * .14, c.dy + w * .3), width: w * .12, height: w * .3),
              const Radius.circular(2),
            ),
            Paint()..color = dx < 0 ? BookNestEmojiPalette.navy : BookNestEmojiPalette.lavender,
          );
        }
      case EmojiObject.comet:
        canvas.drawLine(
          Offset(c.dx + w * .3, c.dy - w * .3),
          Offset(c.dx - w * .18, c.dy + w * .18),
          Paint()
            ..color = BookNestEmojiPalette.cyan.withOpacity(.6)
            ..strokeWidth = w * .06
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(Offset(c.dx - w * .24, c.dy + w * .24), w * .15, Paint()..color = Colors.white);
    }

    if (def.effect == EmojiEffect.orbit) {
      for (var i = 0; i < 4; i++) {
        final angle = t * 6.2832 + i * 1.5708;
        canvas.drawCircle(
          Offset(c.dx + w * .42 * math.cos(angle), c.dy + w * .42 * math.sin(angle)),
          w * .035,
          Paint()..color = [BookNestEmojiPalette.cyan, Colors.white, BookNestEmojiPalette.lavender, BookNestEmojiPalette.mint][i],
        );
      }
    }
  }

  // ── shared shapes ──

  void _drawStar(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -1.5708 + i * 0.6283;
      final rad = i.isEven ? r : r * .45;
      final p = Offset(c.dx + rad * math.cos(angle), c.dy + rad * math.sin(angle));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawHeart(Canvas canvas, Offset c, double size, Color color,
      {Color? outline}) {
    final path = Path()
      ..moveTo(c.dx, c.dy + size * .38)
      ..cubicTo(c.dx - size * .62, c.dy - size * .06, c.dx - size * .3,
          c.dy - size * .48, c.dx, c.dy - size * .18)
      ..cubicTo(c.dx + size * .3, c.dy - size * .48, c.dx + size * .62,
          c.dy - size * .06, c.dx, c.dy + size * .38)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    if (outline != null) {
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * .07
            ..color = outline);
    }
  }

  void _circleOutline(Canvas canvas, Offset c, double r, Color color, double w) {
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = color);
  }

  void _drawLetter(Canvas canvas, String letter, Offset c, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: letter,
          style: TextStyle(
              color: color, fontSize: size, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c);
  }

  @override
  bool shouldRepaint(covariant BookNestEmojiPainter old) =>
      old.def.code != def.code || old.t != t;
}
