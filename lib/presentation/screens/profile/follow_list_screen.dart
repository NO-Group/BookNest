import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// Followers or Following list for any user (?type=followers|following).
class FollowListScreen extends StatefulWidget {
  final String userId;
  final String type; // 'followers' | 'following'

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.type,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  bool _loading = true;
  bool _offline = false;
  List<Map<String, dynamic>> _people = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res =
        await BackendApi.instance.listSocial(widget.userId, type: widget.type);
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _offline = true;
        _loading = false;
      });
      return;
    }
    final ids = (res['userIds'] as List? ?? [])
        .map((id) => id.toString())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final rows = await SupabaseService()
          .client
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .in('id', ids);
      if (!mounted) return;
      setState(() {
        _people = (rows as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.type == 'following' ? 'Following' : 'Followers';
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? BookNestColors.darkChatBackground
          : BookNestColors.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan))
          : _offline
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Cloud not connected yet',
                  subtitle:
                      'The social graph lives in the BookNest cloud. It will '
                      'show here once connected.',
                )
              : _people.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'Nobody here yet',
                      subtitle:
                          'Share a great book — readers follow great taste.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                      itemCount: _people.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final person = _people[index];
                        final name =
                            (person['display_name'] ?? person['username'] ?? 'Reader')
                                .toString();
                        return Material(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            leading: BookNestAvatar(
                              imageUrl: person['avatar_url']?.toString(),
                              name: name,
                              radius: 21,
                            ),
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: person['username'] == null
                                ? null
                                : Text('@${person['username']}'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () =>
                                context.push('/user/${person['id']}'),
                          ),
                        );
                      },
                    ),
    );
  }
}
