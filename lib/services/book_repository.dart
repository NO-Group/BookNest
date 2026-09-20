import 'backend_api.dart';
import 'supabase_service.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// The book data layer. Every screen reads and writes books through HERE —
/// the UI never knows the data lives in MongoDB behind the edge function
/// (with one transitional Supabase fallback that also lives in here, not
/// in a widget). Swap or re-shape the backend and only this file changes.
/// ─────────────────────────────────────────────────────────────────────────────

/// A book loaded for reading or managing: the book itself plus its
/// chapter list (chapter bodies stream separately in the reader).
class BookWithChapters {
  final Map<String, dynamic>? book;
  final List<Map<String, dynamic>> chapters;
  final bool fromLegacyFallback;

  const BookWithChapters({
    required this.book,
    this.chapters = const [],
    this.fromLegacyFallback = false,
  });
}

class BookRepository {
  BookRepository._();
  static final BookRepository instance = BookRepository._();

  BackendApi get _api => BackendApi.instance;

  /// The shelf: newest approved published books.
  Future<List<Map<String, dynamic>>> list({int limit = 50}) async {
    final res = await _api.call('books.list', {'limit': limit});
    return ((res?['books'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// One book with its chapters, or null when the cloud is unreachable.
  Future<BookWithChapters?> get(String bookId) async {
    final res = await _api.call('books.get', {'bookId': bookId});
    if (res == null) return null;
    final book = res['book'];
    final chapters = ((res['chapters'] as List?) ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    return BookWithChapters(
      book: book is Map ? Map<String, dynamic>.from(book) : null,
      chapters: chapters,
    );
  }

  /// Loading a book for the writer tools: the edge first, and for the
  /// oldest transitional books the Supabase chapters — a fallback that
  /// lives in the repository, where data access belongs.
  Future<BookWithChapters> getForManage(String bookId) async {
    final primary = await _api.call('books.get', {'bookId': bookId});
    if (primary != null) {
      final book = primary['book'];
      final chapters = ((primary['chapters'] as List?) ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map((row) => {
                'chapterNumber': row['chapterNumber'],
                'title': row['title'],
              })
          .toList();
      return BookWithChapters(
        book: book is Map ? Map<String, dynamic>.from(book) : null,
        chapters: chapters,
      );
    }
    // Graceful fallback: transitional Supabase chapters.
    try {
      final bookRow = await SupabaseService()
          .client
          .from('club_books')
          .select('title')
          .eq('id', bookId)
          .maybeSingle();
      final chapters = await SupabaseService()
          .client
          .from('book_chapters')
          .select('chapter_number, title')
          .eq('club_book_id', bookId)
          .order('chapter_number', ascending: true);
      return BookWithChapters(
        book: bookRow == null
            ? null
            : Map<String, dynamic>.from(bookRow as Map),
        chapters: (chapters as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .map((row) => {
                  'chapterNumber': row['chapter_number'],
                  'title': row['title'],
                })
            .toList(),
        fromLegacyFallback: true,
      );
    } catch (_) {
      return const BookWithChapters(book: null);
    }
  }

  /// Optimistic analytics: counted once per user per day server-side.
  Future<void> recordView(String bookId) => _api.recordView(bookId);

  Future<void> setLike(String bookId, bool liked) =>
      _api.setLike(bookId, liked);

  Future<void> setBookmark(String bookId, bool saved) =>
      _api.setBookmark(bookId, saved);

  Future<List<Map<String, dynamic>>> reviews(String bookId,
      {int limit = 12}) async {
    final res = await _api.call('reviews.list', {'bookId': bookId, 'limit': limit});
    return (((res?['reviews'] as List?) ?? const []))
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> createReview(String bookId, int rating, String text,
          {String displayName = 'Reader'}) =>
      _api.createReview(bookId, rating, text, displayName: displayName);

  Future<Map<String, dynamic>?> readingProgress(String bookId) =>
      _api.call('reader.progress.get', {'bookId': bookId});

  /// Spending gems to pin a book to the top of its shelves.
  Future<Map<String, dynamic>?> boost(String bookId) =>
      _api.call('gems.spend', {'kind': 'boost_book', 'bookId': bookId});

  Future<void> deleteChapter(
          {required String bookId, required int chapterNumber}) =>
      _api.deleteChapter(bookId: bookId, chapterNumber: chapterNumber);

}
