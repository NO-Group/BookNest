import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backend_api.dart';
import '../services/book_repository.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Book state, outside the UI — the same split the chat engine got.
/// Screens watch these providers; the repository does the talking.
/// ─────────────────────────────────────────────────────────────────────────────

class BooksCatalogState {
  final bool loading;
  final List<Map<String, dynamic>> books;

  const BooksCatalogState({
    this.loading = true,
    this.books = const [],
  });

  BooksCatalogState copyWith({bool? loading, List<Map<String, dynamic>>? books}) {
    return BooksCatalogState(
      loading: loading ?? this.loading,
      books: books ?? this.books,
    );
  }
}

/// The public shelf — any surface (library, home rail, a future widget)
/// watches the exact same list.
class BooksCatalogController
    extends AutoDisposeNotifier<BooksCatalogState> {
  @override
  BooksCatalogState build() {
    Future.microtask(() => refresh());
    // A background refresh brought a changed shelf — repaint from cache.
    final sub = BackendApi.instance.cacheUpdates
        .where((action) => action == 'books.list')
        .listen((_) => refresh());
    ref.onDispose(sub.cancel);
    return const BooksCatalogState();
  }

  Future<void> refresh() async {
    final books = await BookRepository.instance.list(limit: 50);
    state = state.copyWith(loading: false, books: books);
  }
}

final booksCatalogProvider = NotifierProvider.autoDispose<
        BooksCatalogController, BooksCatalogState>(
    BooksCatalogController.new);

/// One detail page's full payload: the book (+chapters), progress,
/// reviews and recommendations — loaded once, refreshable by anything.
class BookDetailState {
  final bool loading;
  final Map<String, dynamic>? book;
  final List<Map<String, dynamic>> chapters;
  final Map<String, dynamic>? progress;
  final List<Map<String, dynamic>> reviews;
  final List<Map<String, dynamic>> recommended;

  const BookDetailState({
    this.loading = true,
    this.book,
    this.chapters = const [],
    this.progress,
    this.reviews = const [],
    this.recommended = const [],
  });

  BookDetailState copyWith({
    bool? loading,
    Map<String, dynamic>? book,
    bool clearBook = false,
    List<Map<String, dynamic>>? chapters,
    Map<String, dynamic>? progress,
    bool clearProgress = false,
    List<Map<String, dynamic>>? reviews,
    List<Map<String, dynamic>>? recommended,
  }) {
    return BookDetailState(
      loading: loading ?? this.loading,
      book: clearBook ? null : (book ?? this.book),
      chapters: chapters ?? this.chapters,
      progress: clearProgress ? null : (progress ?? this.progress),
      reviews: reviews ?? this.reviews,
      recommended: recommended ?? this.recommended,
    );
  }
}

class BookDetailController
    extends AutoDisposeFamilyNotifier<BookDetailState, String> {
  @override
  BookDetailState build(String arg) {
    Future.microtask(() => refresh());
    return const BookDetailState();
  }

  String get _bookId => arg;

  Future<void> refresh() async {
    // Optimistic analytics: counted once per user per day server-side.
    BookRepository.instance.recordView(_bookId);
    final results = await Future.wait([
      BookRepository.instance.get(_bookId),
      BookRepository.instance.list(limit: 8),
      BookRepository.instance.readingProgress(_bookId),
      BookRepository.instance.reviews(_bookId),
    ]);
    final loaded = results[0] as BookWithChapters?;
    final related = results[1] as List<Map<String, dynamic>>;
    final progressData = results[2] as Map<String, dynamic>?;
    final reviews = results[3] as List<Map<String, dynamic>>;
    // The screen reads book['chapters'] — keep that shape.
    final bookMap = loaded?.book;
    if (bookMap != null) bookMap['chapters'] = loaded!.chapters;
    state = BookDetailState(
      loading: false,
      book: bookMap,
      chapters: loaded?.chapters ?? const [],
      progress: (progressData?['progress'] as Map?) == null
          ? null
          : Map<String, dynamic>.from(progressData!['progress'] as Map),
      reviews: reviews,
      recommended: related
          .where((b) => b['id'] != _bookId)
          .take(5)
          .toList(),
    );
  }

  Future<void> refreshReviews() async {
    final reviews = await BookRepository.instance.reviews(_bookId);
    state = state.copyWith(reviews: reviews);
  }

  Future<void> postReview(int rating, String text,
      {String displayName = 'Reader'}) async {
    await BookRepository.instance
        .createReview(_bookId, rating, text, displayName: displayName);
    await refreshReviews();
  }

  Future<bool> deleteChapter(int chapterNumber) async {
    await BookRepository.instance
        .deleteChapter(bookId: _bookId, chapterNumber: chapterNumber);
    await refresh();
    return true;
  }

  /// Spending gems to boost — null result means the spend failed.
  Future<Map<String, dynamic>?> boost() =>
      BookRepository.instance.boost(_bookId);

  /// Reading progress for this book (used by the details continue-card).
  Future<void> reloadProgress() async {
    final res = await BookRepository.instance.readingProgress(_bookId);
    final progressData = res?['progress'];
    state = state.copyWith(
      progress: progressData is Map
          ? Map<String, dynamic>.from(progressData)
          : null,
      clearProgress: progressData is! Map,
    );
  }
}

final bookDetailProvider = NotifierProvider.autoDispose
    .family<BookDetailController, BookDetailState, String>(
        BookDetailController.new);

/// A book loaded for the writer tools (chapter manager, publish
/// preview) — the legacy fallback lives inside the repository.
final manageBookProvider = FutureProvider.autoDispose
    .family<BookWithChapters, String>(
        (ref, bookId) => BookRepository.instance.getForManage(bookId));
