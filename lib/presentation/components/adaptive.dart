import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// BookNest's responsive toolkit — one place that decides when the app is
/// a phone, a tablet or a PC, so every screen agrees.
///
/// * compact  (< 600 px)   phones: bottom navigation, sheets, ⋮ menus.
/// * medium   (600–1023)   tablets / small windows: navigation rail.
/// * expanded (≥ 1024)     PC / large tablets: sidebar + multi-pane pages.
class Breakpoints {
  Breakpoints._();

  static const double medium = 600;
  static const double expanded = 1024;
  static const double wide = 1400;
}

extension BookNestScreen on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isCompact => screenWidth < Breakpoints.medium;
  bool get isMediumUp => screenWidth >= Breakpoints.medium;
  bool get isExpanded => screenWidth >= Breakpoints.expanded;
  bool get isWide => screenWidth >= Breakpoints.wide;
}

/// Centres [child] at a comfortable reading width on big screens and does
/// nothing on phones. Use around page bodies that were designed for a phone
/// column (forms, settings, articles) so they don't stretch to 1900 px.
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final Alignment alignment;

  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 760,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Body of a modal bottom sheet: safe-area aware, follows the keyboard and
/// scrolls when its content is taller than the screen (small phones,
/// landscape) instead of overflowing.
class SheetBody extends StatelessWidget {
  final Widget child;

  const SheetBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SingleChildScrollView(child: child),
      ),
    );
  }
}

/// One entry for [adaptiveActions].
class HeaderAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Stays a visible icon on phones too (keep it to one or two).
  final bool pinned;

  const HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.pinned = false,
  });
}

/// App-bar actions that fit the screen: every action is an icon on tablets
/// and PCs; on phones they fold into a single ⋮ menu (plus any [pinned]
/// ones) so the header never gets crowded.
List<Widget> adaptiveActions(
  BuildContext context,
  List<HeaderAction> actions, {
  double inlineFrom = Breakpoints.medium,
}) {
  final inline = context.screenWidth >= inlineFrom;
  Widget icon(HeaderAction a) => IconButton(
        tooltip: a.label,
        icon: Icon(a.icon, size: 21),
        onPressed: a.onTap,
      );
  if (inline) return [for (final a in actions) icon(a)];
  final pinned = actions.where((a) => a.pinned).toList();
  final folded = actions.where((a) => !a.pinned).toList();
  return [
    for (final a in pinned) icon(a),
    if (folded.isNotEmpty)
      PopupMenuButton<int>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert_rounded),
        position: PopupMenuPosition.under,
        onSelected: (i) => folded[i].onTap?.call(),
        itemBuilder: (context) => [
          for (var i = 0; i < folded.length; i++)
            PopupMenuItem<int>(
              value: i,
              enabled: folded[i].onTap != null,
              child: Row(children: [
                Icon(folded[i].icon, size: 20, color: BookNestColors.cyan),
                const SizedBox(width: 14),
                Flexible(child: Text(folded[i].label)),
              ]),
            ),
        ],
      ),
  ];
}

/// A pop-up that fits the device: a bottom sheet on phones, a centred
/// dialog on tablets / PC (a sheet glued to the bottom of a 27" monitor
/// is the "stretched phone" look).
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = 560,
  bool isDismissible = true,
}) {
  if (context.isCompact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      isDismissible: isDismissible,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: size.height * .86,
        ),
        child: builder(dialogContext),
      );
    },
  );
}
