import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_state.dart';

import '../../config/theme.dart';

/// Shared BookNest UI kit — one visual language across all screens:
/// navy/cyan gradients, glass surfaces, soft cyan glows, honest empty states.

/// Rounded avatar with Cloudinary-aware caching and an initials fallback.
class BookNestAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;

  const BookNestAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final hasImage = url != null && url.startsWith('http');
    final initial =
        name.characters.isEmpty ? '?' : name.characters.first.toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: BookNestColors.navy,
      backgroundImage: hasImage ? CachedNetworkImageProvider(url) : null,
      child: hasImage
          ? null
          : Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * .8,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

/// Book cover: Cloudinary art when available, branded gradient when not.
class BookCover extends StatelessWidget {
  final String? coverUrl;
  final String title;
  final double width;
  final double height;
  final double radius;

  const BookCover({
    super.key,
    this.coverUrl,
    required this.title,
    this.width = 64,
    this.height = 86,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final url = coverUrl;
    final hasImage = url != null && url.startsWith('http');
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [BookNestColors.navy, BookNestColors.navyDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: BookNestColors.navyDeep.withOpacity(.25),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => const ColoredBox(
                    color: BookNestColors.navyDeep),
                errorWidget: (_, __, ___) => const _FallbackCover(),
              ),
            )
          : const _FallbackCover(),
    );
  }
}

class _FallbackCover extends StatelessWidget {
  const _FallbackCover();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories_rounded, color: BookNestColors.cyan, size: 22),
          SizedBox(height: 4),
          Text(
            'BookNest',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title with an optional trailing action ("See all →").
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(actionLabel!,
                style: const TextStyle(
                    color: BookNestColors.cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
      ],
    );
  }
}

/// Honest empty state — used everywhere instead of blank space.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BookNestColors.cyan.withOpacity(.1),
                border: Border.all(color: BookNestColors.cyan.withOpacity(.3)),
              ),
              child: Icon(icon, color: BookNestColors.cyan, size: 34),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.hintColor, height: 1.4)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Compact stat display for dashboards and profiles.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: BookNestColors.cyan.withOpacity(.08),
        border: Border.all(color: BookNestColors.cyan.withOpacity(.22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: BookNestColors.cyan, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: Theme.of(context).hintColor, fontSize: 11.5)),
        ],
      ),
    );
  }
}

/// Glassmorphism wrapper for bottom sheets (blur + cyan hairline).
class GlassSheet extends StatelessWidget {
  final Widget child;
  final double heightFactor;

  const GlassSheet({
    super.key,
    required this.child,
    this.heightFactor = .75,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: MediaQuery.sizeOf(context).height * heightFactor,
            decoration: BoxDecoration(
              color: (dark ? BookNestColors.darkChatBackground : Colors.white)
                  .withOpacity(.96),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border.all(color: BookNestColors.cyan.withOpacity(.22)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cyan gradient CTA used across the new screens.
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onPressed,
      child: SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [BookNestColors.cyanSoft, BookNestColors.cyan],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: BookNestColors.cyan.withOpacity(.28),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: busy ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: BookNestColors.navyDeep))
              : Icon(icon, color: BookNestColors.navyDeep, size: 20),
          label: Text(
            label,
            style: const TextStyle(
              color: BookNestColors.navyDeep,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Small rounded chip for genres, tags and filters.
class TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const TagChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected ? BookNestColors.cyan : Colors.transparent,
          border: Border.all(
            color: selected ? BookNestColors.cyan : BookNestColors.cyan.withOpacity(.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected
                ? BookNestColors.navyDeep
                : (Theme.of(context).brightness == Brightness.dark
                    ? BookNestColors.darkTextPrimary
                    : BookNestColors.navy),
          ),
        ),
      ),
    );
  }
}

/// The canonical 22 BookNest genres, in the exact product order.

/// ─────────────────────────────────────────────────────────────────────────
/// BookNest motion kit — reusable, theme-aware animation primitives.
/// Every widget respects the "Reduce motion" accessibility setting.
/// ─────────────────────────────────────────────────────────────────────────

/// Wraps a child in a springy press animation (tap-down scale).
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = .96,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduced = AppSettings.reduceMotion.value;
    return GestureDetector(
      onTapDown: reduced || widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: reduced || widget.onTap == null ? null : (_) => setState(() => _down = false),
      onTapCancel: reduced || widget.onTap == null ? null : () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Entrance animation: fades + slides its child in, staggered by [index].
/// Wrap list tiles with `Entrance(index: i, child: …)`.
class Entrance extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration duration;

  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, .08),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    if (AppSettings.reduceMotion.value) {
      _controller.value = 1;
    } else {
      final stagger = Duration(milliseconds: 55 * widget.index.clamp(0, 12));
      Future.delayed(stagger, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

/// Shimmering placeholder for async-loading content.
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppSettings.reduceMotion.value) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: widget.borderRadius,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final base = theme.colorScheme.surface;
        final glow = theme.dividerColor;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * _controller.value, 0),
              end: Alignment(0 + 2 * _controller.value, 0),
              colors: [base, glow.withOpacity(.45), base],
            ),
          ),
        );
      },
    );
  }
}

/// Number that animates when its value changes (likes, stats, counters).
class AnimatedCount extends StatefulWidget {
  final int value;
  final TextStyle? style;

  const AnimatedCount({super.key, required this.value, this.style});

  @override
  State<AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<AnimatedCount> {
  late int _from = widget.value;

  @override
  void didUpdateWidget(AnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _from = oldWidget.value;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: _from, end: widget.value),
      duration: AppSettings.reduceMotion.value
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('$v', style: widget.style),
    );
  }
}


/// Universal glassmorphism panel: frosted blur + translucent base + cyan
/// hairline. The one wrapper to reach for when a surface should read as
/// glass. Respects dark/light automatically.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Border? border;

  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 18,
    this.opacity = .62,
    this.radius = 20,
    this.padding,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base =
        dark ? BookNestColors.darkChatBackground : Colors.white;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: base.withOpacity(opacity),
            borderRadius: BorderRadius.circular(radius),
            border: border ??
                Border.all(color: BookNestColors.cyan.withOpacity(.2)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Frosted app bar: content scrolling beneath it is blurred in real time.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  const GlassAppBar({super.key, required this.title, this.actions, this.leading});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base =
        dark ? BookNestColors.darkChatBackground : Colors.white;
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: leading,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      actions: actions,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: base.withOpacity(.66),
              border: Border(
                bottom: BorderSide(
                    color: BookNestColors.cyan.withOpacity(.15)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const List<String> kBookNestGenres = [
  'Romance',
  'Science Fiction',
  'Thriller & Suspense',
  'Fantasy',
  'Mystery & Crime',
  'Horror',
  'Historical Fiction',
  'Literary Fiction',
  'Westerns',
  'Biographies & Memoirs',
  'True Crime',
  'Self-Help & Wellness',
  'History & Politics',
  'Young Adult (YA)',
  'STEM',
  'Humanities & Social Sciences',
  'Languages & Linguistics',
  'Finance & Economics',
  'Professional Certification',
  'Lexicons',
  'Research & Citation Tools',
  'Compendiums',
];
