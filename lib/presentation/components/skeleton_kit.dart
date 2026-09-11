import 'package:flutter/material.dart';

import '../../config/theme.dart';

import 'booknest_ui.dart';

/// BookNest skeleton kit — loading states that mirror the exact geometry of
/// the content they become, swept by a soft navy→cyan shimmer. Skeletons
/// (not spinners) are the app's language for lists: the page never jumps,
/// the shimmer reads as instant progress at 60fps.
class SkeletonKit extends StatefulWidget {
  const SkeletonKit({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1400),
  });

  /// The skeleton tree to sweep the shimmer across.
  final Widget child;
  final Duration duration;

  static SkeletonKitState? of(BuildContext context) =>
      context.findAncestorStateOfType<SkeletonKitState>();

  @override
  State<SkeletonKit> createState() => SkeletonKitState();
}

class SkeletonKitState extends State<SkeletonKit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A single rounded bone. Needs a [SkeletonKit] ancestor for the sweep.
class Bone extends StatelessWidget {
  const Bone({
    super.key,
    this.width,
    required this.height,
    this.radius = 10,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF182340) : const Color(0xFFE4EBF5);
    final state = SkeletonKit.of(context);
    if (state == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }
    final t = state._controller.value;
    return CustomPaint(
      size: Size(width ?? double.infinity, height),
      painter: _BonePainter(
        t: t,
        base: base,
        sweep: dark
            ? const [Color(0xFF1E2C48), Color(0xFF24395F), Color(0xFF1E2C48)]
            : const [Color(0xFFEDF2FA), Color(0xFFDCE9F7), Color(0xFFEDF2FA)],
        radius: radius,
      ),
    );
  }
}

class _BonePainter extends CustomPainter {
  _BonePainter({
    required this.t,
    required this.base,
    required this.sweep,
    required this.radius,
  });

  final double t;
  final Color base;
  final List<Color> sweep;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
    canvas.drawRRect(r, Paint()..color = base);
    // diagonal light band sweeping left → right, one full cycle per t
    final dx = (t * 2 - 0.5) * size.width;
    final rect = Rect.fromLTWH(dx - size.width * 0.35, -size.height,
        size.width * 0.7, size.height * 3);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: sweep,
      ).createShader(rect);
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BonePainter old) => old.t != t;
}

/// Vertical list of post-card skeletons (the feed's exact silhouette).
class PostListSkeleton extends StatelessWidget {
  const PostListSkeleton({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SkeletonKit(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: count,
        itemBuilder: (_, __) => const _PostCardSkeleton(),
      ),
    );
  }
}

class _PostCardSkeleton extends StatelessWidget {
  const _PostCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassPanel(
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Bone(width: 38, height: 38, radius: 19),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Bone(height: 11, width: 140),
                      SizedBox(height: 6),
                      Bone(height: 9, width: 90),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              const Bone(height: 12),
              const SizedBox(height: 6),
              const Bone(height: 12),
              const SizedBox(height: 6),
              const Bone(height: 12, width: 210),
              const SizedBox(height: 14),
              Row(children: const [
                Bone(width: 54, height: 22, radius: 11),
                SizedBox(width: 10),
                Bone(width: 54, height: 22, radius: 11),
                SizedBox(width: 10),
                Bone(width: 54, height: 22, radius: 11),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal shelf of book-cover skeletons (library / reading lists).
class BookShelfSkeleton extends StatelessWidget {
  const BookShelfSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SkeletonKit(
      child: SizedBox(
        height: 150,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Bone(width: 104, height: 104, radius: 14),
              SizedBox(height: 8),
              Bone(height: 10, width: 90),
              SizedBox(height: 5),
              Bone(height: 9, width: 60),
            ],
          ),
        ),
      ),
    );
  }
}

/// Conversation-row skeletons (DM list / member directories).
class RowsSkeleton extends StatelessWidget {
  const RowsSkeleton({super.key, this.count = 7});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SkeletonKit(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: count,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            const Bone(width: 46, height: 46, radius: 23),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Bone(height: 11, width: 150),
                  SizedBox(height: 7),
                  Bone(height: 10),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Group-card skeletons for the Discover shelves.
class GroupCardsSkeleton extends StatelessWidget {
  const GroupCardsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonKit(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassPanel(
                  radius: 18,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      const Bone(width: 48, height: 48, radius: 14),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Bone(height: 12, width: 170),
                            SizedBox(height: 7),
                            Bone(height: 10),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
