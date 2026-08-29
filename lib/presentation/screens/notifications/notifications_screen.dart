import 'package:flutter/material.dart';

import '../../../config/app_state.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../components/booknest_ui.dart';

/// Notification center — DMs, reviews, follows. Marks everything read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  bool _offline = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await BackendApi.instance.call('notifications.list');
    if (!mounted) return;
    setState(() {
      _offline = res == null;
      _items = (res?['notifications'] as List? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _loading = false;
    });
    if (!_offline && _items.isNotEmpty) {
      await BackendApi.instance.call('notifications.read',
          <String, dynamic>{'all': true});
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'dm':
        return Icons.chat_bubble_rounded;
      case 'review':
        return Icons.star_rounded;
      case 'follow':
        return Icons.person_add_alt_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  String _label(String type) {
    switch (type) {
      case 'dm':
        return 'Message';
      case 'review':
        return 'Review';
      case 'follow':
        return 'New follower';
      default:
        return 'Update';
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
        title: const Text('Notifications',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : _offline
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Cloud not connected yet',
                  subtitle:
                      'Notifications travel through the BookNest cloud and will '
                      'appear here once it is connected.',
                  action: GradientButton(
                      label: 'Retry',
                      icon: Icons.refresh_rounded,
                      onPressed: () {
                        setState(() => _loading = true);
                        _load();
                      }),
                )
              : _items.isEmpty
                  ? const EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'All caught up',
                      subtitle:
                          'Messages, review activity and new followers land here.',
                    )
                  : RefreshIndicator(
                      color: BookNestColors.cyan,
                      onRefresh: _load,
                      child: Builder(builder: (context) {
                          final visible = _items
                              .where((n) => AppSettings.allowsNotification(
                                  n['type']?.toString() ?? 'update'))
                              .toList();
                          if (visible.isEmpty) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Text(
                                    'All caught up — or every channel is muted in Settings.'),
                              ),
                            );
                          }
                          return ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(16, 16, 16, 40),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = visible[index];
                          final type =
                              item['type']?.toString() ?? 'update';
                          final text = item['text']?.toString() ?? '';
                          final createdAt = item['createdAt'];
                          final time = createdAt is DateTime
                              ? DateFormat('MMM d, HH:mm')
                                  .format(createdAt.toLocal())
                              : '';
                          return Material(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: type == 'dm' &&
                                      item['conversationId'] != null
                                  ? () => context.push(
                                      '/chat/${item['conversationId']}')
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(13),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: BookNestColors.cyan
                                            .withOpacity(.12),
                                      ),
                                      child: Icon(_icon(type),
                                          size: 19,
                                          color: BookNestColors.cyan),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(_label(type),
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w800,
                                                  fontSize: 13)),
                                          if (text.isNotEmpty)
                                            Text(text,
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    color: theme.hintColor,
                                                    fontSize: 13,
                                                    height: 1.3)),
                                        ],
                                      ),
                                    ),
                                    Text(time,
                                        style: TextStyle(
                                            color: theme.hintColor,
                                            fontSize: 11)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                          );
                        }),
                    ),
    );
  }
}
