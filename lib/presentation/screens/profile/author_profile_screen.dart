import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/theme.dart';
import '../../../services/call_service.dart';
import '../calls/call_screen.dart';
import '../../../services/backend_api.dart';
import '../../../services/cloudinary_service.dart';
import '../chat/media_viewer_screen.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';
import '../../components/report_sheet.dart';
import '../../components/watermark_background.dart';

/// Public profile. One responsive design for readers and authors (authors
/// add the badge, cyan-tinted banner and Works cards): phones scroll the
/// whole header away under pinned tabs; PC shows a sticky profile card
/// beside a works grid.
///
/// History: it used to have TWO faces. A reader's page keeps the familiar
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
    _loadCover();
    final stats = await BackendApi.instance.fetchUserStats(widget.userId);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  /// Read on its own so the profile still loads if the column is missing.
  Future<void> _loadCover() async {
    try {
      final row = await SupabaseService()
          .client
          .from('profiles')
          .select('cover_url')
          .eq('id', widget.userId)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _profile = {...?_profile, 'cover_url': row['cover_url']});
    } catch (_) {}
  }

  String? get _coverUrl {
    final url = _profile?['cover_url']?.toString();
    return url != null && url.startsWith('http') ? url : null;
  }

  void _viewCover() {
    final url = _coverUrl;
    if (url == null) return;
    openChatPhoto(context, url,
        album: [MediaItem(url: url, name: '$_name · cover photo')]);
  }

  Widget _coverImage() => CachedNetworkImage(
        imageUrl: CloudinaryService.transformUrl(_coverUrl!, width: 1280),
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 200),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      );

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
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_loading || !_modeLoaded) {
      return const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan)));
    }
    final followers =
        ((_stats?['followers'] as num?)?.toInt() ?? 0) + _followerDelta;
    final following = (_stats?['following'] as num?)?.toInt() ?? 0;
    final bg =
        dark ? BookNestColors.darkChatBackground : BookNestColors.lightSurface;
    return DefaultTabController(
      length: 2,
      child: LayoutBuilder(builder: (context, box) {
        // Big screens get a two-column page (sticky profile card + works
        // grid); phones get one scrolling column with pinned tabs.
        final wide = box.maxWidth >= 1000;
        if (wide) {
          return Scaffold(
            backgroundColor: bg,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(_name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              actions: _authorActions(compact: false),
            ),
            body: _wideLayout(context,
                dark: dark,
                followers: followers,
                following: following,
                cardWidth: box.maxWidth >= 1300 ? 380 : 340),
          );
        }
        return Scaffold(
          backgroundColor: bg,
          body: _phoneLayout(context,
              dark: dark, bg: bg, followers: followers, following: following),
        );
      }),
    );
  }

  int get _gems => (_profile?['gems'] as num?)?.toInt() ?? 0;
  String? get _joined =>
      _joinedAt == null ? null : DateFormat('d MMM y').format(_joinedAt!);

  // ── Phone: banner → identity → pinned tabs, all in one scroll ──────
  Widget _phoneLayout(BuildContext context,
      {required bool dark,
      required Color bg,
      required int followers,
      required int following}) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final topPad = media.padding.top;
    const avatarR = 38.0;
    const strip = avatarR + 8; // part of the avatar below the banner
    final art = (media.size.width * .24).clamp(64.0, 120.0);
    final expanded = kToolbarHeight + art + strip;
    final minH = topPad + kToolbarHeight;
    final maxH = topPad + expanded;
    return NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverAppBar(
          pinned: true,
          expandedHeight: expanded,
          elevation: 0,
          backgroundColor: _bannerColors.first,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          systemOverlayStyle: SystemUiOverlayStyle.light,
          actions: _authorActions(compact: true),
          flexibleSpace: LayoutBuilder(builder: (context, c) {
            final t = ((c.maxHeight - minH) / (maxH - minH)).clamp(0.0, 1.0);
            final s = strip * t;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: s,
                  child: GestureDetector(
                    onTap: _viewCover,
                    child: _bannerArt(),
                  ),
                ),
                Positioned(
                    left: 0, right: 0, bottom: 0, height: s,
                    child: ColoredBox(color: bg)),
                if (t > .35)
                  Positioned(
                    left: 20,
                    bottom: 0,
                    child: Opacity(
                      opacity: ((t - .35) / .4).clamp(0.0, 1.0),
                      child: _avatarRing(avatarR, dark),
                    ),
                  ),
                if (t < .2)
                  Positioned(
                    left: 64,
                    right: _isMe ? 16 : 64,
                    top: topPad,
                    height: kToolbarHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            );
          }),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: _identity(context,
                dark: dark, followers: followers, following: following),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabsHeader(_tabBar(theme, dark), bg),
        ),
      ],
      body: TabBarView(
        children: [
          _works.isEmpty
              ? _emptyWorks(theme)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                  itemCount: _works.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _WorkCard(book: _works[i]),
                ),
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
            children: [
              _card(theme,
                  child: Column(
                      children: _aboutRows(context,
                          followers: followers, following: following))),
            ],
          ),
        ],
      ),
    );
  }

  // ── PC / tablet landscape: sticky card left, works grid right ──────
  Widget _wideLayout(BuildContext context,
      {required bool dark,
      required int followers,
      required int following,
      required double cardWidth}) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: cardWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 12, 32),
            child: _card(
              theme,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        height: 132,
                        width: double.infinity,
                        child: GestureDetector(
                            onTap: _viewCover, child: _bannerArt()),
                      ),
                      Positioned(
                          left: 18,
                          bottom: -40,
                          child: _avatarRing(38, dark)),
                    ],
                  ),
                  const SizedBox(height: 50),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                    child: _identity(context,
                        dark: dark,
                        followers: followers,
                        following: following),
                  ),
                  Divider(height: 26, color: theme.dividerColor),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                    child: Column(
                        children: _aboutRows(context,
                            followers: followers, following: following)),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 24, 12),
                child: Row(children: [
                  Text(_isAuthor ? 'Works' : 'Books',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: BookNestColors.cyan.withOpacity(.14),
                    ),
                    child: Text('${_works.length}',
                        style: const TextStyle(
                            color: BookNestColors.cyan,
                            fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
              Expanded(
                child: _works.isEmpty
                    ? _emptyWorks(theme)
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 24, 40),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 460,
                          mainAxisExtent: 132,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: _works.length,
                        itemBuilder: (context, i) =>
                            _WorkCard(book: _works[i]),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Shared pieces ──────────────────────────────────────────────────

  /// Cover photo when there is one, otherwise the per-user navy blend
  /// under the BookNest wordmark pattern.
  Widget _bannerArt() {
    if (_coverUrl != null) {
      return Stack(fit: StackFit.expand, children: [
        DecoratedBox(
            decoration:
                BoxDecoration(gradient: LinearGradient(colors: _bannerColors))),
        _coverImage(),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0x00000000)],
              stops: [0, .55],
            ),
          ),
        ),
      ]);
    }
    return WatermarkOverlay(
      color: Colors.white,
      opacity: 0.08,
      spacing: 148,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ..._bannerColors,
              if (_isAuthor) BookNestColors.cyan.withOpacity(.45),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarRing(double radius, bool dark) {
    final url = _profile?['avatar_url']?.toString();
    return GestureDetector(
      onTap: url == null || !url.startsWith('http')
          ? null
          : () => openChatPhoto(context, url,
              album: [MediaItem(url: url, name: _name)]),
      child: Container(
        padding: const EdgeInsets.all(3.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [BookNestColors.cyan, BookNestColors.navy],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
              color: dark ? BookNestColors.darkChatBackground : Colors.white,
              width: 2),
        ),
        child: BookNestAvatar(imageUrl: url, name: _name, radius: radius),
      ),
    );
  }

  /// Name, badge, handle, stat strip, chips and the action buttons.
  Widget _identity(BuildContext context,
      {required bool dark, required int followers, required int following}) {
    final theme = Theme.of(context);
    final joined = _joined;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(_name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (_isAuthor) _authorBadge,
          ],
        ),
        if (_username.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('@$_username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: BookNestColors.cyan,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 14),
        _card(
          theme,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: IntrinsicHeight(
            child: Row(
              children: [
                _stat('${_works.length}', _isAuthor ? 'Works' : 'Books'),
                VerticalDivider(width: 1, color: theme.dividerColor),
                _stat('$followers', 'Followers',
                    onTap: () => context.push(
                        '/user/${widget.userId}/follows?type=followers')),
                VerticalDivider(width: 1, color: theme.dividerColor),
                _stat('$following', 'Following',
                    onTap: () => context.push(
                        '/user/${widget.userId}/follows?type=following')),
              ],
            ),
          ),
        ),
        if (_gems > 0 || joined != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 0,
            runSpacing: 8,
            children: [
              if (_gems > 0) _redditChip(Icons.diamond_rounded, '$_gems gems'),
              if (joined != null)
                _redditChip(Icons.cake_rounded, 'Joined $joined'),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (!_isMe)
          Row(
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
                  onTap: () => context.push('/chat/peer/${widget.userId}'),
                ),
              ),
            ],
          )
        else
          SizedBox(
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
      ],
    );
  }

  Widget _stat(String value, String label, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 17)),
              ),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: theme.hintColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _aboutRows(BuildContext context,
      {required int followers, required int following}) {
    final joined = _joined;
    return [
      if (joined != null)
        _aboutRow(context, Icons.cake_rounded, 'Joined', joined),
      _aboutRow(context, Icons.person_rounded, 'Member',
          _isAuthor ? 'Author' : 'Reader'),
      _aboutRow(context, Icons.menu_book_rounded, 'Books published',
          '${_works.length}'),
      _aboutRow(context, Icons.favorite_rounded, 'Followers', '$followers'),
      _aboutRow(
          context, Icons.person_search_rounded, 'Following', '$following'),
      if (_gems > 0)
        _aboutRow(context, Icons.diamond_rounded, 'Gems', '$_gems'),
      if (_username.isNotEmpty)
        _aboutRow(
            context, Icons.alternate_email_rounded, 'Handle', '@$_username'),
    ];
  }

  Widget _card(ThemeData theme,
      {required Widget child,
      EdgeInsetsGeometry padding = const EdgeInsets.all(14)}) {
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
      ),
      child: child,
    );
  }

  TabBar _tabBar(ThemeData theme, bool dark) => TabBar(
        indicatorColor: BookNestColors.cyan,
        labelColor: dark ? Colors.white : BookNestColors.navy,
        unselectedLabelColor: theme.hintColor,
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        dividerColor: theme.dividerColor,
        tabs: [Tab(text: _isAuthor ? 'Works' : 'Books'), const Tab(text: 'About')],
      );

  Widget _emptyWorks(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_stories_outlined,
                  size: 42, color: BookNestColors.cyan.withOpacity(.6)),
              const SizedBox(height: 10),
              Text(
                _isMe
                    ? 'Publish a book and it will appear here.'
                    : 'No published books yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.hintColor),
              ),
            ],
          ),
        ),
      );

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

  /// Calls + report/block. On phones the call buttons fold into the ⋮
  /// menu so the banner stays clean; big screens show them as icons.
  List<Widget> _authorActions({required bool compact}) {
    if (_isMe) return const [];
    final iconColor = compact ? Colors.white : null;
    return [
      if (!compact) ...[
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
      PopupMenuButton<String>(
        tooltip: 'More options',
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(Icons.more_vert_rounded, color: iconColor),
        onSelected: (value) async {
          if (value == 'voice') return _call(video: false);
          if (value == 'video') return _call(video: true);
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
            if (mounted) setState(() => _blocked = !_blocked);
          }
        },
        itemBuilder: (context) => [
          if (compact) ...[
            const PopupMenuItem(
              value: 'voice',
              child: Row(children: [
                Icon(Icons.call_outlined, color: BookNestColors.cyan, size: 19),
                SizedBox(width: 10),
                Text('Voice call'),
              ]),
            ),
            const PopupMenuItem(
              value: 'video',
              child: Row(children: [
                Icon(Icons.videocam_outlined,
                    color: BookNestColors.cyan, size: 19),
                SizedBox(width: 10),
                Text('Video call'),
              ]),
            ),
            const PopupMenuDivider(),
          ],
          const PopupMenuItem(
            value: 'report',
            child: Row(children: [
              Icon(Icons.flag_rounded, color: Colors.redAccent, size: 19),
              SizedBox(width: 10),
              Text('Report profile'),
            ]),
          ),
          PopupMenuItem(
            value: 'block',
            child: Row(children: [
              Icon(_blocked ? Icons.lock_open_rounded : Icons.block_rounded,
                  size: 19),
              const SizedBox(width: 10),
              Text(_blocked ? 'Unblock reader' : 'Block reader'),
            ]),
          ),
        ],
      ),
    ];
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

/// Keeps the Works / About tabs pinned under the collapsed banner.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color color;

  _TabsHeader(this.tabBar, this.color);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      ColoredBox(color: color, child: tabBar);

  @override
  bool shouldRebuild(covariant _TabsHeader old) =>
      old.color != color || old.tabBar != tabBar;
}
