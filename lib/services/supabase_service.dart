import 'package:flutter/foundation.dart';
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
  String _friendly(Object error) {
    final raw = error.toString();
    if (raw.contains('42501') || raw.contains('row-level security')) {
      return 'BookNest could not verify your permission to write — check '
          'that the latest database upgrade script was run.';
    }
    if (raw.contains('duplicate key') && raw.contains('username')) {
      return 'That username is already taken — try another.';
    }
    if (raw.contains('foreign key')) {
      return 'Your profile row is missing — restart the app once to repair it.';
    }
    return raw.replaceFirst(RegExp(r'^.*?\{\s*"'), 'Something went wrong: ');
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
        throw WriteException(_friendly(edgeError));
      }
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
