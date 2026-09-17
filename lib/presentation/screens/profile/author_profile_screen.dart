import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../services/call_service.dart';
import '../calls/call_screen.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';
import '../../components/report_sheet.dart';
import '../../components/watermark_background.dart';

/// Public profile — with TWO faces. A reader's page keeps the familiar
/// identity-header layout; an author's page switches to the second
/// design: a full-bleed banner with the wordmark pattern, an avatar
/// overlapping its edge, stat chips, action buttons and card tabs —
/// the layout readers already know from the profile screens of the
/// big community apps.
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
  bool _modeLoaded = false;
  DateTime? _joinedAt;

  String? get _viewerId => SupabaseService().auth.currentUser?.id;
  bool get _isMe => _viewerId == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBlocked();
    _loadMode();
    _loadJoined();
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

  /// Decides which of the two profile faces renders. Fails open to the
  /// reader face so a network hiccup never blanks the screen.
  Future<void> _loadMode() async {
    var author = false;
    try {
      final res = await BackendApi.instance
          .call('profile.mode.get', {'userId': widget.userId});
      author = res?['mode']?.toString() == 'author';
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isAuthor = author;
        _modeLoaded = true;
      });
    }
  }

  /// The "joined" date for the author face. Queried separately on
  /// purpose: if the column ever goes missing this degrades to simply
  /// hiding the joined chip instead of failing the whole profile.
  Future<void> _loadJoined() async {
    try {
      final row = await SupabaseService().client
          .from('profiles')
          .select('created_at')
          .eq('id', widget.userId)
          .maybeSingle();
      final raw = row?['created_at']?.toString();
      final d = raw == null ? null : DateTime.tryParse(raw);
      if (d != null && mounted) setState(() => _joinedAt = d);
    } catch (_) {}
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
            .select('id, username, display_name, avatar_url, gems')
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
      (_profile?['username']?.toString() ?? '').trim().replaceAll(RegExp(r'^@'), '');

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
    if (_loading || !_modeLoaded) {
      return const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan)));
    }
    final followers =
        ((_stats?['followers'] as num?)?.toInt() ?? 0) + _followerDelta;
    final following = (_stats?['following'] as num?)?.toInt() ?? 0;
    // ── The second face: author mode renders the banner layout. ──
    if (_isAuthor) {
      return _buildAuthorPage(context,
          dark: dark, followers: followers, following: following);
    }
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

  // ── The author face — the second profile design ────────────────────
  // Rendered only when the profile owner is in Author mode: full-bleed
  // banner (a per-user navy/cyan blend under the BookNest wordmark
  // pattern), avatar overlapping the banner edge, stat chips, follow
  // and message buttons, then Works & About as outlined cards.

  static const double _bannerExtra = 72;

  /// Deterministic per-user banner blend — the same profile always
  /// shows the same banner, with zero uploads or storage.
  List<Color> get _bannerColors {
    var h = 0;
    for (final c in widget.userId.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    const pairs = <List<Color>>[
      [BookNestColors.navyDeep, BookNestColors.navy],
      [BookNestColors.navy, Color(0xFF123B63)],
      [Color(0xFF071A3D), Color(0xFF14486B)],
    ];
    return pairs[h % pairs.length];
  }

  Widget get _authorBadge => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: BookNestColors.cyan.withOpacity(.14),
          border: Border.all(color: BookNestColors.cyan.withOpacity(.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_edu_rounded,
                size: 12, color: BookNestColors.cyan),
            SizedBox(width: 4),
            Text('Author',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: BookNestColors.cyan)),
          ],
        ),
      );

  List<Widget> _authorActions() {
    return [
      if (!_isMe) ...[
        IconButton(
          tooltip: 'Voice call',
          icon: const Icon(Icons.call_outlined,
              size: 20, color: Colors.white),
          onPressed: () => _call(video: false),
        ),
        IconButton(
          tooltip: 'Video call',
          icon: const Icon(Icons.videocam_outlined,
              size: 21, color: Colors.white),
          onPressed: () => _call(video: true),
        ),
      ],
      if (!_isMe)
        PopupMenuButton<String>(
          tooltip: 'More options',
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
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
    ];
  }

  Widget _buildAuthorPage(BuildContext context,
      {required bool dark, required int followers, required int following}) {
    final theme = Theme.of(context);
    final topPad = MediaQuery.of(context).padding.top;
    final bannerH = topPad + kToolbarHeight + _bannerExtra;
    final gems = (_profile?['gems'] as num?)?.toInt() ?? 0;
    final joined =
        _joinedAt == null ? null : DateFormat('d MMM y').format(_joinedAt!);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: dark
            ? BookNestColors.darkChatBackground
            : BookNestColors.lightSurface,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: _authorActions(),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Banner: per-user gradient under the BookNest pattern,
            //    avatar ringed and overlapping its bottom edge ──
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  height: bannerH,
                  width: double.infinity,
                  child: WatermarkOverlay(
                    color: Colors.white,
                    opacity: 0.08,
                    spacing: 148,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _bannerColors,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  bottom: -38,
                  child: Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                          color: dark
                              ? Colors.white
                              : BookNestColors.lightBorder),
                    ),
                    child: BookNestAvatar(
                      imageUrl: _profile?['avatar_url']?.toString(),
                      name: _name,
                      radius: 34,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 50),
            // ── Name, author badge, handle ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Row(
                children: [
                  Flexible(
                    child: Text(_name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  _authorBadge,
                ],
              ),
            ),
            if (_username?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 3),
                child: Text('@$_username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: BookNestColors.cyan,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
              ),
            // ── Stat chips: books, followers, following, gems, joined ──
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _redditChip(Icons.menu_book_rounded,
                        '${_works.length} books'),
                    _redditChip(Icons.person_rounded, '$followers followers',
                        onTap: () => context.push(
                            '/user/${widget.userId}/follows?type=followers')),
                    _redditChip(
                        Icons.person_outline_rounded, '$following following',
                        onTap: () => context.push(
                            '/user/${widget.userId}/follows?type=following')),
                    _redditChip(Icons.diamond_rounded, '$gems gems'),
                    if (joined != null)
                      _redditChip(Icons.cake_rounded, 'Joined $joined'),
                  ],
                ),
              ),
            ),
            // ── Action buttons ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
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
                        Expanded(
                          child: _pill(
                            context,
                            dark: dark,
                            filled: false,
                            icon: Icons.chat_bubble_outline_rounded,
                            label: 'Message',
                            onTap: () =>
                                context.push('/chat/peer/${widget.userId}'),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: _pill(
                        context,
                        dark: dark,
                        filled: false,
                        icon: Icons.edit_rounded,
                        label: 'Edit profile',
                        onTap: () => context.push('/settings/edit-profile'),
                      ),
                    ),
            ),
            // ── Tabs: outlined-card works feed & about ──
            TabBar(
              indicatorColor: BookNestColors.cyan,
              labelColor: dark ? Colors.white : BookNestColors.navy,
              unselectedLabelColor: theme.hintColor,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              dividerColor: theme.dividerColor,
              tabs: const [Tab(text: 'Works'), Tab(text: 'About')],
            ),
            Expanded(
              child: TabBarView(
                children: [
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
                              _WorkCard(book: _works[i]),
                        ),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                    children: [
                      if (joined != null)
                        _aboutRow(
                            context, Icons.cake_rounded, 'Joined', joined),
                      _aboutRow(
                          context, Icons.person_rounded, 'Member', 'Author'),
                      _aboutRow(context, Icons.menu_book_rounded,
                          'Books published', '${_works.length}'),
                      _aboutRow(
                          context, Icons.favorite_rounded, 'Followers',
                          '$followers'),
                      _aboutRow(context, Icons.person_search_rounded,
                          'Following', '$following'),
                      _aboutRow(
                          context, Icons.diamond_rounded, 'Gems', '$gems'),
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

  /// Rounded stat pill — icon + live count, tappable where it opens a list.
  Widget _redditChip(IconData icon, String label, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: BookNestColors.cyan),
          const SizedBox(width: 6),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
        borderRadius: BorderRadius.circular(18), onTap: onTap, child: chip);
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

/// Outlined work card for the author face — cover, title, genre, a
/// two-line description teaser and a live rating/likes meta row.
class _WorkCard extends StatelessWidget {
  final Map<String, dynamic> book;
  const _WorkCard({required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = book['id']?.toString() ?? '';
    final title = book['title']?.toString() ?? 'Untitled';
    final desc = book['description']?.toString().trim() ?? '';
    final genre = book['genre']?.toString().trim() ?? '';
    final rating = (book['average_rating'] as num?)?.toDouble() ?? 0;
    final likes = (book['like_count'] as num?)?.toInt() ?? 0;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/book/$id'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(coverUrl: book['cover_url']?.toString(), title: title),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14.5)),
                    if (genre.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(genre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: BookNestColors.cyan,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ),
                    if (desc.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: theme.hintColor,
                                fontSize: 12,
                                height: 1.3)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 14, color: BookNestColors.cyan),
                          const SizedBox(width: 3),
                          Text(rating > 0 ? '$rating' : 'New',
                              style: TextStyle(
                                  color: theme.hintColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 12),
                          const Icon(Icons.favorite_rounded,
                              size: 13, color: BookNestColors.cyan),
                          const SizedBox(width: 3),
                          Text('$likes',
                              style: TextStyle(
                                  color: theme.hintColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
