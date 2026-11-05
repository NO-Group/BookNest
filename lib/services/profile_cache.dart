import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

/// Names and avatars of other readers, cached on the device.
///
/// Chats, the inbox and group rooms all show the same handful of people,
/// and before this every load (and every 4-second chat poll in rooms)
/// queried their profiles again. Now a profile is fetched once and reused
/// for [_ttl]; only unknown or old entries go to the server, in one query.
class ProfileCache {
  ProfileCache._();
  static final ProfileCache instance = ProfileCache._();

  static const String _prefKey = 'bn.profiles.v1';
  static const Duration _ttl = Duration(hours: 12);
  static const int _maxEntries = 600;

  final Map<String, ({Map<String, dynamic> profile, DateTime at})> _mem = {};
  bool _loaded = false;
  Future<void>? _loading;
  Timer? _saveTimer;

  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefKey);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            decoded.forEach((id, value) {
              if (value is Map && value['p'] is Map) {
                _mem[id.toString()] = (
                  profile: Map<String, dynamic>.from(value['p'] as Map),
                  at: DateTime.fromMillisecondsSinceEpoch(
                      (value['at'] as num?)?.toInt() ?? 0),
                );
              }
            });
          }
        }
      } catch (_) {
        // A damaged entry is ignored and rebuilt from the server.
      }
      _loaded = true;
    }();
  }

  /// What is already known, synchronously (for an instant first paint).
  Map<String, Map<String, dynamic>> peek(Iterable<String> ids) {
    final out = <String, Map<String, dynamic>>{};
    for (final id in ids) {
      final hit = _mem[id];
      if (hit != null) out[id] = hit.profile;
    }
    return out;
  }

  /// Profiles for [ids]: cached ones instantly, missing or old ones in a
  /// single query. Never throws — unknown people are simply left out.
  Future<Map<String, Map<String, dynamic>>> lookup(Iterable<String> ids,
      {bool refresh = false}) async {
    await _ensureLoaded();
    final wanted = ids.where((id) => id.isNotEmpty).toSet();
    final now = DateTime.now();
    final missing = wanted.where((id) {
      final hit = _mem[id];
      return refresh || hit == null || now.difference(hit.at) > _ttl;
    }).toList();
    if (missing.isNotEmpty) {
      try {
        final rows = await SupabaseService()
            .client
            .from('profiles')
            .select('id, username, display_name, avatar_url')
            .inFilter('id', missing);
        for (final row in rows as List) {
          final person = Map<String, dynamic>.from(row as Map);
          final id = person['id']?.toString() ?? '';
          if (id.isNotEmpty) _mem[id] = (profile: person, at: now);
        }
        _scheduleSave();
      } catch (_) {
        // Offline: keep using whatever we had, however old.
      }
    }
    return peek(wanted);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      try {
        final rows = _mem.entries.toList()
          ..sort((a, b) => b.value.at.compareTo(a.value.at));
        final out = <String, dynamic>{};
        for (final row in rows.take(_maxEntries)) {
          out[row.key] = {
            'p': row.value.profile,
            'at': row.value.at.millisecondsSinceEpoch,
          };
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKey, jsonEncode(out));
      } catch (_) {}
    });
  }

  /// Forget everything (sign-out).
  Future<void> clear() async {
    _saveTimer?.cancel();
    _mem.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
  }
}
