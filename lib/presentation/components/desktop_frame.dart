import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import 'adaptive.dart';

/// The big-screen frame around every signed-in page.
///
/// * PC (≥ 1024 px): a permanent sidebar — logo, Write button, the five
///   main sections, your shelf/tools, and your account at the bottom. It
///   stays put while you open books, clubs, chats or settings, like a real
///   desktop app.
/// * Tablet / small window (600–1023): a slim icon rail.
/// * Phone: nothing — phones keep the floating bottom bar.
class DesktopFrame extends StatelessWidget {
  final String location;
  final Widget child;

  const DesktopFrame({super.key, required this.location, required this.child});

  @override
  Widget build(BuildContext context) {
    if (context.isCompact) return child;
    final expanded = context.isExpanded;
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Row(
        children: [
          expanded
              ? _Sidebar(location: location)
              : _Rail(location: location),
          VerticalDivider(width: 1, thickness: 1, color: theme.dividerColor),
          Expanded(child: ClipRect(child: child)),
        ],
      ),
    );
  }
}

class _Dest {
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Other locations that belong to this section (a book page lights up
  /// Books, a club lights up Discover…).
  final List<String> also;

  const _Dest(this.path, this.label, this.icon, this.selectedIcon,
      [this.also = const []]);

  bool matches(String location) {
    bool hit(String p) => location == p || location.startsWith('$p/');
    return hit(path) || also.any(hit);
  }
}

const _main = <_Dest>[
  _Dest('/feed', 'Feed', Icons.view_agenda_outlined, Icons.view_agenda_rounded,
      ['/create']),
  _Dest('/discover', 'Discover', Icons.explore_outlined, Icons.explore_rounded,
      ['/club', '/community', '/organization', '/school', '/genre', '/events']),
  _Dest('/books', 'Books', Icons.menu_book_outlined, Icons.menu_book_rounded,
      ['/book', '/dashboard', '/manage', '/analytics', '/publish-details']),
  _Dest('/dms', 'Messages', Icons.chat_bubble_outline_rounded,
      Icons.chat_bubble_rounded,
      ['/chat', '/club-chat', '/random-chat', '/shared']),
  _Dest('/profile', 'Profile', Icons.person_outline_rounded,
      Icons.person_rounded, ['/settings/edit-profile', '/streaks', '/wrapped']),
];

const _more = <_Dest>[
  _Dest('/library', 'My library', Icons.local_library_outlined,
      Icons.local_library_rounded),
  _Dest('/notifications', 'Notifications', Icons.notifications_none_rounded,
      Icons.notifications_rounded),
  _Dest('/search', 'Search', Icons.search_rounded, Icons.search_rounded),
  _Dest('/wallet', 'Wallet & store', Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet_rounded, ['/store']),
  _Dest('/settings', 'Settings', Icons.settings_outlined,
      Icons.settings_rounded),
];

void _goTo(BuildContext context, _Dest d) {
  // Main sections are tabs: `go` restores each tab where you left it.
  if (_main.contains(d)) {
    context.go(d.path);
  } else {
    context.push(d.path);
  }
}

_Dest? _active(String location) {
  for (final d in [..._more, ..._main]) {
    // Settings sub-pages that belong to Profile are listed in _main.also,
    // so check the specific ones first.
    if (d.path == '/settings' && location.startsWith('/settings/edit-profile')) {
      continue;
    }
    if (d.matches(location)) return d;
  }
  return null;
}

class _Sidebar extends StatelessWidget {
  final String location;

