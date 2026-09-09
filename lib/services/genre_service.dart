import 'backend_api.dart';

/// The genre taxonomy that ships inside the app — the instant default and
/// the offline fallback. The live lists come from the moderator-curated
/// backend (`genres.list`): the overall moderator adds and removes genres
/// from the moderation console and every device picks the change up. No
/// screen keeps its own copy; all of them read this one instance.
const List<String> kBookNestGenres = [
  'Romance',
  'Science Fiction',
  'Thriller & Suspense',
  'Fantasy',
  'Mystery & Crime',
  'Horror',
  'Historical Fiction',
  'Literary Fiction',
  'Westerns',
  'Biographies & Memoirs',
  'True Crime',
  'Self-Help & Wellness',
  'History & Politics',
  'Young Adult (YA)',
  'STEM',
  'Humanities & Social Sciences',
  'Languages & Linguistics',
  'Finance & Economics',
  'Professional Certification',
  'Lexicons',
  'Research & Citation Tools',
  'Compendiums',
];

/// The club taxonomy that ships inside the app (same idea as the shelves
/// above — the moderator curates the live list from the console).
const List<String> kBookNestClubGenres = [
  'Fiction',
  'Non-Fiction',
  'Sci-Fi',
  'Classics',
  'African Lit',
  'Romance',
  'Thriller',
  'Poetry',
  'Academic',
  'WAEC Prep',
];

class GenreService {
  GenreService._();
  static final GenreService instance = GenreService._();

  final List<String> bookGenres = List<String>.from(kBookNestGenres);
  final List<String> clubGenres = List<String>.from(kBookNestClubGenres);
  bool _loaded = false;

  /// Pulls the moderator-curated lists. Never throws; on any failure the
  /// current lists (the defaults on first run) stay in place, so every
  /// screen keeps working offline. Results are cached by BackendApi.
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    final res = await BackendApi.instance.call('genres.list');
    if (res == null) return;
    final books = res['bookGenres'];
    final clubs = res['clubGenres'];
    if (books is List && books.isNotEmpty) {
      bookGenres
        ..clear()
        ..addAll(books.map((e) => e.toString()));
    }
    if (clubs is List && clubs.isNotEmpty) {
      clubGenres
        ..clear()
        ..addAll(clubs.map((e) => e.toString()));
    }
    _loaded = true;
  }
}
