import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../core/utils/auth_guard.dart';
import '../../../services/genre_service.dart';
import '../../../state/book_providers.dart';
import '../../components/booknest_ui.dart' show BookNestLoader, TagChip, kBookNestGenres;
import '../../components/skeleton_kit.dart';

class BooksLibraryScreen extends ConsumerStatefulWidget {
  const BooksLibraryScreen({super.key});

  @override
  ConsumerState<BooksLibraryScreen> createState() =>
      _BooksLibraryScreenState();
}

/// The face of the shelf: search and genre chips are presentation state;
/// the books themselves come from the shared catalog provider.
class _BooksLibraryScreenState extends ConsumerState<BooksLibraryScreen> {

  final TextEditingController _search = TextEditingController();
  final Set<String> _selectedGenres = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    GenreService.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> books) {
    final query = _search.text.trim().toLowerCase();
    return books.where((book) {
      final haystack =
          '${book['title']} ${book['author']} ${book['description']}'
              .toLowerCase();
      final matches = query.isEmpty || haystack.contains(query);
      final genre = book['genre']?.toString();
      return matches &&
          (_selectedGenres.isEmpty || _selectedGenres.contains(genre));
    }).toList();
  }

  Future<void> _showFilters() async {
    final next = Set<String>.from(_selectedGenres);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => DraggableScrollableSheet(
          initialChildSize: .72,
          minChildSize: .45,
          maxChildSize: .92,
          expand: false,
          builder: (_, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Row(
                  children: [
                    Text(
                      'Filter books',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setSheetState(next.clear),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: GenreService.instance.bookGenres.length,
                  itemBuilder: (_, index) {
                    final genre = GenreService.instance.bookGenres[index];
                    return CheckboxListTile(
                      value: next.contains(genre),
                      activeColor: BookNestColors.cyan,
                      title: Text(genre),
                      onChanged: (checked) => setSheetState(() {
                        checked == true ? next.add(genre) : next.remove(genre);
                      }),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _selectedGenres
                          ..clear()
                          ..addAll(next);
                      });
                      Navigator.pop(sheetContext);
                    },
                    child: Text(next.isEmpty
                        ? 'Show books'
                        : 'Show books (${next.length} genres)'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    // The shelf lives outside the UI — this widget only paints it.
    final catalog = ref.watch(booksCatalogProvider);
    final bool _loading = catalog.loading;
    final List<Map<String, dynamic>> _books = catalog.books;
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark
        ? BookNestColors.darkTextSecondary
        : BookNestColors.lightTextSecondary;

    return Scaffold(
      // Lifted above the navigation bar so it is never covered.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 68),
        child: FloatingActionButton.extended(
        backgroundColor: BookNestColors.navy,
        foregroundColor: Colors.white,
        onPressed: () =>
            AuthGuard.run(context, () => context.push('/editor')),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Write'),
      ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Discover books',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text('Find your next unforgettable read',
                      style: TextStyle(color: muted)),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search titles, authors, or topics',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Badge(
                        isLabelVisible: _selectedGenres.isNotEmpty,
                        label: Text('${_selectedGenres.length}'),
                        child: IconButton.filledTonal(
                          onPressed: _showFilters,
                          icon: const Icon(Icons.tune_rounded),
                          tooltip: 'Filter books',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // The live genre shelves — tap to browse one.
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: GenreService.instance.bookGenres.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) => TagChip(
                        label: GenreService.instance.bookGenres[index],
                        onTap: () => context.push('/genre?name='
                            '${Uri.encodeComponent(GenreService.instance.bookGenres[index])}'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const BookShelfSkeleton()
                  : RefreshIndicator(
                      color: BookNestColors.cyan,
                      onRefresh: () => ref
                          .read(booksCatalogProvider.notifier)
                          .refresh(),
                      child: Builder(builder: (context) {
                        final books = _filter(_books);
                        if (books.isEmpty) {
                          // A truly empty shelf gets the arrival card —
                          // an empty-looking library must never look broken.
                          if (_books.isEmpty) {
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(28, 60, 28, 40),
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(18),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: BookNestColors.cyan
                                              .withOpacity(.12),
                                          border: Border.all(
                                              color: BookNestColors.cyan
                                                  .withOpacity(.4)),
                                        ),
                                        child: const Icon(
                                            Icons.history_edu_rounded,
                                            color: BookNestColors.cyan,
                                            size: 34),
                                      ),
                                      const SizedBox(height: 18),
                                      const Text('The ink is still drying…',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 17)),
                                      const SizedBox(height: 8),
                                      Text(
                                        'The first wave of stories is being '
                                        'inked and shipped to this shelf. It '
                                        'will not stay empty for long.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: muted,
                                            fontSize: 13.5,
                                            height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(40),
                                child: Center(
                                  child: Text('No books match your search.',
                                      style: TextStyle(color: muted)),
                                ),
                              ),
                            ],
                          );
                        }
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: ListView.builder(
                            key: ValueKey(
                                '${books.length}-${_search.text}-${_selectedGenres.length}'),
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
                            itemCount: books.length,
                            itemBuilder: (_, index) =>
                                _BookTile(book: books[index]),
                          ),
                        );
                      }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  final Map<String, dynamic> book;

  const _BookTile({required this.book});

  @override
  Widget build(BuildContext context) {
    final id = book['id']?.toString() ?? '';
    final title = book['title']?.toString() ?? 'Untitled';
    final author = book['author']?.toString() ?? 'Unknown author';
    final description = book['description']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Theme.of(context).colorScheme.surface.withOpacity(.72),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
                color: BookNestColors.cyan.withOpacity(.16))),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/book/$id'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Hero(
                  tag: 'book-$id',
                  child: Container(
                    width: 64,
                    height: 86,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [BookNestColors.navy, BookNestColors.navyDeep],
                      ),
                    ),
                    child: const Icon(
                      Icons.auto_stories_rounded,
                      color: BookNestColors.cyan,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(author,
                          style: const TextStyle(color: BookNestColors.cyan)),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).hintColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
