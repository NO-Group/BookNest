import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../components/booknest_bottom_nav.dart';

class MainShell extends StatefulWidget {
  final Widget child;
  final String location;

  const MainShell({super.key, required this.child, required this.location});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _getIndex(String loc) {
    if (loc == '/clubs') return 0;
    if (loc == '/discover') return 1;
    if (loc.startsWith('/books') || loc.startsWith('/reader')) return 2;
    if (loc.startsWith('/chat') || loc.startsWith('/dms')) return 3;
    if (loc == '/profile') return 4;
    return 0;
  }

  void _onTap(int index) {
    switch (index) {
      case 0: context.go('/clubs'); break;
      case 1: context.go('/discover'); break;
      case 2: context.go('/books'); break;
      case 3: context.go('/dms'); break;
      case 4: context.go('/profile'); break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: widget.child,
      bottomNavigationBar: BookNestBottomNav(
        currentIndex: _getIndex(widget.location),
        onTap: _onTap,
      ),
      extendBody: true,
    );
  }
}