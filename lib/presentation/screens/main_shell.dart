import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../components/booknest_bottom_nav.dart';

/// Persistent shell layout wrapping the primary [StatefulNavigationShell].
///
/// Renders the floating 5-tab [BookNestBottomNav]:
/// Feed | Discover | Books (center FAB) | Messages | Profile.
/// Each branch's state is preserved via the indexed stack shell.
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      // Preserve the current stack state when re-selecting the active branch.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BookNestBottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: _onDestinationSelected,
      ),
      extendBody: true,
    );
  }
}
