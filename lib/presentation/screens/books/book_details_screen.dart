import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../core/utils/auth_guard.dart';
import '../../../services/supabase_service.dart';

/// Store-style book landing page. Reading remains a separate, distraction-free route.
class BookDetailsScreen extends StatefulWidget {
  final String bookId;
  const BookDetailsScreen({super.key, required this.bookId});

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  Map<String, dynamic>? _book;
  List<Map<String, dynamic>> _recommended = [];
  bool _loading = true;
  bool _saved = false;
  bool _liked = false;
  final List<_Review> _reviews = [
    const _Review(name: 'Amina M.', initials: 'AM', text: 'A beautifully written read — I could not put it down.', rating: 5),
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final client = SupabaseService().client;
      final results = await Future.wait([
        client.from('club_books').select().eq('id', widget.bookId).maybeSingle(),
        client.from('club_books').select().eq('moderation_status', 'approved').limit(8),
      ]);
      if (!mounted) return;
      final rows = results[1] as List;
      setState(() {
        _book = results[0] == null ? null : Map<String, dynamic>.from(results[0] as Map);
        _recommended = rows.map((e) => Map<String, dynamic>.from(e as Map)).where((b) => b['id'] != widget.bookId).take(5).toList();
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _notice(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  void _guard(String message, VoidCallback action) => AuthGuard.run(context, () { action(); _notice(message); });

  void _share() {
    AuthGuard.run(context, () {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ShareBookSheet(
          bookTitle: _book?['title']?.toString() ?? 'this book',
          onSelected: (name) => _notice('Book profile shared with $name.'),
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
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { final text = controller.text.trim(); if (text.isEmpty) return; setState(() => _reviews.insert(0, _Review(name: 'You', initials: 'YO', text: text, rating: rating))); Navigator.pop(sheetContext); _notice('Your review has been posted for this session.'); }, child: const Text('Post review'))),
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
            actions: [IconButton(icon: const Icon(Icons.ios_share_outlined), onPressed: _share)],
            flexibleSpace: FlexibleSpaceBar(background: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [BookNestColors.navyDeep, BookNestColors.navy.withOpacity(.65), surface], begin: Alignment.topLeft, end: Alignment.bottomRight)))),
          ),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Hero(tag: 'book-${widget.bookId}', child: _Cover(title: title)), const SizedBox(width: 18),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 6),
                  Text(author, style: TextStyle(color: BookNestColors.cyan, fontWeight: FontWeight.w600)), const SizedBox(height: 14),
                  Row(children: [const Icon(Icons.star_rounded, color: BookNestColors.cyan, size: 20), const SizedBox(width: 4), Text('4.8', style: theme.textTheme.titleMedium), Text('  •  128 ratings', style: TextStyle(color: muted))]),
                  const SizedBox(height: 12), Text('Ebook • Markdown', style: TextStyle(color: muted)),
                ])),
              ]),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: ElevatedButton.icon(onPressed: () => AuthGuard.run(context, () => context.push('/publish-details?bookId=${widget.bookId}')), icon: const Icon(Icons.menu_book_rounded), label: const Text('Read now'))),
                const SizedBox(width: 10),
                _RoundAction(icon: _saved ? Icons.bookmark : Icons.bookmark_border, selected: _saved, label: 'Save', onTap: () => _guard(_saved ? 'Removed from saved books.' : 'Saved to your library.', () => setState(() => _saved = !_saved))),
                _RoundAction(icon: _liked ? Icons.favorite : Icons.favorite_border, selected: _liked, label: 'Like', onTap: () => _guard(_liked ? 'Like removed.' : 'You liked this book.', () => setState(() => _liked = !_liked))),
              ]),
              const SizedBox(height: 28), _Heading('About this book'), const SizedBox(height: 10), Text(description, style: theme.textTheme.bodyLarge?.copyWith(height: 1.55, color: muted)),
              const SizedBox(height: 28), _Heading('Ratings and reviews'), const SizedBox(height: 14),
              _Reviews(reviews: _reviews, onReview: _writeReview),
              const SizedBox(height: 28), _Heading('Recommended for you'), const SizedBox(height: 12),
              SizedBox(height: 184, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _recommended.length, separatorBuilder: (_, __) => const SizedBox(width: 12), itemBuilder: (_, i) { final item = _recommended[i]; return InkWell(borderRadius: BorderRadius.circular(16), onTap: () => context.push('/book/${item['id']}'), child: SizedBox(width: 112, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_Cover(title: item['title']?.toString() ?? 'Book', small: true), const SizedBox(height: 7), Text(item['title']?.toString() ?? 'Untitled', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))]))); })),
            ]),
          )),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget { final String title; final bool small; const _Cover({required this.title, this.small = false}); @override Widget build(BuildContext context) => Container(width: small ? 112 : 118, height: small ? 140 : 164, decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), gradient: const LinearGradient(colors: [BookNestColors.navy, BookNestColors.navyDeep], begin: Alignment.topLeft, end: Alignment.bottomRight), boxShadow: [BoxShadow(color: BookNestColors.cyan.withOpacity(.18), blurRadius: 18, offset: const Offset(0, 8))]), child: Padding(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.auto_stories_rounded, color: BookNestColors.cyan), const Spacer(), Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: small ? 12 : 14))]))); }
