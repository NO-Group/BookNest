import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/call_service.dart';
import '../calls/call_screen.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';
import '../../components/report_sheet.dart';

/// Public author profile — every reader's page, laid out the way readers
/// expect from the apps they already live in: a left-aligned identity
/// header, plain stat counters, action pills, then tabs for works & about.
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
  bool _blocked = false;
  bool _isAuthor = false;

  String? get _viewerId => SupabaseService().auth.currentUser?.id;
  bool get _isMe => _viewerId == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBlocked();
    _loadMode();
    _loadFollowing();
  }

  /// Starts the screen with the follow state already truthful (the
  /// optimistic toggle still handles the tap).
  Future<void> _loadFollowing() async {
    if (_isMe) return;
    final res = await BackendApi.instance
        .call('social.list', {'kind': 'following', 'userId': widget.userId});
    final rows = (res?['users'] as List?) ?? const [];
    for (final row in rows) {
      if (row is Map && row['id'].toString() == _viewerId) {
        if (mounted) setState(() => _following = true);
        return;
      }
    }
  }

  Future<void> _loadMode() async {
    final res = await BackendApi.instance
        .call('profile.mode.get', {'userId': widget.userId});
    if (res?['mode']?.toString() == 'author' && mounted) {
      setState(() => _isAuthor = true);
    }
  }

  Future<void> _loadBlocked() async {
    if (_isMe) return;
    final res = await BackendApi.instance.call('dm.blocklist');
    final blocked = res?['blocked'];
    if (blocked is List && mounted) {
      setState(() => _blocked = blocked.contains(widget.userId));
    }
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
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

  String get _username =>
      _profile?['username']?.toString().trim().replaceAll(RegExp(r'^@'), '');

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
  Future<void> _call({required bool video}) async {
    if (widget.userId.isEmpty) return;
    final service = CallService.instance;
    if (service.status != CallStatus.idle) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already in a call.')));
      return;
    }
    await service.startCall(
        peerId: widget.userId, peerName: _name, video: video);
    if (!mounted) return;
    CallScreen.open(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    if (_loading) {
      return const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan)));
    }
    final followers =
        ((_stats?['followers'] as num?)?.toInt() ?? 0) + _followerDelta;
    final following = (_stats?['following'] as num?)?.toInt() ?? 0;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: dark
            ? BookNestColors.darkChatBackground
            : BookNestColors.lightSurface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(_name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (_isAuthor) ...[
                const SizedBox(width: 7),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: BookNestColors.cyan.withOpacity(.14),
                    border:
                        Border.all(color: BookNestColors.cyan.withOpacity(.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_edu_rounded,
                          size: 11, color: BookNestColors.cyan),
                      SizedBox(width: 3),
                      Text('Author',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: BookNestColors.cyan)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (!_isMe && !_loading) ...[
              IconButton(
                tooltip: 'Voice call',
                icon: const Icon(Icons.call_outlined, size: 20),
                onPressed: () => _call(video: false),
              ),
              IconButton(
                tooltip: 'Video call',
                icon: const Icon(Icons.videocam_outlined, size: 21),
                onPressed: () => _call(video: true),
              ),
            ],
            if (!_isMe && !_loading)
              PopupMenuButton<String>(
                tooltip: 'More options',
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) async {
                  if (value == 'report') {
                    await showReportSheet(context,
                        kind: ReportTargetKind.user,
                        targetId: widget.userId,
                        hintName: _name);
                  }
                  if (value == 'block') {
                    await confirmBlock(
                      context,
                      peerId: widget.userId,
                      peerName: _name,
                      currentlyBlocked: _blocked,
                    );
                    if (mounted) {
                      setState(() => _blocked = !_blocked);
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'report',
                    child: Row(children: [
                      Icon(Icons.flag_rounded,
                          color: Colors.redAccent, size: 19),
                      SizedBox(width: 10),
                      Text('Report profile'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'block',
                    child: Row(children: [
                      Icon(
                          _blocked
                              ? Icons.lock_open_rounded
                              : Icons.block_rounded,
                          size: 19),
                      SizedBox(width: 10),
                      Text(_blocked ? 'Unblock reader' : 'Block reader'),
                    ]),
                  ),
                ],
              ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Identity header: avatar left, name + @handle beside it ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  BookNestAvatar(
                    imageUrl: _profile?['avatar_url']?.toString(),
                    name: _name,
                    radius: 32,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        if (_username?.isNotEmpty == true)
                          Text('@$_username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: BookNestColors.cyan,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Plain stat counters (tap → follower/following lists) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  _countBlock('${_works.length}', 'Books'),
                  _countBlock('$followers', 'Followers',
                      onTap: () => context.push(
                          '/user/${widget.userId}/follows?type=followers')),
                  _countBlock('$following', 'Following',
                      onTap: () => context.push(
                          '/user/${widget.userId}/follows?type=following')),
                ],
              ),
            ),
            // ── Action pills ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: !_isMe
                  ? Row(
                      children: [
                        Expanded(
                          child: _pill(
                            context,
                            dark: dark,
                            filled: !_following,
                            busy: _followBusy,
                            icon: _following
                                ? Icons.check_rounded
                                : Icons.person_add_alt_rounded,
                            label: _followBusy
                                ? '…'
                                : (_following ? 'Following' : 'Follow'),
                            onTap: _toggleFollow,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _pill(
                          context,
                          dark: dark,
                          filled: false,
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Message',
                          onTap: () =>
                              context.push('/chat/peer/${widget.userId}'),
                        ),
                      ],
                    )
                  : _pill(
                      context,
                      dark: dark,
                      filled: false,
                      icon: Icons.edit_rounded,
                      label: 'Edit profile',
                      onTap: () => context.push('/settings/edit-profile'),
                    ),
            ),
            // ── Tabs: works & about, like the feed apps readers know ──
            TabBar(
              indicatorColor: BookNestColors.cyan,
              labelColor: dark ? Colors.white : BookNestColors.navy,
              unselectedLabelColor: theme.hintColor,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              dividerColor: theme.dividerColor,
              tabs: const [Tab(text: 'Books'), Tab(text: 'About')],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // ── Books tab ──
                  _works.isEmpty
                      ? Center(
                          child: Text(
                            _isMe
                                ? 'Publish a book and it will appear here.'
                                : 'No published books yet.',
                            style: TextStyle(color: theme.hintColor),
                          ),
                        )
                      : ListView.separated(
                          padding:
                              const EdgeInsets.fromLTRB(20, 14, 20, 40),
                          itemCount: _works.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) =>
                              _AuthorBookRow(book: _works[i]),
                        ),
                  // ── About tab ──
                  ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                    children: [
                      _aboutRow(context, Icons.person_rounded, 'Member',
                          _isAuthor ? 'Author' : 'Reader'),
                      _aboutRow(context, Icons.menu_book_rounded,
                          'Books published', '${_works.length}'),
                      _aboutRow(
                          context, Icons.favorite_rounded, 'Followers',
                          '$followers'),
                      _aboutRow(context, Icons.person_search_rounded,
                          'Following', '$following'),
                      if (_username?.isNotEmpty == true)
                        _aboutRow(context, Icons.alternate_email_rounded,
                            'Handle', '@$_username'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countBlock(String value, String label, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final block = Padding(
      padding: const EdgeInsets.only(right: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(
                  color: theme.hintColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
    if (onTap == null) return block;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: block,
    );
  }

  Widget _pill(
    BuildContext context, {
    required bool dark,
    required bool filled,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    return Material(
      color: filled
          ? BookNestColors.cyan
          : (dark ? Colors.white.withOpacity(.06) : BookNestColors.navy.withOpacity(.05)),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: busy ? null : onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 17,
                  color: filled
                      ? BookNestColors.navyDeep
                      : BookNestColors.cyan),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: filled
                          ? BookNestColors.navyDeep
                          : BookNestColors.cyan)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aboutRow(BuildContext context, IconData icon, String label,
      String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: BookNestColors.cyan),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(color: theme.hintColor, fontSize: 13.5)),
          const Spacer(),
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
        ],
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
