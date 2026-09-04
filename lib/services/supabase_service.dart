import 'package:flutter/foundation.dart';
import 'dictionary_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// A permission or connection failure surfaced with human language.
class WriteException implements Exception {
  final String message;
  WriteException(this.message);
  @override
  String toString() => message;
}

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  late final SupabaseClient client;

  Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      // Only log auth/network debug output in debug builds — never in release.
      debug: kDebugMode,
    );
    client = Supabase.instance.client;
  }

  SupabaseClient get supabase => client;
  GoTrueClient get auth => client.auth;

  // ───────────────────────────────────────────────────────────────────────
  // Resilient writes: try the direct (RLS-checked) path first; if the
  // database refuses (e.g. stale policies → error 42501), fall back to the
  // booknest-api edge function, which force-binds the row to the verified
  // caller. The caller never sees a raw 42501.
  // ───────────────────────────────────────────────────────────────────────
  /// Production-safe error copy: end users never see infrastructure
  /// details (services, dashboards, scripts). Raw errors are logged in
  /// debug builds only.
  String _friendly(Object error) {
    final raw = error.toString();
    if (raw.contains('duplicate key') && raw.contains('username')) {
      return 'That username is already taken — try another.';
    }
    if (raw.contains('42501') || raw.contains('row-level security')) {
      return "That action isn't allowed for your account right now. "
          'Please try again later.';
    }
    if (raw.contains('foreign key')) {
      return 'Your profile is still syncing — try again in a minute.';
    }
    return "BookNest couldn't complete that just now — please try again "
        'in a moment.';
  }

  dynamic _requireSession() {
    final user = auth.currentUser;
    if (user == null) {
      throw WriteException('Please sign in again to continue.');
    }
    return user;
  }

  /// INSERT into a Supabase table with edge-function fallback.
  /// Returns the inserted row (map) when available.
  Future<Map<String, dynamic>?> writeRow(
    String table,
    Map<String, dynamic> values,
  ) async {
    _requireSession();
    try {
      final res =
          await client.from(table).insert(values).select().single();
      return Map<String, dynamic>.from(res as Map);
    } on WriteException {
      rethrow;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('writeRow($table) direct path failed → edge fallback: $error');
      }
      try {
        final res = await client.functions.invoke(
          'booknest-api',
          body: {
            'action': 'db.write',
            'table': table,
            'op': 'insert',
            'values': values,
          },
        );
        final data = res.data;
        if (data is Map && data['row'] != null) {
          return Map<String, dynamic>.from(data['row'] as Map);
        }
        throw WriteException('Write rejected by the server.');
      } on WriteException {
        rethrow;
      } catch (edgeError) {
        // Only possible cause left for an unauthenticated caller:
        if (auth.currentUser == null) {
          throw WriteException('Please sign in again to continue.');
        }
        if (kDebugMode) debugPrint('writeRow fallback failed: $edgeError');
        throw WriteException(_friendly(edgeError));
      }
    }
  }

  /// UPDATE rows in a Supabase table with edge-function fallback.
  Future<void> updateRow(
    String table,
    Map<String, dynamic> values, {
    required String column,
    required String equals,
  }) async {
    _requireSession();
    try {
      await client.from(table).update(values).eq(column, equals);
      return;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('updateRow($table) direct path failed → edge fallback: $error');
      }
      try {
        final res = await client.functions.invoke(
          'booknest-api',
          body: {
            'action': 'db.write',
            'table': table,
            'op': 'update',
            'values': values,
            'match': {column: equals},
          },
        );
        final data = res.data;
        if (data is Map && data['row'] != null) return;
        throw WriteException('Update rejected by the server.');
      } on WriteException {
        rethrow;
      } catch (edgeError) {
        if (kDebugMode) debugPrint('updateRow fallback failed: $edgeError');
        throw WriteException(_friendly(edgeError));
      }
    }
  }

  // ── Feed post likes (stored in the social store via the edge API) ──

  /// Like counts + whether the current user liked each post, keyed by post
  /// id. Best-effort: an empty map is returned on failure so the feed never
  /// blocks on it.
  Future<Map<String, Map<String, dynamic>>> feedStats(List<String> postIds) async {
    _requireSession();
    try {
      final res = await client.functions.invoke(
        'booknest-api',
        body: {'action': 'feed.stats', 'postIds': postIds},
      );
      final data = res.data;
      if (data is Map && data['stats'] is Map) {
        final raw = data['stats'] as Map;
        return raw.map(
          (k, v) => MapEntry(
            k.toString(),
            v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{},
          ),
        );
      }
      return {};
    } catch (error) {
      if (kDebugMode) debugPrint('feedStats unavailable: $error');
      return {};
    }
  }

  /// Likes or unlikes a feed post and returns the fresh server-side count.
  /// Throws [WriteException] when the change could not be saved.
  Future<int> setFeedLike(String postId, {required bool liked}) async {
    _requireSession();
    try {
      final res = await client.functions.invoke(
        'booknest-api',
        body: {
          'action': liked ? 'feed.like' : 'feed.unlike',
          'postId': postId,
        },
      );
      final data = res.data;
      if (data is Map && data['likeCount'] is num) {
        return (data['likeCount'] as num).toInt();
      }
      throw WriteException(
          "BookNest couldn't complete that just now — please try again in a moment.");
    } on WriteException {
      rethrow;
    } catch (error) {
      throw WriteException(_friendly(error));
    }
  }

  // ── Word Nest dictionary community layer (best-effort, offline-safe) ──

  /// Records a lookup so the community trending list stays fresh.
  /// Failures are swallowed — the dictionary itself is offline-first.
  Future<void> logDictionarySearch(String term) async {
    final t = term.trim().toLowerCase();
    if (t.length < 2 || t.length > 40) return;
    _requireSession();
    try {
      await client.functions.invoke(
        'booknest-api',
        body: {'action': 'dict.log', 'term': t},
      );
    } catch (error) {
      if (kDebugMode) debugPrint('dict.log skipped: $error');
    }
  }

  /// Looks any word up in the full dictionary (server-side, cached).
  /// Returns null when the word can't be found or we're offline — the
  /// bundled edition remains the offline base.
  Future<WordEntry?> lookupOnline(String word) async {
    _requireSession();
    try {
      final res = await client.functions.invoke(
        'booknest-api',
        body: {
          'action': 'dict.lookup',
          'word': word.trim().toLowerCase(),
        },
      );
      final data = res.data;
      if (data is! Map || data['word'] is! Map) return null;
      final w = Map<String, dynamic>.from(data['word'] as Map);
      final meanings =
          ((w['meanings'] as List?) ?? const []).whereType<Map>().toList();
      final defs = <String>[];
      final examples = <String>[];
      final syns = <String>[];
      var pos = '';
      for (final m in meanings) {
        for (final d in ((m['defs'] as List?) ?? const [])) {
          if (d is Map && d['d'] != null && d['d'].toString().isNotEmpty) {
            defs.add(d['d'].toString());
            final ex = d['ex'];
            if (ex != null && ex.toString().isNotEmpty) {
              examples.add(ex.toString());
            }
          }
        }
        for (final sy in ((m['syns'] as List?) ?? const [])) {
          final v = sy.toString();
          if (v.isNotEmpty) syns.add(v);
        }
        if (pos.isEmpty) pos = m['pos']?.toString() ?? '';
        if (defs.length >= 6) break;
      }
      if (defs.isEmpty) return null;
      return WordEntry(
        word: w['word']?.toString() ?? word,
        pos: pos,
        definition: defs.first,
        example: examples.isNotEmpty ? examples.first : '',
        synonyms: syns.take(8).toList(),
      );
    } catch (error) {
      if (kDebugMode) debugPrint('lookupOnline unavailable: $error');
      return null;
    }
  }

  /// Words the community looked up most in the last 7 days.
  /// Returns an empty list when offline or unavailable.
  Future<List<String>> fetchDictionaryTrending() async {
    _requireSession();
    try {
      final res = await client.functions.invoke(
        'booknest-api',
        body: {'action': 'dict.trending'},
      );
      final data = res.data;
      if (data is Map && data['trending'] is List) {
        return (data['trending'] as List).map((t) => t.toString()).toList();
      }
      return const [];
    } catch (error) {
      if (kDebugMode) debugPrint('dict.trending unavailable: $error');
      return const [];
    }
  }

  /// Live profile search used by the DM contact picker and global search.
  /// Server-side `ilike` over username AND display name (matches any part).
  Future<List<Map<String, dynamic>>> searchProfiles(String term,
      {int limit = 20}) async {
    final query = term.trim();
    try {
      // Filters first, terminal transforms last: .or() must precede .limit().
      PostgrestFilterBuilder<List<Map<String, dynamic>>> request = client
          .from('profiles')
          .select('id, username, display_name, avatar_url');
      final safe = query.replaceAll(RegExp(r'[%_,()]'), '');
      if (safe.isNotEmpty) {
        request =
            request.or('username.ilike.%$safe%,display_name.ilike.%$safe%');
      }
      final rows = await request.limit(limit);
      final viewer = auth.currentUser?.id;
      return (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((person) => person['id'].toString() != viewer)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Self-heal: guarantee the signed-in user has a profiles row (older
  /// signups predate the auto-create trigger). Safe to call repeatedly.
  Future<void> ensureProfile() async {
    final user = auth.currentUser;
    if (user == null) return;
    try {
      final existing = await client
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      if (existing != null) return;
    } catch (_) {
      return; // table unreachable — nothing to heal here
    }
    final meta = user.userMetadata;
    final username = (meta?['username']?.toString().isNotEmpty ?? false)
        ? meta!['username'].toString()
        : (user.email?.split('@').first ?? 'reader');
    try {
      await client.from('profiles').upsert({
        'id': user.id,
        'username': username,
        'display_name': username,
      });
    } catch (_) {
      // Duplicate username etc. — retry with a disambiguated handle.
      try {
        await client.from('profiles').upsert({
          'id': user.id,
          'username': '${username}_'
              '${DateTime.now().millisecondsSinceEpoch % 10000}',
          'display_name': username,
        });
      } catch (_) {}
    }
  }

  // Create profile after signup (used by the register flow).
  Future<void> createProfile({
    required String userId,
    required String username,
    String? displayName,
    String? phoneNumber,
  }) async {
    await client.from('profiles').upsert({
      'id': userId,
      'username': username,
      'display_name': displayName ?? username,
      'phone_number': phoneNumber,
      'gems': 77, // Welcome bonus
    });
  }
}
