import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../core/utils/auth_guard.dart';
import 'book_editor_screen.dart';
import '../../components/booknest_ui.dart';
import '../../../services/backend_api.dart';
import '../../../services/supabase_service.dart';

/// Store-style book landing page. Reading opens the immersive Reader.
class BookDetailsScreen extends StatefulWidget {
  final String bookId;
  const BookDetailsScreen({super.key, required this.bookId});

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  String? _viewerId;
  Map<String, dynamic>? _book;
  Map<String, dynamic>? _progress;
  List<Map<String, dynamic>> _recommended = [];
  bool _loading = true;
  bool _saved = false;
  bool _liked = false;
  List<_Review> _reviews = [];

  @override
  void initState() {
    super.initState();
    _viewerId = SupabaseService().client.auth.currentUser?.id;
    _load();
  }

  Future<void> _load() async {
    // Optimistic analytics: counted once per user per day server-side; a
    // silent no-op until the edge function is deployed.
    unawaited(BackendApi.instance.recordView(widget.bookId));
    try {
      final results = await Future.wait([
        BackendApi.instance.fetchBook(widget.bookId),
        BackendApi.instance.call('books.list', {'limit': 8}),
        BackendApi.instance.call('reader.progress.get', {'bookId': widget.bookId}),
        BackendApi.instance.call('reviews.list', {'bookId': widget.bookId, 'limit': 12}),
      ]);
      if (!mounted) return;
      final bookRes = results[0];
      final rows = ((bookRes?['chapters'] as List?) ?? const []);
      final related = ((results[1]?['books'] as List?) ?? const []);
      setState(() {
        final b = bookRes?['book'];
        _book = b is Map
            ? Map<String, dynamic>.from(b)
            : null;
        final progressData =
            (results[2] as Map<String, dynamic>?)?['progress'];
        _progress = progressData is Map
            ? Map<String, dynamic>.from(progressData)
            : null;
        _reviews = (((results[3] as Map<String, dynamic>?)?['reviews'] as List?) ?? const [])
            .map((row) => _Review.fromRow(Map<String, dynamic>.from(row as Map)))
            .toList();
        if (_book != null && rows.isNotEmpty) {
          _book!['chapters'] = rows;
        }
        _recommended = related
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((b) => b['id'] != widget.bookId)
            .take(5)
            .toList();
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _loadReviews() async {
    final res = await BackendApi.instance
        .call('reviews.list', {'bookId': widget.bookId, 'limit': 12});
    if (!mounted || res == null) return;
    setState(() {
      _reviews = (((res['reviews'] as List?) ?? const []))
          .map((row) => _Review.fromRow(Map<String, dynamic>.from(row as Map)))
          .toList();
    });
  }

  void _notice(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  void _guard(String message, VoidCallback action) => AuthGuard.run(context, () { action(); _notice(message); });

  /// Best-effort display name for reviews (metadata → email prefix → 'Reader').
  String get _viewerName {
    final user = SupabaseService().auth.currentUser;
    final meta = user?.userMetadata;
    final name = (meta?['username'] ?? meta?['display_name'] ?? user?.email?.split('@').first)?.toString();
    return (name == null || name.trim().isEmpty) ? 'Reader' : name.trim();
  }

  /// Optimistic UI per the backend blueprint: flip the icon instantly, then
  /// fire-and-forget persistence. Persistence is a silent no-op (session-only
  /// behaviour) until the booknest-api edge function is deployed.
  void _toggleSave() {
    setState(() => _saved = !_saved);
    unawaited(BackendApi.instance.setBookmark(widget.bookId, _saved));
  }

  void _toggleLike() {
    setState(() => _liked = !_liked);
    unawaited(BackendApi.instance.setLike(widget.bookId, _liked));
  }

  void _share() {
    AuthGuard.run(context, () {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => BookShareSheet(
          bookId: widget.bookId,
          bookTitle: _book?['title']?.toString() ?? 'this book',
          onSelected: (name, delivered) => _notice(delivered ? 'Book profile sent to $name.' : 'Book profile shared with $name.'),
        ),
      );
    });
  }

  void _showMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.flag_rounded, color: BookNestColors.cyan),
            title: const Text('Report this book'),
            subtitle: Text('Tell the moderators something is wrong', style: TextStyle(color: Theme.of(sheetContext).hintColor)),
            onTap: () { Navigator.pop(sheetContext); _reportBook(); },
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded, color: BookNestColors.cyan),
            title: const Text('Copy book link'),
            subtitle: Text('BookNest · book/${widget.bookId}', style: TextStyle(color: Theme.of(sheetContext).hintColor)),
            onTap: () => Navigator.pop(sheetContext),
          ),
        ]),
      ),
    );
  }

  void _reportBook() {
    AuthGuard.run(context, () {
      const reasons = ['Spam or scam', 'Hate or harassment', 'Copyright issue', 'Wrong category', 'Something else'];
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text('Why are you reporting this book?', style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            ...reasons.map((reason) => ListTile(
              leading: const Icon(Icons.flag_outlined, color: BookNestColors.cyan),
              title: Text(reason),
              onTap: () {
                Navigator.pop(sheetContext);
                BackendApi.instance.reportContent(targetType: 'book', targetId: widget.bookId, reason: reason);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report sent to the moderators. Thank you.')));
              },
            )),
            const SizedBox(height: 8),
          ]),
        ),
      );
    });
  }

  void _writeReview() {
    AuthGuard.run(context, () {
      final controller = TextEditingController();
      var rating = 5;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Write a review', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Row(children: List.generate(5, (index) => IconButton(onPressed: () => setSheetState(() => rating = index + 1), icon: Icon(index < rating ? Icons.star_rounded : Icons.star_outline_rounded, color: BookNestColors.cyan)))),
              TextField(controller: controller, autofocus: true, minLines: 3, maxLines: 6, decoration: const InputDecoration(hintText: 'Tell readers what you think…')),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { final text = controller.text.trim(); if (text.isEmpty) return; Navigator.pop(sheetContext); unawaited(BackendApi.instance.createReview(widget.bookId, rating, text, displayName: _viewerName).then((_) => _loadReviews())); _notice('Your review has been posted.'); }, child: const Text('Post review'))),
            ]),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: BookNestColors.cyan)));
    if (_book == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This book is no longer available.')));
    final book = _book!;
    final title = book['title']?.toString() ?? 'Untitled';
    final author = book['author']?.toString() ?? 'Unknown author';
    final description = book['description']?.toString() ?? 'No description has been added yet.';
    final dark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    final muted = dark ? BookNestColors.darkTextSecondary : BookNestColors.lightTextSecondary;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true, expandedHeight: 100, leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: context.pop),
            actions: [
              IconButton(icon: const Icon(Icons.ios_share_outlined), onPressed: _share),
              IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: _showMoreMenu),
            ],
            flexibleSpace: FlexibleSpaceBar(background: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [BookNestColors.navyDeep, BookNestColors.navy.withOpacity(.65), surface], begin: Alignment.topLeft, end: Alignment.bottomRight)))),
          ),
          if (book['banner_url'] is String &&
              (book['banner_url'] as String).startsWith('http'))
            SliverToBoxAdapter(
              child: Image.network(
                book['banner_url'] as String,
                width: double.infinity,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Hero(tag: 'book-${widget.bookId}', child: _Cover(title: title, coverUrl: book['cover_url']?.toString())), const SizedBox(width: 18),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 6),
                  GestureDetector(
                    onTap: (book['added_by']?.toString().isNotEmpty == true)
                        ? () => context.push('/user/${book['added_by']}')
                        : null,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(author, style: TextStyle(color: BookNestColors.cyan, fontWeight: FontWeight.w600)),
                      if (book['added_by']?.toString().isNotEmpty == true) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded, size: 15, color: BookNestColors.cyan),
                      ],
                    ]),
                  ), const SizedBox(height: 14),
                  Row(children: [
                    Icon(
                      book['average_rating'] is num &&
                              (book['average_rating'] as num) > 0
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: BookNestColors.cyan,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      book['average_rating'] is num &&
                              (book['average_rating'] as num) > 0
                          ? (book['average_rating'] as num).toStringAsFixed(1)
                          : 'New',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      book['review_count'] is num && (book['review_count'] as num) > 0
                          ? '  •  ${(book['review_count'] as num).toInt()} ratings'
                          : '  •  No ratings yet',
                      style: TextStyle(color: muted),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  _LineageBadges(book: book),
                  const SizedBox(height: 12), Text('Ebook • Markdown', style: TextStyle(color: muted)),
                ])),
              ]),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: ElevatedButton.icon(onPressed: () => AuthGuard.run(context, () => context.push('/reader?bookId=${widget.bookId}')), icon: Icon(_progress != null ? Icons.auto_stories_rounded : Icons.menu_book_rounded), label: Text(_progress != null ? 'Continue · Unit ${(_progress!['chapterNumber'] as num?)?.toInt() ?? 1}' : 'Read now'))),
                const SizedBox(width: 10),
                _RoundAction(icon: _saved ? Icons.bookmark : Icons.bookmark_border, selected: _saved, label: 'Save', onTap: () => _guard(_saved ? 'Removed from saved books.' : 'Saved to your library.', _toggleSave)),
                _RoundAction(icon: _liked ? Icons.favorite : Icons.favorite_border, selected: _liked, label: 'Like', onTap: () => _guard(_liked ? 'Like removed.' : 'You liked this book.', _toggleLike)),
              ]),
              const SizedBox(height: 12),
              if (book['added_by']?.toString().isNotEmpty == true &&
                  book['added_by'].toString() == _viewerId)
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final edited = await context.push<bool>(
                            '/editor/book/${widget.bookId}');
                        if (edited == true && mounted) _load();
                      },
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Edit book'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _BoostButton(book: book, onBoosted: _load)),
                ])
              else
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _startRemix(context, 'remix'),
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                      label: const Text('Write a remix'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _startRemix(context, 'sequel'),
                      icon: const Icon(Icons.queue_rounded, size: 18),
                      label: const Text('Write a sequel'),
                    ),
                  ),
                ]),
              const SizedBox(height: 28), _Heading('About this book'), const SizedBox(height: 10), Text(description, style: theme.textTheme.bodyLarge?.copyWith(height: 1.55, color: muted)),
              const SizedBox(height: 28), _Heading('Ratings and reviews'), const SizedBox(height: 14),
              _Reviews(
                reviews: _reviews,
                ratingText: book['average_rating'] is num && (book['average_rating'] as num) > 0 ? (book['average_rating'] as num).toStringAsFixed(1) : '—',
                    ratingsNote: book['review_count'] is num &&
                            (book['review_count'] as num) > 0
                        ? '${(book['review_count'] as num).toInt()} community ratings'
                        : 'Not rated yet',
                onReview: _writeReview,
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => context.push('/book/${widget.bookId}/reviews'), icon: const Icon(Icons.star_rounded, size: 17), label: const Text('All reviews'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(onPressed: () => context.push('/book/${widget.bookId}/discussion'), icon: const Icon(Icons.forum_rounded, size: 17), label: const Text('Discussion'))),
              ]),
              const SizedBox(height: 28), _Heading('Recommended for you'), const SizedBox(height: 12),
              SizedBox(height: 184, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _recommended.length, separatorBuilder: (_, __) => const SizedBox(width: 12), itemBuilder: (_, i) { final item = _recommended[i]; return InkWell(borderRadius: BorderRadius.circular(16), onTap: () => context.push('/book/${item['id']}'), child: SizedBox(width: 112, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_Cover(title: item['title']?.toString() ?? 'Book', coverUrl: item['cover_url']?.toString(), small: true), const SizedBox(height: 7), Text(item['title']?.toString() ?? 'Untitled', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))]))); })),
            ]),
          )),
        ],
      ),
    );
  }
  /// Remix or sequel: the new draft carries every chapter and marks.
  Future<void> _startRemix(BuildContext context, String mode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(mode == 'remix'
            ? 'Write a remix of this book?'
            : 'Write the next part?'),
        content: Text(mode == 'remix'
            ? 'A remix starts from this book\'s every chapter — your own '
                'words take it somewhere new. The remix mark travels with it '
                'and the original author keeps full credit.'
            : 'A sequel continues this story as its next part — every '
                'chapter comes with you, and the series line stays unbroken. '
                'The original author keeps full credit.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Start writing',
                  style: TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: BookNestLoader(size: 64)),
    );
    final res = await BackendApi.instance
        .call('books.remix', {'bookId': widget.bookId, 'mode': mode});
    if (!mounted) return;
    Navigator.of(context).pop(); // loader
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not start — this book may be a draft, or you are its '
              'author. Open it in the studio instead.')));
      return;
    }
    final newId = res['id']?.toString() ?? '';
    final carried = (res['carriedChapters'] as num?)?.toInt() ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(mode == 'remix'
            ? 'Remix draft created — $carried chapters carried. You earned 10 gems!'
            : 'Sequel draft created — $carried chapters carried. You earned 10 gems!')));
    if (newId.isNotEmpty && mounted) {
      final book = await BackendApi.instance.fetchBook(newId);
      final b = book?['book'];
      if (b is Map && mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (routeContext) => BookEditorScreen.edit(
              book: Map<String, dynamic>.from(b)),
        ));
      }
    }
    if (mounted) _load();
  }

}

