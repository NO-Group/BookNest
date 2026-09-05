// lib/presentation/screens/clubs/club_detail_screen.dart
//
// Real club detail: glass header, member roster size, the club's approved
// shelf, and — for the club owner — the moderation desk: approve or deny
// submitted books (moderation.queue / moderation.decide edge actions;
// approval credits the author +10 gems through the wallet ledger).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

class ClubDetailScreen extends StatefulWidget {
  final String clubId;

  const ClubDetailScreen({super.key, required this.clubId});

  @override
  State<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends State<ClubDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _club;
  int _memberCount = 0;
  List<Map<String, dynamic>> _books = const [];
  List<Map<String, dynamic>> _pending = const [];
  bool _isOwner = false;
  bool _modLoading = false;
  final Set<String> _deciding = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = SupabaseService().client;
    try {
      final gres = await BackendApi.instance
          .call('groups.get', {'kind': 'clubs', 'groupId': widget.clubId});
      final club = gres?['group'] is Map
          ? Map<String, dynamic>.from(gres!['group'] as Map)
          : null;
      if (club == null) {
        if (!mounted) return;
        setState(() {
          _error = 'This club no longer exists.';
          _loading = false;
        });
        return;
      }
      final members = ((gres?['members'] as List?) ?? const [])
          .map((m) => {'user_id': (m as Map)['user_id']})
          .toList();
      final booksRes = await BackendApi.instance
          .call('books.list', {'clubId': widget.clubId, 'limit': 50});
      final books = (booksRes?['books'] as List?) ?? const [];
      final viewerId = SupabaseService().auth.currentUser?.id;
      final owner = club['owner_id']?.toString() ?? '';
      if (!mounted) return;
      setState(() {
        _club = Map<String, dynamic>.from(club as Map);
        _memberCount = (members as List).length;
        _books = (books as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _isOwner = viewerId != null && owner == viewerId;
      });
      if (_isOwner) await _loadQueue();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this club — check your connection.';
        _loading = false;
      });
    }
  }

  Future<void> _loadQueue() async {
    setState(() => _modLoading = true);
    final res = await BackendApi.instance
        .call('moderation.queue', {'clubId': widget.clubId});
    if (!mounted) return;
    setState(() {
      _modLoading = false;
      _pending = res == null
          ? const []
          : ((res['pending'] as List?) ?? const [])
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList();
    });
  }

  Future<void> _decide(String bookId, bool approve) async {
    if (_deciding.contains(bookId)) return;
    setState(() => _deciding.add(bookId));
    final res = await BackendApi.instance
        .call('moderation.decide', {'bookId': bookId, 'approve': approve});
    if (!mounted) return;
    setState(() => _deciding.remove(bookId));
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Could not reach the moderation service — try again.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve
            ? 'Book approved — the author earned +10 gems 💎'
            : 'Book denied')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      appBar: GlassAppBar(title: _club?['name']?.toString() ?? 'Club'),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: BookNestColors.cyan))
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Something went wrong',
                  subtitle: _error!,
                  action: TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded,
                        size: 18, color: BookNestColors.cyan),
                    label: const Text('Retry',
                        style: TextStyle(color: BookNestColors.cyan)),
                  ),
                )
              : RefreshIndicator(
                  color: BookNestColors.cyan,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                    children: [
                      // ── glass header ──
                      GlassPanel(
                        radius: 24,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                          colors: [
                                            BookNestColors.navy,
                                            BookNestColors.navyDeep
                                          ]),
                                      borderRadius:
                                          BorderRadius.circular(16),
                                      border: Border.all(
                                          color: BookNestColors.cyan
                                              .withOpacity(.5)),
                                    ),
                                    child: const Icon(Icons.groups_rounded,
                                        color: Colors.white),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            _club?['name']?.toString() ??
                                                'Club',
                                            style: const TextStyle(
                                                fontSize: 19,
                                                fontWeight:
                                                    FontWeight.w800)),
                                        const SizedBox(height: 3),
                                        Text(
                                            '$_memberCount member${_memberCount == 1 ? '' : 's'}'
                                            '${(_club?['is_private'] == true) ? ' · private' : ''}',
                                            style: TextStyle(
                                                color: theme.hintColor,
                                                fontSize: 12.5)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if ((_club?['description']?.toString() ?? '')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text(_club!['description'].toString(),
                                    style: TextStyle(
                                        color: onSurface.withOpacity(.85),
                                        fontSize: 13.5,
                                        height: 1.5)),
                              ],
                              if (_isOwner) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color:
                                        BookNestColors.cyan.withOpacity(.14),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: BookNestColors.cyan
                                            .withOpacity(.4)),
                                  ),
                                  child: const Text('You own this club',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: BookNestColors.cyan)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── moderation desk (owner only) ──
                      if (_isOwner) ...[
                        Row(
                          children: [
                            const Icon(Icons.verified_user_rounded,
                                size: 18, color: BookNestColors.cyan),
                            const SizedBox(width: 8),
                            Text('Moderation desk',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            if (_modLoading)
                              const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: BookNestColors.cyan)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_pending.isEmpty)
                          GlassPanel(
                            radius: 16,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  const Icon(Icons.task_alt_rounded,
                                      color: BookNestColors.cyan, size: 19),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                        'Queue clear — no books waiting '
                                        'for review.',
                                        style: TextStyle(
                                            color: theme.hintColor,
                                            fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ..._pending.map((book) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GlassPanel(
                                  radius: 16,
                                  child: Padding(
                                    padding: const EdgeInsets.all(13),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            book['title']?.toString() ??
                                                'Untitled',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14)),
                                        const SizedBox(height: 2),
                                        Text(
                                            'by ${book['author'] ?? 'Unknown'}',
                                            style: TextStyle(
                                                color: theme.hintColor,
                                                fontSize: 12)),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            _decideButton(
                                              label: 'Approve',
                                              icon: Icons.check_rounded,
                                              filled: true,
                                              busy: _deciding.contains(
                                                  book['id']?.toString()),
                                              onTap: () => _decide(
                                                  book['id']?.toString() ??
                                                      '',
                                                  true),
                                            ),
                                            const SizedBox(width: 8),
                                            _decideButton(
                                              label: 'Deny',
                                              icon: Icons.close_rounded,
                                              filled: false,
                                              busy: _deciding.contains(
                                                  book['id']?.toString()),
                                              onTap: () => _decide(
                                                  book['id']?.toString() ??
                                                      '',
                                                  false),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )),
                        if (_pending.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                              'Approving credits the author +10 gems and '
                              'publishes the book to this club shelf.',
                              style: TextStyle(
                                  color: theme.hintColor, fontSize: 12)),
                        ],
                        const SizedBox(height: 20),
                      ],

                      // ── club shelf ──
                      const SectionHeader(title: 'Club shelf'),
                      const SizedBox(height: 10),
                      if (_books.isEmpty)
                        const EmptyState(
                          icon: Icons.library_books_rounded,
                          title: 'No books on the shelf yet',
                          subtitle: 'Approved member books appear here. '
                              'Writers: the stylus → Write a book.',
                        )
                      else
                        ..._books.map((book) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GlassPanel(
                                radius: 16,
                                child: ListTile(
                                  leading: BookCover(
                                    coverUrl:
                                        book['cover_url']?.toString(),
                                    title:
                                        book['title']?.toString() ?? 'Untitled',
                                    width: 44,
                                    height: 62,
                                  ),
                                  title: Text(
                                      book['title']?.toString() ?? 'Untitled',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                  subtitle: Text(
                                      book['author']?.toString() ?? 'Unknown',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 20),
                                  onTap: () =>
                                      context.push('/book/${book['id']}'),
                                ),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }

  Widget _decideButton({
    required String label,
    required IconData icon,
    required bool filled,
    required bool busy,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? BookNestColors.cyan : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BookNestColors.cyan.withOpacity(.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            busy
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: BookNestColors.cyan))
                : Icon(icon,
                    size: 15,
                    color: filled
                        ? BookNestColors.navyDeep
                        : BookNestColors.cyan),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: filled
                        ? BookNestColors.navyDeep
                        : BookNestColors.cyan)),
          ],
        ),
      ),
    );
  }
}
