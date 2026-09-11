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
import '../../components/book_picker_sheet.dart';

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
  bool _isMember = false;
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _books = const [];
  List<Map<String, dynamic>> _pending = const [];
  bool _isOwner = false;
  bool _isManager = false;
  Map<String, dynamic>? _potm;
  bool _potmBusy = false;
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
      final announcementsRes = await BackendApi.instance
          .call('groups.announcements.list', {'groupId': widget.clubId});
      final booksRes = await BackendApi.instance
          .call('books.list', {'clubId': widget.clubId, 'limit': 50});
      final books = (booksRes?['books'] as List?) ?? const [];
      final viewerId = SupabaseService().auth.currentUser?.id;
      // groups docs store ownerId (camelCase); some older rows may carry
      // owner_id — accept both so owner powers always resolve.
      final owner =
          (club['ownerId'] ?? club['owner_id'])?.toString() ?? '';
      final vice = club['viceModeratorId']?.toString() ?? '';
      final potm = club['potm'] is Map
          ? Map<String, dynamic>.from(club['potm'] as Map)
          : null;
      if (!mounted) return;
      setState(() {
        _club = Map<String, dynamic>.from(club as Map);
        _potm = potm;
        _isManager =
            (viewerId != null && owner == viewerId) ||
                (viewerId != null && vice == viewerId);
        _memberCount = (members as List).length;
        _books = (books as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _announcements = (((announcementsRes?['announcements'] as List?) ?? const []))
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _isOwner = viewerId != null && owner == viewerId;
        _isMember = _isOwner ||
            (viewerId != null &&
                members.any((m) => m['user_id']?.toString() == viewerId));
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

  Future<void> _postAnnouncement() async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    final posted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New announcement',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: titleController,
              autofocus: true,
              maxLength: 160,
              decoration: const InputDecoration(
                  labelText: 'Headline', hintText: 'What is happening?'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bodyController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                  labelText: 'Message',
                  hintText: 'Tell every member of the group…'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (titleController.text.trim().isEmpty ||
                      bodyController.text.trim().isEmpty) {
                    return;
                  }
                  Navigator.pop(sheetContext, true);
                },
                child: const Text('Post to the forum'),
              ),
            ),
          ],
        ),
      ),
    );
    if (posted != true || !mounted) return;
    final res = await BackendApi.instance.call('groups.announcements.post', {
      'groupId': widget.clubId,
      'kind': 'clubs',
      'title': titleController.text.trim(),
      'body': bodyController.text.trim(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res == null
          ? 'The announcement could not be posted — please try again.'
          : 'Announcement posted to every member.'),
    ));
    if (res != null) _load();
  }

  Future<void> _deleteAnnouncement(String id) async {
    final res = await BackendApi.instance
        .call('groups.announcements.delete', {'announcementId': id});
    if (!mounted) return;
    if (res != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement removed.')));
      _load();
    }
  }

  List<Widget> _potmSection(ThemeData theme) {
    final onSurface = theme.colorScheme.onSurface;
    final potm = _potm;
    return [
      GlassPanel(
        radius: 24,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.auto_stories_rounded,
                    size: 19, color: BookNestColors.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Book of the month',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: onSurface)),
                ),
                if (_isManager && _potmBusy)
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: BookNestColors.cyan)),
                if (_isManager && _potmBusy == false && potm != null)
                  IconButton(
                    tooltip: 'Clear the club read',
                    onPressed: _clearPotm,
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 18, color: onSurface.withOpacity(.5)),
                  ),
              ]),
              const SizedBox(height: 8),
              if (potm == null)
                Text(
                  _isManager
                      ? 'Pick the book every member should read this month.'
                      : 'The club has not picked its read yet.',
                  style: TextStyle(
                      fontSize: 12.5, color: onSurface.withOpacity(.6)),
                )
              else
                Row(children: [
                  GestureDetector(
                    onTap: () => context
                        .push('/book/${potm['bookId']?.toString() ?? ''}'),
                    child: BookCover(
                      coverUrl: potm['coverUrl']?.toString(),
                      title: potm['title']?.toString() ?? 'Book',
                      width: 62,
                      height: 84,
                      radius: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(potm['title']?.toString() ?? 'Untitled',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: onSurface)),
                        const SizedBox(height: 3),
                        Text(
                            'by ${potm['authorName']?.toString() ?? 'Unknown'}',
                            style: TextStyle(
                                fontSize: 12,
                                color: onSurface.withOpacity(.6))),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: () => context.push(
                              '/book/${potm['bookId']?.toString() ?? ''}'),
                          style: FilledButton.styleFrom(
                            backgroundColor: BookNestColors.navy,
                            foregroundColor: BookNestColors.cyan,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ),
                          icon: const Icon(Icons.menu_book_rounded,
                              size: 15),
                          label: const Text('Read now',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ]),
              if (_isManager && potm == null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _potmBusy ? null : _pickPotm,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: BookNestColors.cyan.withOpacity(.55)),
                    foregroundColor: BookNestColors.cyan,
                  ),
                  icon: const Icon(Icons.emoji_events_rounded, size: 17),
                  label: const Text('Pick the club read',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  Future<void> _pickPotm() async {
    if (_potmBusy) return;
    final book = await showBookPicker(context, title: 'Pick the club read');
    if (book == null) return;
    setState(() => _potmBusy = true);
    final res = await BackendApi.instance.call('clubs.potm.set', {
      'groupId': widget.clubId,
      'kind': 'clubs',
      'bookId': book['id']?.toString() ?? '',
    });
    if (!mounted) return;
    setState(() => _potmBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res == null
            ? 'Could not set the club read — try again.'
            : '"${book['title']}" is this month\'s read. 📖')));
    if (res != null) _load();
  }

  Future<void> _clearPotm() async {
    if (_potmBusy) return;
    setState(() => _potmBusy = true);
    final res = await BackendApi.instance.call('clubs.potm.clear', {
      'groupId': widget.clubId,
      'kind': 'clubs',
    });
    if (!mounted) return;
    setState(() => _potmBusy = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not clear it — try again.')));
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      appBar: GlassAppBar(
        title: _club?['name']?.toString() ?? 'Club',
        actions: [
          if (_isMember)
            IconButton(
              icon: const Icon(Icons.forum_outlined),
              tooltip: 'Group chat',
              onPressed: () {
                final id = _club?['id']?.toString() ?? '';
                if (id.isEmpty) return;
                context.push(
                  '/club-chat?id=$id&kind=clubs'
                  '&title=${Uri.encodeComponent(_club?['name']?.toString() ?? 'Club')}',
                );
              },
            ),
        ],
      ),
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
                      _AnnouncementsSection(
                        announcements: _announcements,
                        isOwner: _isOwner,
                        onPost: _postAnnouncement,
                        onDelete: _deleteAnnouncement,
                      ),
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
                      const SizedBox(height: 16),

                      // ── book of the month (the club read) ──
                      ..._potmSection(theme),

                      const SizedBox(height: 12),

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

/// Every group is born with an announcement forum — this renders it.
/// Owners post and remove; members read. Pinned posts float to the top.
class _AnnouncementsSection extends StatelessWidget {
  final List<Map<String, dynamic>> announcements;
  final bool isOwner;
  final Future<void> Function() onPost;
  final Future<void> Function(String id) onDelete;

  const _AnnouncementsSection({
    required this.announcements,
    required this.isOwner,
    required this.onPost,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final sorted = [...announcements]
      ..sort((a, b) {
        final pinnedA = a['pinned'] == true ? 1 : 0;
        final pinnedB = b['pinned'] == true ? 1 : 0;
        if (pinnedA != pinnedB) return pinnedB - pinnedA;
        final aTime = DateTime.tryParse(a['createdAt']?.toString() ?? '');
        final bTime = DateTime.tryParse(b['createdAt']?.toString() ?? '');
        return (bTime ?? DateTime(0)).compareTo(aTime ?? DateTime(0));
      });

    return GlassPanel(
      radius: 22,
      blur: 16,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_rounded,
                    color: BookNestColors.cyan, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Announcement forum',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (isOwner)
                  IconButton.filledTonal(
                    onPressed: onPost,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    color: BookNestColors.cyan,
                    tooltip: 'Post an announcement',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (sorted.isEmpty)
              Text(
                'Announcements from the owners will appear here — every '
                'member sees them the moment they land.',
                style: TextStyle(color: theme.hintColor, height: 1.45),
              )
            else
              ...sorted.map((item) {
                final pinned = item['pinned'] == true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.white.withOpacity(.04)
                        : BookNestColors.lightSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: BookNestColors.cyan.withOpacity(pinned ? .45 : .2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (pinned)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.push_pin_rounded,
                                  size: 13, color: BookNestColors.cyan),
                            ),
                          Expanded(
                            child: Text(
                              item['title']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 13.5),
                            ),
                          ),
                          if (isOwner)
                            GestureDetector(
                              onTap: () =>
                                  onDelete(item['id']?.toString() ?? ''),
                              child: const Icon(Icons.close_rounded,
                                  size: 16, color: BookNestColors.cyan),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item['body']?.toString() ?? '',
                        style: TextStyle(
                            height: 1.45,
                            fontSize: 13,
                            color: dark
                                ? BookNestColors.darkTextSecondary
                                : BookNestColors.navyDeep.withOpacity(.85)),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
