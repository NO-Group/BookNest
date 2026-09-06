import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/theme.dart';
import '../../../services/notification_service.dart';
import '../../components/booknest_ui.dart';

/// One friendly place where BookNest asks for everything it needs:
/// notifications (daily word + streak reminders) and photo access
/// (book covers & avatars). Shown once, always reachable from Settings.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool? _notifications;
  bool? _photos;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final n = await NotificationService.instance.dailyWordEnabled() ||
        await Permission.notification.isGranted;
    final photos = await Permission.photos.isGranted ||
        await Permission.storage.isGranted;
    if (mounted) {
      setState(() {
        _notifications = n;
        _photos = photos;
      });
    }
  }

  Future<void> _askNotifications() async {
    await NotificationService.instance.init();
    await Permission.notification.request();
    await _refresh();
  }

  Future<void> _askPhotos() async {
    // Android 13+ uses the photo permission; older versions use storage.
    final photos = await Permission.photos.request();
    if (photos.isDenied || photos.isPermanentlyDenied) {
      await Permission.storage.request();
    }
    await _refresh();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('perm_primer_done', true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const GlassAppBar(title: 'App permissions'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassPanel(
            child: Text(
              'BookNest asks only for what it truly uses — nothing more.',
              style: TextStyle(
                  color: theme.hintColor, height: 1.4, fontSize: 13.5),
            ),
          ),
          const SizedBox(height: 12),
          _PermissionCard(
            icon: Icons.notifications_active_rounded,
            title: 'Notifications',
            subtitle:
                'Daily word nudges and evening streak reminders. You pick '
                'which ones in Settings.',
            state: _notifications,
            onRequest: _askNotifications,
          ),
          _PermissionCard(
            icon: Icons.photo_library_rounded,
            title: 'Photos',
            subtitle:
                'So you can set a profile picture and add cover art to the '
                'books you publish.',
            state: _photos,
            onRequest: _askPhotos,
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: BookNestColors.cyan,
              foregroundColor: BookNestColors.navy,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _finish,
            child: const Text('Done',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool? state;
  final VoidCallback onRequest;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 24, color: BookNestColors.cyan),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          color: theme.hintColor,
                          fontSize: 12.5,
                          height: 1.35)),
                  const SizedBox(height: 10),
                  state == null
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : state!
                          ? Row(
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    size: 18, color: BookNestColors.cyan),
                                const SizedBox(width: 6),
                                const Text('Allowed',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            )
                          : FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                foregroundColor: BookNestColors.navy,
                                backgroundColor:
                                    BookNestColors.cyan.withValues(alpha: 0.25),
                              ),
                              onPressed: onRequest,
                              child: const Text('Allow'),
                            ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