class _Cover extends StatelessWidget { final String title; final String? coverUrl; final bool small; const _Cover({required this.title, this.coverUrl, this.small = false});
  @override
  Widget build(BuildContext context) {
    final url = coverUrl;
    final box = Container(width: small ? 112 : 118, height: small ? 140 : 164, decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), gradient: const LinearGradient(colors: [BookNestColors.navy, BookNestColors.navyDeep], begin: Alignment.topLeft, end: Alignment.bottomRight), boxShadow: [BoxShadow(color: BookNestColors.cyan.withOpacity(.18), blurRadius: 18, offset: const Offset(0, 8))]));
    if (url != null && url.startsWith('http')) {
      return ClipRRect(borderRadius: BorderRadius.circular(15), child: SizedBox(width: small ? 112 : 118, height: small ? 140 : 164, child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => box)));
    }
    return Container(width: small ? 112 : 118, height: small ? 140 : 164, decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), gradient: const LinearGradient(colors: [BookNestColors.navy, BookNestColors.navyDeep], begin: Alignment.topLeft, end: Alignment.bottomRight), boxShadow: [BoxShadow(color: BookNestColors.cyan.withOpacity(.18), blurRadius: 18, offset: const Offset(0, 8))]), child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.auto_stories_rounded, color: BookNestColors.cyan), const Spacer(), Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: small ? 12 : 14))])));
  }
}
class _Heading extends StatelessWidget { final String text; const _Heading(this.text); @override Widget build(BuildContext context) => Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)); }
class _RoundAction extends StatelessWidget { final IconData icon; final bool selected; final String label; final VoidCallback onTap; const _RoundAction({required this.icon, required this.selected, required this.label, required this.onTap}); @override Widget build(BuildContext context) => Column(children: [IconButton.filledTonal(onPressed: onTap, icon: Icon(icon, color: selected ? BookNestColors.cyan : null)), Text(label, style: Theme.of(context).textTheme.labelSmall)]); }
class _Reviews extends StatelessWidget {
  final List<_Review> reviews;
  final String ratingText;
  final String ratingsNote;
  final VoidCallback onReview;
  const _Reviews({
    required this.reviews,
    required this.ratingText,
    required this.ratingsNote,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filled = double.tryParse(ratingText)?.round() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(ratingText,
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < filled
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: BookNestColors.cyan,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(ratingsNote,
                      style: TextStyle(color: theme.hintColor)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onReview,
          icon: const Icon(Icons.rate_review_outlined),
          label: const Text('Write a review'),
        ),
        const SizedBox(height: 12),
        if (reviews.isEmpty)
          Text(
            'Be the first to share what you thought of this book.',
            style: TextStyle(color: theme.hintColor),
          )
        else
          ...reviews.map(
            (review) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(review.initials)),
              title: Row(
                children: [
                  Expanded(
                    child: Text(review.name,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  ...List.generate(
                    review.rating,
                    (_) => const Icon(Icons.star_rounded,
                        color: BookNestColors.cyan, size: 14),
                  ),
                ],
              ),
              subtitle: Text(
                review.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}
class _Review { final String name; final String initials; final String text; final int rating; const _Review({required this.name, required this.initials, required this.text, required this.rating});
  factory _Review.fromRow(Map<String, dynamic> row) {
    final name = row['userName']?.toString() ?? 'Reader';
    final initials = name.trim().isEmpty
        ? 'R'
        : name.trim().split(RegExp(r'\s+')).map((w) => w.characters.first.toUpperCase()).take(2).join();
    return _Review(
      name: name,
      initials: initials,
      text: row['body']?.toString() ?? '',
      rating: (row['rating'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Contact picker for sending a book card inside BookNest. It intentionally does
/// not use the operating system share sheet: the selected recipient is from the
/// app's own profiles directory. Reused by the reader screen too.
class BookShareSheet extends StatefulWidget {
  final String bookId;
  final String bookTitle;

  /// Optional custom handler; when omitted the sheet confirms with a snackbar.
  final void Function(String name, bool delivered)? onSelected;

  const BookShareSheet({
    super.key,
    required this.bookId,
    required this.bookTitle,
    this.onSelected,
  });

  @override
  State<BookShareSheet> createState() => _BookShareSheetState();
}

class _BookShareSheetState extends State<BookShareSheet> {
  final _search = TextEditingController();
  late final Future<List<Map<String, dynamic>>> _contacts;

  @override
  void initState() {
    super.initState();
    _contacts = SupabaseService().client
        .from('profiles')
        .select('id, username, display_name')
        .limit(60)
        .then((rows) => (rows as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList());
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = dark ? BookNestColors.darkChatBackground : Colors.white;
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: MediaQuery.sizeOf(context).height * .72,
            decoration: BoxDecoration(
              color: background.withOpacity(.94),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              border: Border.all(color: BookNestColors.cyan.withOpacity(.22)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(children: [
              Container(width: 38, height: 4, decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(8))),
              const SizedBox(height: 18),
              Row(children: [
                Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle, color: BookNestColors.cyan.withOpacity(.14)), child: const Icon(Icons.send_rounded, color: BookNestColors.cyan)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Send book to', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text(widget.bookTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: BookNestColors.cyan)),
                ])),
              ]),
              const SizedBox(height: 18),
              TextField(controller: _search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search your BookNest contacts')),
              const SizedBox(height: 14),
              Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _contacts,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator(color: BookNestColors.cyan));
                  if (snapshot.hasError) return const Center(child: Text('Your contacts could not be loaded.'));
                  final term = _search.text.trim().toLowerCase();
                  final contacts = (snapshot.data ?? []).where((person) => '${person['display_name'] ?? ''} ${person['username'] ?? ''}'.toLowerCase().contains(term)).toList();
                  if (contacts.isEmpty) return const Center(child: Text('No BookNest contacts found.'));
                  return ListView.separated(itemCount: contacts.length, separatorBuilder: (_, __) => const SizedBox(height: 4), itemBuilder: (_, index) {
                    final person = contacts[index];
                    final name = person['display_name']?.toString().trim().isNotEmpty == true ? person['display_name'].toString() : (person['username']?.toString() ?? 'BookNest reader');
                    final initial = name.characters.first.toUpperCase();
                    return ListTile(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), leading: CircleAvatar(backgroundColor: BookNestColors.navy, child: Text(initial, style: const TextStyle(color: Colors.white))), title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: person['username'] == null ? null : Text('@${person['username']}'), trailing: const Icon(Icons.send_outlined, color: BookNestColors.cyan), onTap: () async { final messenger = ScaffoldMessenger.maybeOf(context); final delivered = await BackendApi.instance.shareBook(bookId: widget.bookId, bookTitle: widget.bookTitle, peerId: person['id']?.toString() ?? '') != null; if (!context.mounted) return; Navigator.pop(context); if (widget.onSelected != null) { widget.onSelected!(name, delivered); } else { messenger?.showSnackBar(SnackBar(content: Text(delivered ? 'Book profile sent to $name.' : 'Book profile shared with $name.'))); } });
                  });
                },
              )),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Lineage marks: part number, sequel, remix and the boost flame.
class _LineageBadges extends StatelessWidget {
  final Map<dynamic, dynamic> book;
  const _LineageBadges({required this.book});

  @override
  Widget build(BuildContext context) {
    final part = (book['part_number'] as num?)?.toInt() ?? 1;
    final isRemix = book['is_remix'] == true;
    final isSequel = book['sequel_of'] != null;
    final boosted = book['boosted_until'] != null &&
        DateTime.tryParse(book['boosted_until'].toString()) != null &&
        DateTime.parse(book['boosted_until'].toString())
            .isAfter(DateTime.now());
    if (part <= 1 && !isRemix && !isSequel && !boosted) {
      return const SizedBox.shrink();
    }
    final chips = <Widget>[
      if (boosted)
        _Badge(
          icon: Icons.local_fire_department_rounded,
          label: 'Boosted',
          color: BookNestColors.cyan,
        ),
      if (part > 1)
        _Badge(
          icon: Icons.queue_rounded,
          label: 'Part $part',
          color: BookNestColors.navy,
        ),
      if (isSequel && part <= 1)
        const _Badge(
          icon: Icons.auto_stories_rounded,
          label: 'Sequel',
          color: BookNestColors.navy,
        ),
      if (isRemix)
        const _Badge(
          icon: Icons.auto_fix_high_rounded,
          label: 'Remix',
          color: BookNestColors.navy,
        ),
    ];
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withOpacity(.1),
        border: Border.all(color: color.withOpacity(.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }
}

/// Author-only boost: 20 gems put the book at the top of Discover for
/// three days.
class _BoostButton extends StatefulWidget {
  final Map<dynamic, dynamic> book;
  final VoidCallback onBoosted;
  const _BoostButton({required this.book, required this.onBoosted});
  @override
  State<_BoostButton> createState() => _BoostButtonState();
}

class _BoostButtonState extends State<_BoostButton> {
  bool _busy = false;

  Future<void> _boost() async {
    if (_busy) return;
    final until = widget.book['boosted_until']?.toString();
    final active = until != null &&
        DateTime.tryParse(until) != null &&
        DateTime.parse(until).isAfter(DateTime.now());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(active ? 'Extend the boost?' : 'Boost this book?'),
        content: const Text(
            '20 gems put this book at the top of Discover for three days. '
            'Claim your daily gems from the wallet if you are short.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Boost · 20 gems',
                  style: TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final res = await BackendApi.instance
        .call('gems.spend', {'kind': 'boost_book', 'bookId': widget.book['id']?.toString() ?? ''});
    if (!mounted) return;
    setState(() => _busy = false);
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'You need 20 gems to boost — claim your daily gems first.')));
      return;
    }
    final left = (res['gemsLeft'] as num?)?.toInt();
    widget.onBoosted();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(active
            ? 'Boost extended!${left != null ? ' $left gems left.' : ''}'
            : 'Boosted — this book leads Discover for three days!${left != null ? ' $left gems left.' : ''}')));
  }

  @override
  Widget build(BuildContext context) {
    final until = widget.book['boosted_until']?.toString();
    final active = until != null &&
        DateTime.tryParse(until) != null &&
        DateTime.parse(until).isAfter(DateTime.now());
    return OutlinedButton.icon(
      onPressed: _busy ? null : _boost,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: BookNestColors.cyan))
          : Icon(
              active
                  ? Icons.local_fire_department_rounded
                  : Icons.rocket_launch_outlined,
              size: 18,
              color: active ? BookNestColors.cyan : null),
      label: Text(active ? 'Boosted · extend' : 'Boost · 20 gems'),
    );
  }
}
