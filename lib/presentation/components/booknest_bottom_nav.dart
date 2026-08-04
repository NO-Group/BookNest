import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BookNestBottomNav extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BookNestBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<BookNestBottomNav> createState() => _BookNestBottomNavState();
}

class _BookNestBottomNavState extends State<BookNestBottomNav>
    with SingleTickerProviderStateMixin {
  late AnimationController _fabController;
  late Animation<double> _fabScale;

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fabScale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  void _onCenterTap() {
    HapticFeedback.mediumImpact();
    _fabController.forward().then((_) => _fabController.reverse());
    widget.onTap(2);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // Glassmorphism Main Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildTab(0, Icons.view_agenda_outlined),
                      _buildTab(1, Icons.explore_outlined),
                      const SizedBox(width: 56), // Center gap for the FAB
                      _buildTab(3, Icons.chat_bubble_outline),
                      _buildTab(4, Icons.person_outline),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Glassmorphism Center FAB
          Positioned(
            top: 0,
            child: GestureDetector(
              onTap: _onCenterTap,
              child: AnimatedBuilder(
                animation: _fabScale,
                builder: (context, child) => Transform.scale(
                  scale: widget.currentIndex == 2 ? _fabScale.value : 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6A00).withOpacity(0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFFFFD000).withOpacity(0.8),
                                const Color(0xFFFF6A00).withOpacity(0.8),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.4),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.menu_book,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index, IconData icon) {
    final isSelected = widget.currentIndex == index;
    return GestureDetector(
      onTap: () => widget.onTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: isSelected
            ? BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF6A00).withOpacity(0.2),
                border: Border.all(
                  color: const Color(0xFFFF6A00).withOpacity(0.3),
                  width: 1,
                ),
              )
            : const BoxDecoration(
                shape: BoxShape.circle,
              ),
        child: Icon(
          icon,
          size: 24,
          color: isSelected
              ? const Color(0xFFFFD000)
              : Colors.white.withOpacity(0.6),
        ),
      ),
    );
  }
}