import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One dictionary entry from the bundled Word Nest edition.
class WordEntry {
  final String word;
  final String pos;
  final String definition;
  final String example;
  final List<String> synonyms;

  const WordEntry({
    required this.word,
    required this.pos,
    required this.definition,
    required this.example,
    required this.synonyms,
  });

  factory WordEntry.fromJson(Map<String, dynamic> json) => WordEntry(
        word: (json['w'] as String? ?? '').trim(),
        pos: (json['p'] as String? ?? '').trim(),
        definition: (json['d'] as String? ?? '').trim(),
        example: (json['e'] as String? ?? '').trim(),
        synonyms: ((json['s'] as List<dynamic>?) ?? const [])
            .map((s) => s.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      );
}

/// Offline dictionary over the bundled edition, with deterministic
/// word-of-the-day selection and ranked search. Works with no network at
/// all; the community layer (trending) rides on top in the screen.
class DictionaryService {
  DictionaryService._();

  static final DictionaryService instance = DictionaryService._();

  static const String _assetPath = 'assets/dictionary/words.json';

  List<WordEntry>? _entries;
  Map<String, WordEntry>? _byWord;

  /// All entries, alphabetically ordered. Loaded once per app run.
  Future<List<WordEntry>> entries() async {
    final cached = _entries;
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(raw) as List<dynamic>;
      final list = decoded
          .whereType<Map<String, dynamic>>()
          .map(WordEntry.fromJson)
          .where((e) => e.word.isNotEmpty && e.definition.isNotEmpty)
          .toList()
        ..sort((a, b) => a.word.toLowerCase().compareTo(b.word.toLowerCase()));
      _entries = list;
      _byWord = {
        for (final e in list) e.word.toLowerCase(): e,
      };
      return list;
    } catch (error) {
      if (kDebugMode) debugPrint('dictionary load failed: $error');
      _entries = const [];
      _byWord = const {};
      return _entries!;
    }
  }

  /// Exact (case-insensitive) lookup, or null when the edition has no such
  /// word.
  Future<WordEntry?> lookup(String word) async {
    await entries();
    return _byWord?[word.trim().toLowerCase()];
  }

  /// Ranked search: exact prefix matches first, then substring matches,
  /// then matches inside definitions or synonyms.
  Future<List<WordEntry>> search(String query) async {
    final all = await entries();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;

    final scored = <({WordEntry entry, int rank})>[];
    for (final entry in all) {
      final w = entry.word.toLowerCase();
      var rank = -1;
      if (w == q) {
        rank = 0;
      } else if (w.startsWith(q)) {
        rank = 1;
      } else if (w.contains(q)) {
        rank = 2;
      } else if (entry.definition.toLowerCase().contains(q) ||
          entry.synonyms.any((s) => s.toLowerCase().contains(q))) {
        rank = 3;
      }
      if (rank >= 0) scored.add((entry: entry, rank: rank));
    }
    scored.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      return a.entry.word.toLowerCase().compareTo(b.entry.word.toLowerCase());
    });
    return scored.map((s) => s.entry).toList();
  }

  /// Word of the day: deterministic per calendar date, identical for
  /// everyone, no backend round trip.
  Future<WordEntry> wordOfTheDay() async {
    final all = await entries();
    if (all.isEmpty) throw StateError('dictionary edition is empty');
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    return all[dayOfYear % all.length];
  }

  /// A lucky dip: any entry from the edition.
  Future<WordEntry?> randomWord() async {
    final all = await entries();
    if (all.isEmpty) return null;
    return all[Random().nextInt(all.length)];
  }
}
