import 'dart:ui';

// lib/presentation/screens/settings/settings_screen.dart
//
// The full settings facility. Every control writes to an AppSettings
// notifier, persists to SharedPreferences, and takes effect immediately:
//   · Appearance  — theme mode + reduce-motion accessibility
//   · Reading     — font scale, line height, serif (live preview)
//   · Alerts      — per-channel notification preferences
//   · Data        — data saver + one-tap image cache clear
//   · Account     — edit profile, change password, sign out
//   · About       — version + links

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  bool _clearingCache = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearImageCache() async {
    setState(() => _clearingCache = true);
    try {
      await DefaultCacheManager().emptyCache();
      if (!mounted) return;
      _toast('Cached images cleared — fresh covers on next load.');
    } catch (_) {
      if (!mounted) return;
      _toast('Could not clear the cache right now.');
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  Future<void> _changePassword() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: 'New password',
            hintText: 'At least 6 characters',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Update')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final password = controller.text.trim();
    if (password.length < 6) {
      _toast('Password needs at least 6 characters.');
      return;
    }
    try {
      await SupabaseService()
          .auth
          .updateUser(UserAttributes(password: password));
      _toast('Password updated ✓');
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not update the password right now.');
    }
  }

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
          const _SectionLabel('APPEARANCE'),
          const SizedBox(height: 10),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: AppSettings.themeMode,
            builder: (context, mode, _) => _SettingsCard(children: [
              const _CardHeader(
                  icon: Icons.brightness_6_rounded, title: 'Theme'),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('Auto'),
                        icon:
                            Icon(Icons.brightness_auto_rounded, size: 17)),
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
                  selectedIcon:
                      const Icon(Icons.check_rounded, size: 17),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: BookNestColors.cyan,
                    selectedForegroundColor: BookNestColors.navyDeep,
                  ),
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      AppSettings.themeMode.value = selection.first,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          _SettingsGroup(children: [
            _SwitchTile(
              icon: Icons.animation_rounded,
              title: 'Reduce motion',
              subtitle:
                  'Calms entrance animations and shimmer across the app.',
              notifier: AppSettings.reduceMotion,
            ),
          ]),
          const SizedBox(height: 24),

          const _SectionLabel('READING'),
          const SizedBox(height: 10),
          _SettingsGroup(children: [
            ValueListenableBuilder<double>(
              valueListenable: AppSettings.readerFontScale,
              builder: (context, scale, _) => _SliderTile(
                icon: Icons.format_size_rounded,
                title: 'Text size',
                value: scale,
                min: .85,
                max: 1.4,
                label: '${(scale * 100).round()}%',
                onChanged: (v) => AppSettings.readerFontScale.value = v,
              ),
            ),
            ValueListenableBuilder<double>(
              valueListenable: AppSettings.readerLineHeight,
              builder: (context, lh, _) => _SliderTile(
                icon: Icons.format_line_spacing_rounded,
                title: 'Line spacing',
                value: lh,
                min: 1.4,
                max: 2.0,
                label: lh.toStringAsFixed(2),
                onChanged: (v) => AppSettings.readerLineHeight.value = v,
              ),
            ),
            _SwitchTile(
              icon: Icons.text_fields_rounded,
              title: 'Serif typeface',
              subtitle: 'Classic book feel in the reader.',
              notifier: AppSettings.readerSerif,
            ),
          ]),
          const SizedBox(height: 10),
          // Live preview of the reader typography.
          ValueListenableBuilder3(
            builder: (context, scale, lh, serif) => Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Text(
                'The night sky over the harbour was the colour of '
                'unwritten pages — vast, patient, waiting.',
                style: TextStyle(
                  fontSize: 15 * scale,
                  height: lh,
                  fontFamily:
                      serif ? 'Georgia' : null,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          const _SectionLabel('ALERTS'),
          const SizedBox(height: 10),
          _SettingsGroup(children: [
            _SwitchTile(
              icon: Icons.favorite_rounded,
              title: 'Likes',
              notifier: AppSettings.notifyLikes,
            ),
            _SwitchTile(
              icon: Icons.comment_rounded,
              title: 'Comments & replies',
              notifier: AppSettings.notifyComments,
            ),
            _SwitchTile(
              icon: Icons.person_add_alt_rounded,
              title: 'New followers',
              notifier: AppSettings.notifyFollows,
            ),
            _SwitchTile(
              icon: Icons.chat_bubble_rounded,
              title: 'Direct messages',
              notifier: AppSettings.notifyMessages,
            ),
            _SwitchTile(
              icon: Icons.event_rounded,
              title: 'Events',
              notifier: AppSettings.notifyEvents,
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            'Muted channels stay in your notification list but no longer '
            'bubble up as new.',
            style: TextStyle(color: theme.hintColor, fontSize: 12.5),
          ),
          const SizedBox(height: 24),

          const _SectionLabel('DATA & STORAGE'),
          const SizedBox(height: 10),
          _SettingsGroup(children: [
            _SwitchTile(
              icon: Icons.savings_rounded,
              title: 'Data saver',
              subtitle:
                  'Loads lighter images on slow connections.',
              notifier: AppSettings.dataSaver,
            ),
            _SettingsRow(
              icon: Icons.cleaning_services_rounded,
              label: _clearingCache
                  ? 'Clearing cached images…'
                  : 'Clear cached images',
              onTap: _clearingCache ? () {} : _clearImageCache,
            ),
          ]),
          const SizedBox(height: 24),

          const _SectionLabel('ACCOUNT'),
          const SizedBox(height: 10),
          _SettingsGroup(children: [
            _SettingsRow(
              icon: Icons.person_outline_rounded,
              label: 'Edit profile',
              onTap: () => context.push('/settings/edit-profile'),
            ),
            _SettingsRow(
              icon: Icons.diamond_outlined,
              label: 'Gems wallet',
              onTap: () => context.push('/wallet'),
            ),
            _SettingsRow(
              icon: Icons.password_rounded,
              label: 'Change password',
              onTap: _changePassword,
            ),
            _SettingsRow(
              icon: Icons.notifications_none_rounded,
              label: 'Notification centre',
              onTap: () => context.push('/notifications'),
            ),
            _SettingsRow(
              icon: Icons.shield_outlined,
              label: 'Privacy & safety',
              onTap: () => context.push('/privacy'),
            ),
          ]),
          const SizedBox(height: 24),

          const _SectionLabel('ABOUT'),
          const SizedBox(height: 10),
          _SettingsGroup(children: [
            _SettingsRow(
              icon: Icons.auto_stories_rounded,
              label: 'About BookNest',
              onTap: () => context.push('/about'),
            ),
            const _SettingsRow(
              icon: Icons.verified_rounded,
              label: 'Version 1.1.0 · build 30',
            ),
          ]),
          const SizedBox(height: 28),
          _SignOutButton(),
        ],
      ),
    );
  }
}

/// Listens to the three reader knobs at once for the preview card.
class ValueListenableBuilder3 extends StatelessWidget {
  final Widget Function(
      BuildContext, double, double, bool) builder;

  const ValueListenableBuilder3({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: AppSettings.readerFontScale,
      builder: (context, scale, _) => ValueListenableBuilder<double>(
        valueListenable: AppSettings.readerLineHeight,
        builder: (context, lh, _) => ValueListenableBuilder<bool>(
          valueListenable: AppSettings.readerSerif,
          builder: (context, serif, _) =>
              builder(context, scale, lh, serif),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
            color: Theme.of(context).hintColor,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1));
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Theme.of(context).colorScheme.surface.withOpacity(.72),
            border: Border.all(
                color: BookNestColors.cyan.withOpacity(.16)),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children),
        ),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _CardHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: BookNestColors.cyan, size: 20),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 15)),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context).colorScheme.surface.withOpacity(.72),
        border: Border.all(color: BookNestColors.cyan.withOpacity(.16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1)
            Divider(height: 1, indent: 56, color: Theme.of(context).dividerColor),
        ],
      ]),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SettingsRow({required this.icon, required this.label, this.onTap});

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

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final ValueNotifier<bool> notifier;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, value, _) => SwitchListTile.adaptive(
        value: value,
        onChanged: (v) => notifier.value = v,
        secondary: Icon(icon, size: 21, color: BookNestColors.cyan),
        activeThumbColor: BookNestColors.cyan,
        activeTrackColor: BookNestColors.cyan.withOpacity(.35),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14.5)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!,
                style: TextStyle(
                    color: Theme.of(context).hintColor, fontSize: 12.5)),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
      child: Row(
        children: [
          Icon(icon, size: 21, color: BookNestColors.cyan),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14.5)),
                    Text(label,
                        style: TextStyle(
                            color: Theme.of(context).hintColor,
                            fontSize: 12.5)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8),
                  ),
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    activeColor: BookNestColors.cyan,
                    inactiveColor: Theme.of(context).dividerColor,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
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
          side: BorderSide(
              color: Theme.of(context).colorScheme.error.withOpacity(.5)),
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
