import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// Public author profile — any reader's page: avatar, follow, stats, works.
class AuthorProfileScreen extends StatefulWidget {
  final String userId;

  const AuthorProfileScreen({super.key, required this.userId});

  @override
  State<AuthorProfileScreen> createState() => _AuthorProfileScreenState();
}

class _AuthorProfileScreenState extends State<AuthorProfileScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _works = [];
  bool _loading = true;
  bool _following = false;
  bool _followBusy = false;
  int _followerDelta = 0;

  String? get _viewerId => SupabaseService().auth.currentUser?.id;
  bool get _isMe => _viewerId == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        SupabaseService()
            .client
            .from('profiles')
            .select('id, username, display_name, avatar_url')
            .eq('id', widget.userId)
            .maybeSingle(),
        BackendApi.instance
            .call('books.list', {'authorId': widget.userId, 'limit': 50})
            .then((res) => (res?['books'] as List?) ?? const []),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] == null
            ? null
            : Map<String, dynamic>.from(results[0] as Map);
        _works = (results[1] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
      });
    } catch (_) {}
    final stats = await BackendApi.instance.fetchUserStats(widget.userId);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  String get _name {
    final name =
        (_profile?['display_name'] ?? _profile?['username'])?.toString();
    return (name == null || name.trim().isEmpty)
        ? 'BookNest reader'
        : name.trim();
  }

  void _toggleFollow() {
    if (_followBusy) return;
    setState(() {
      _following = !_following;
      _followBusy = true;
      _followerDelta += _following ? 1 : -1;
    });
    BackendApi.instance.setFollowing(widget.userId, _following).whenComplete(() {
      if (mounted) setState(() => _followBusy = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan)));
    }
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? BookNestColors.darkChatBackground
          : BookNestColors.lightSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_name,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          children: [
            BookNestAvatar(
              imageUrl: _profile?['avatar_url']?.toString(),
              name: _name,
              radius: 44,
            ),
            const SizedBox(height: 12),
            Text(_name,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (_profile?['username']?.toString().isNotEmpty == true)
              Text('@${_profile?['username']}',
                  style: const TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.w600)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.menu_book_rounded,
                    value: '${_works.length}',
                    label: 'Books',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => context.push(
                        '/user/${widget.userId}/follows?type=followers'),
                    child: StatTile(
                      icon: Icons.favorite_rounded,
                      value:
                          '${((_stats?['followers'] as num?)?.toInt() ?? 0) + _followerDelta}',
                      label: 'Followers',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => context.push(
                        '/user/${widget.userId}/follows?type=following'),
                    child: StatTile(
                      icon: Icons.person_search_rounded,
                      value: '${_stats?['following'] ?? '—'}',
                      label: 'Following',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (!_isMe)
              GradientButton(
                label: _followBusy ? '…' : (_following ? 'Following ✓' : 'Follow'),
                icon: _following
                    ? Icons.person_remove_alt_1_rounded
                    : Icons.person_add_alt_rounded,
                onPressed: _toggleFollow,
              )
            else
              OutlinedButton.icon(
                onPressed: () => context.push('/settings/edit-profile'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BookNestColors.cyan,
                  side: const BorderSide(color: BookNestColors.cyan),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit profile',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            const SizedBox(height: 26),
            SectionHeader(title: 'Books by $_name'),
            const SizedBox(height: 12),
            if (_works.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Text(
                  _isMe
                      ? 'Publish a book and it will appear here.'
                      : 'No published books yet.',
                  style: TextStyle(color: theme.hintColor),
                ),
              )
            else
              ..._works.map((book) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AuthorBookRow(book: book),
                  )),
          ],
        ),
      ),
    );
  }

}

class _AuthorBookRow extends StatelessWidget {
  final Map<String, dynamic> book;
  const _AuthorBookRow({required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = book['id']?.toString() ?? '';
    final title = book['title']?.toString() ?? 'Untitled';
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/book/$id'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              BookCover(coverUrl: book['cover_url']?.toString(), title: title),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.hintColor),
            ],
          ),
        ),
      ),
    );
  }
}
