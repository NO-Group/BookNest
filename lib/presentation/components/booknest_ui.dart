import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
    return SizedBox(
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