  const _Sidebar({required this.location});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final active = _active(location);
    final width = context.isWide ? 264.0 : 236.0;
    return Container(
      width: width,
      color: dark ? const Color(0xFF070F20) : BookNestColors.lightSurface,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 18),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.go('/feed'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 12, 4),
                child: Row(children: [
                  const _LogoTile(size: 38),
                  const SizedBox(width: 12),
                  Text('BookNest',
                      style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.3,
                          color: theme.colorScheme.onSurface)),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _WriteButton(onTap: () => context.push('/editor')),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final d in _main)
                    _SideItem(dest: d, selected: identical(d, active)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 18, 14, 6),
                    child: Text('YOU',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800,
                            color: theme.hintColor)),
                  ),
                  for (final d in _more)
                    _SideItem(dest: d, selected: identical(d, active)),
                ],
              ),
            ),
            const _AccountChip(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  final _Dest dest;
  final bool selected;

  const _SideItem({required this.dest, required this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final on = dark ? BookNestColors.cyan : BookNestColors.navy;
    final off = dark
        ? BookNestColors.darkTextSecondary
        : BookNestColors.lightTextSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? BookNestColors.cyan.withOpacity(dark ? .13 : .16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _goTo(context, dest),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              Icon(selected ? dest.selectedIcon : dest.icon,
                  size: 22, color: selected ? on : off),
              const SizedBox(width: 14),
              Expanded(
                child: Text(dest.label,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? theme.colorScheme.onSurface : off)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _WriteButton extends StatelessWidget {
  final VoidCallback onTap;

  const _WriteButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
            colors: [BookNestColors.cyanSoft, BookNestColors.cyan]),
        boxShadow: [
          BoxShadow(
              color: BookNestColors.cyan.withOpacity(.28),
              blurRadius: 18,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.edit_note_rounded,
                    color: BookNestColors.navyDeep, size: 22),
                SizedBox(width: 8),
                Text('Write a book',
                    style: TextStyle(
                        color: BookNestColors.navyDeep,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The signed-in reader, bottom of the sidebar.
class _AccountChip extends StatelessWidget {
  const _AccountChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = SupabaseService().auth.currentUser;
    final meta = user?.userMetadata ?? const <String, dynamic>{};
    final name = (meta['display_name'] ?? meta['username'] ?? 'Reader')
        .toString();
    final handle = meta['username']?.toString();
    final avatar = meta['avatar_url']?.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go('/profile'),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: BookNestColors.navy,
                backgroundImage: avatar != null && avatar.startsWith('http')
                    ? NetworkImage(avatar)
                    : null,
                child: avatar != null && avatar.startsWith('http')
                    ? null
                    : Text(name.isEmpty ? 'R' : name.characters.first.toUpperCase(),
                        style: const TextStyle(
                            color: BookNestColors.cyan,
                            fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13.5)),
                    if (handle != null && handle.isNotEmpty)
                      Text('@$handle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 12, color: theme.hintColor)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.hintColor),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Tablet rail: icons only, tooltips on hover.
class _Rail extends StatelessWidget {
  final String location;

  const _Rail({required this.location});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final active = _active(location);
    return Container(
      width: 76,
      color: dark ? const Color(0xFF070F20) : BookNestColors.lightSurface,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 14),
            const _LogoTile(size: 40),
            const SizedBox(height: 14),
            Tooltip(
              message: 'Write a book',
              child: IconButton.filled(
                onPressed: () => context.push('/editor'),
                style: IconButton.styleFrom(
                    backgroundColor: BookNestColors.cyan,
                    foregroundColor: BookNestColors.navyDeep),
                icon: const Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: [
                  for (final d in [..._main, ..._more])
                    _RailItem(dest: d, selected: identical(d, active)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final _Dest dest;
  final bool selected;

  const _RailItem({required this.dest, required this.selected});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = dark ? BookNestColors.cyan : BookNestColors.navy;
    final off = dark
        ? BookNestColors.darkTextSecondary
        : BookNestColors.lightTextSecondary;
    return Tooltip(
      message: dest.label,
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: () => _goTo(context, dest),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 52,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: selected
                    ? BookNestColors.cyan.withOpacity(.16)
                    : Colors.transparent,
              ),
              child: Icon(selected ? dest.selectedIcon : dest.icon,
                  size: 22, color: selected ? on : off),
            ),
            const SizedBox(height: 3),
            Text(dest.label.split(' ').first,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? on : off)),
          ]),
        ),
      ),
    );
  }
}

/// The logo on its white tile (it is navy ink — never on black).
class _LogoTile extends StatelessWidget {
  final double size;

  const _LogoTile({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * .28),
        border: Border.all(color: BookNestColors.cyan.withOpacity(.35)),
      ),
      child: Image.asset(
        // Despite the name, this is the navy logo (for light backgrounds).
        'assets/logo/booknest_logo_new_transparent_dark_theme.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
