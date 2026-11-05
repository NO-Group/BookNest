import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_state.dart';
import '../../config/theme.dart';

/// Floating glass navigation: four labelled tabs around the raised Books
/// button. The selected tab gets a filled icon on a soft cyan pill.
/// Keeps the original 92 px footprint so screen paddings stay valid.
class BookNestBottomNav extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  const BookNestBottomNav({super.key, required this.currentIndex, required this.onTap});
  @override
  State<BookNestBottomNav> createState() => _BookNestBottomNavState();
}

class _NavItem {
  final int index;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem(this.index, this.icon, this.selectedIcon, this.label);
}

const _left = [
  _NavItem(0, Icons.view_agenda_outlined, Icons.view_agenda_rounded, 'Feed'),
  _NavItem(1, Icons.explore_outlined, Icons.explore_rounded, 'Discover'),
];
const _right = [
  _NavItem(3, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Messages'),
  _NavItem(4, Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
];

class _BookNestBottomNavState extends State<BookNestBottomNav> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 240));

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Duration get _speed =>
      AppSettings.reduceMotion.value ? Duration.zero : const Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF0B1428) : Colors.white;
    final border = dark ? BookNestColors.cyan.withValues(alpha: .14) : BookNestColors.lightBorder;
    final inactive = dark ? BookNestColors.darkTextSecondary : BookNestColors.lightTextSecondary;
    final active = dark ? BookNestColors.cyan : BookNestColors.navy;
    return SizedBox(
      height: 92,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 66,
            margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: (dark ? Colors.black : BookNestColors.navyDeep).withValues(alpha: dark ? .45 : .14),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: surface.withValues(alpha: dark ? .72 : .86),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      for (final item in _left) Expanded(child: _tab(item, active, inactive)),
                      const SizedBox(width: 72),
                      for (final item in _right) Expanded(child: _tab(item, active, inactive)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(top: 0, child: _booksButton()),
        ],
      ),
    );
  }

  Widget _booksButton() {
    final selected = widget.currentIndex == 2;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Books',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          if (!AppSettings.reduceMotion.value) {
            _pulse.forward(from: 0).then((_) => _pulse.reverse());
          }
          widget.onTap(2);
        },
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Transform.scale(
            scale: 1 + _pulse.value * .08,
            child: AnimatedContainer(
              duration: _speed,
              curve: Curves.easeOutCubic,
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: selected
                      ? const [BookNestColors.cyanSoft, BookNestColors.cyan]
                      : const [Color(0xFF1B3D78), BookNestColors.navyDeep],
                ),
                border: Border.all(
                    color: BookNestColors.cyan.withValues(alpha: selected ? .9 : .55), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: BookNestColors.cyan.withValues(alpha: selected ? .45 : .22),
                    blurRadius: selected ? 22 : 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(Icons.menu_book_rounded,
                  size: 28, color: selected ? BookNestColors.navyDeep : Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(_NavItem item, Color active, Color inactive) {
    final selected = widget.currentIndex == item.index;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap(item.index);
        },
        radius: 34,
        highlightShape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: _speed,
              curve: Curves.easeOutCubic,
              width: selected ? 52 : 40,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                color: selected ? BookNestColors.cyan.withValues(alpha: .16) : Colors.transparent,
              ),
              child: AnimatedSwitcher(
                duration: _speed,
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  key: ValueKey(selected),
                  size: 23,
                  color: selected ? active : inactive,
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: _speed,
              style: TextStyle(
                fontFamily: BookNestTheme.fontFamily,
                fontSize: 11,
                height: 1.1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? active : inactive,
              ),
              child: Text(item.label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
            ),
          ],
        ),
      ),
    );
  }
}