class _Heading extends StatelessWidget { final String text; const _Heading(this.text); @override Widget build(BuildContext context) => Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)); }
class _RoundAction extends StatelessWidget { final IconData icon; final bool selected; final String label; final VoidCallback onTap; const _RoundAction({required this.icon, required this.selected, required this.label, required this.onTap}); @override Widget build(BuildContext context) => Column(children: [IconButton.filledTonal(onPressed: onTap, icon: Icon(icon, color: selected ? BookNestColors.cyan : null)), Text(label, style: Theme.of(context).textTheme.labelSmall)]); }
class _Reviews extends StatelessWidget { final List<_Review> reviews; final VoidCallback onReview; const _Reviews({required this.reviews, required this.onReview}); @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text('4.8', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Row(children: [Icon(Icons.star_rounded, color: BookNestColors.cyan), Icon(Icons.star_rounded, color: BookNestColors.cyan), Icon(Icons.star_rounded, color: BookNestColors.cyan), Icon(Icons.star_rounded, color: BookNestColors.cyan), Icon(Icons.star_half_rounded, color: BookNestColors.cyan)]), Text('128 community ratings', style: TextStyle(color: Theme.of(context).hintColor))])]), const SizedBox(height: 16), OutlinedButton.icon(onPressed: onReview, icon: const Icon(Icons.rate_review_outlined), label: const Text('Write a review')), const SizedBox(height: 12), ...reviews.map((review) => ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(child: Text(review.initials)), title: Row(children: [Text(review.name), const SizedBox(width: 6), ...List.generate(review.rating, (_) => const Icon(Icons.star_rounded, color: BookNestColors.cyan, size: 14))]), subtitle: Text(review.text, maxLines: 3, overflow: TextOverflow.ellipsis), trailing: const Icon(Icons.more_vert))), ]); }
class _Review { final String name; final String initials; final String text; final int rating; const _Review({required this.name, required this.initials, required this.text, required this.rating}); }

/// Contact picker for sending a book card inside BookNest. It intentionally does
/// not use the operating system share sheet: the selected recipient is from the
/// app's own profiles directory.
class _ShareBookSheet extends StatefulWidget {
  final String bookTitle;
  final ValueChanged<String> onSelected;
  const _ShareBookSheet({required this.bookTitle, required this.onSelected});

  @override
  State<_ShareBookSheet> createState() => _ShareBookSheetState();
}

class _ShareBookSheetState extends State<_ShareBookSheet> {
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
                    return ListTile(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), leading: CircleAvatar(backgroundColor: BookNestColors.navy, child: Text(initial, style: const TextStyle(color: Colors.white))), title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: person['username'] == null ? null : Text('@${person['username']}'), trailing: const Icon(Icons.send_outlined, color: BookNestColors.cyan), onTap: () { Navigator.pop(context); widget.onSelected(name); });
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
