import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_state.dart';
import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';

/// Settings — appearance (theme switcher), account shortcuts, support pages.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? BookNestColors.darkChatBackground
          : BookNestColors.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text('APPEARANCE',
              style: TextStyle(
                  color: theme.hintColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
          const SizedBox(height: 10),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: AppSettings.themeMode,
            builder: (context, mode, _) => Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.brightness_6_rounded,
                          color: BookNestColors.cyan, size: 20),
                      SizedBox(width: 10),
                      Text('Theme',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('Auto'),
                          icon: Icon(Icons.brightness_auto_rounded, size: 17)),
                      ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_outlined, size: 17)),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_outlined, size: 17)),
                    ],
                    selected: {mode},
                    selectedIcon: const Icon(Icons.check_rounded, size: 17),
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: BookNestColors.cyan,
                      selectedForegroundColor: BookNestColors.navyDeep,
                    ),
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        AppSettings.themeMode.value = selection.first,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('ACCOUNT',
              style: TextStyle(
                  color: theme.hintColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
          const SizedBox(height: 10),
          _SettingsGroup(children: [
            _SettingsRow(
              icon: Icons.person_outline_rounded,
              label: 'Edit profile',
              onTap: () => context.push('/settings/edit-profile'),
            ),
            _SettingsRow(
              icon: Icons.notifications_none_rounded,
              label: 'Notifications',
              onTap: () => context.push('/notifications'),
            ),
            _SettingsRow(
              icon: Icons.shield_outlined,
              label: 'Privacy & safety',
              onTap: () => context.push('/privacy'),
            ),
          ]),
          const SizedBox(height: 24),
          Text('ABOUT',
              style: TextStyle(
                  color: theme.hintColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
          const SizedBox(height: 10),
          _SettingsGroup(children: [
            _SettingsRow(
              icon: Icons.auto_stories_rounded,
              label: 'About BookNest',
              onTap: () => context.push('/about'),
            ),
            _SettingsRow(
              icon: Icons.favorite_rounded,
              label: 'Made for bookworms & STEM minds',
              onTap: () => context.push('/about'),
            ),
          ]),
          const SizedBox(height: 28),
          _SignOutButton(),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1)
            Divider(height: 1, indent: 56, color: Theme.of(context).dividerColor),
        ],
      ]),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 21, color: BookNestColors.cyan),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14.5)),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: Theme.of(context).hintColor),
          ],
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  Future<void> _confirmAndSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await SupabaseService().auth.signOut();
    if (!context.mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _confirmAndSignOut(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          side: BorderSide(color: Theme.of(context).colorScheme.error.withOpacity(.5)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.logout_rounded, size: 19),
        label: const Text('Sign out',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
