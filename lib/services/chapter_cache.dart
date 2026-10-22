import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'backend_api.dart';

/// Book chapters kept on the device.
///
/// Chapters are the heaviest thing the app downloads (a classic's chapter
/// can be 300 KB of text), and before this every reopen downloaded it
/// again. Now:
///  · library classics (ids `bulk-…`, their text never changes) open
///    straight from the device with no request at all; they are re-checked
///    only after 30 days;
///  · members' books may be edited, so each open asks the server with the
///    cached fingerprint; when nothing changed the answer is a few bytes
///    and the cached text is shown.
/// The cache is capped (oldest chapters are dropped first).
class ChapterCache {
  ChapterCache._();
  static final ChapterCache instance = ChapterCache._();

  static const int _maxBytes = 120 * 1024 * 1024;
  static const Duration _libraryRecheck = Duration(days: 30);

  Directory? _dir;
  int _writesSinceTrim = 0;

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/chapter_cache');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<File> _file(String bookId, int chapterNumber) async {
    final dir = await _cacheDir();
    final safe = bookId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final name = safe.length > 120 ? safe.substring(0, 120) : safe;
    return File('${dir.path}/${name}_${_fnv(bookId)}_$chapterNumber.json');
  }

  static bool isLibraryBook(String bookId) => bookId.startsWith('bulk-');

  /// The chapter payload (same shape as the `books.chapter` answer), from
  /// the device when possible. Null when it is neither cached nor reachable.
  Future<Map<String, dynamic>?> load(String bookId, int chapterNumber) async {
    _Cached? hit;
    try {
      hit = await _read(bookId, chapterNumber);
    } catch (_) {
      hit = null;
    }
    final library = isLibraryBook(bookId);
    if (hit != null &&
        library &&
        DateTime.now().difference(hit.savedAt) < _libraryRecheck) {
      return hit.data; // immutable text — no request at all
    }
    final answer = await BackendApi.instance.callIfChanged(
      'books.chapter',
      <String, dynamic>{'bookId': bookId, 'chapterNumber': chapterNumber},
      ifRev: hit?.rev,
    );
    if (answer == null) return hit?.data; // offline: the saved copy
    if (answer.unchanged && hit != null) {
      if (library) _touch(bookId, chapterNumber, hit);
      return hit.data;
    }
    final data = answer.data;
    if (data == null) return hit?.data;
    final content = data['content']?.toString() ?? '';
    if (content.isNotEmpty) {
      _write(bookId, chapterNumber, data, answer.rev);
    }
    return data;
  }

  Future<_Cached?> _read(String bookId, int chapterNumber) async {
    final file = await _file(bookId, chapterNumber);
    if (!await file.exists()) return null;
    final decoded = await compute(_decode, await file.readAsString());
    if (decoded is! Map || decoded['data'] is! Map) return null;
    return _Cached(
      Map<String, dynamic>.from(decoded['data'] as Map),
      decoded['rev']?.toString(),
      DateTime.fromMillisecondsSinceEpoch(
          (decoded['savedAt'] as num?)?.toInt() ?? 0),
    );
  }

  void _touch(String bookId, int chapterNumber, _Cached hit) {
    _write(bookId, chapterNumber, hit.data, hit.rev);
  }

  Future<void> _write(String bookId, int chapterNumber,
      Map<String, dynamic> data, String? rev) async {
    try {
      final file = await _file(bookId, chapterNumber);
      final text = await compute(_encode, <String, dynamic>{
        'v': 1,
        'rev': rev,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'data': data,
      });
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
      if (++_writesSinceTrim >= 25) {
        _writesSinceTrim = 0;
        await _trim();
      }
    } catch (_) {
      // Disk full or read-only — reading still works from the network.
    }
  }

  /// Keeps the cache under its cap, dropping the least recently saved.
  Future<void> _trim() async {
    try {
      final dir = await _cacheDir();
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) files.add(entity);
      }
      final stats = <File, FileStat>{};
      var total = 0;
      for (final f in files) {
        final st = await f.stat();
        stats[f] = st;
        total += st.size;
      }
      if (total <= _maxBytes) return;
      files.sort((a, b) => stats[a]!.modified.compareTo(stats[b]!.modified));
      for (final f in files) {
        if (total <= _maxBytes * 0.8) break;
        total -= stats[f]!.size;
        try {
          await f.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Removes every saved chapter (Settings → clear cache, sign-out).
  Future<void> clear() async {
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {}
  }
}

class _Cached {
  final Map<String, dynamic> data;
  final String? rev;
  final DateTime savedAt;
  const _Cached(this.data, this.rev, this.savedAt);
}

/// Stable across app versions (String.hashCode is not guaranteed to be).
String _fnv(String input) {
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16);
}

Object? _decode(String text) => jsonDecode(text);
String _encode(Map<String, dynamic> value) => jsonEncode(value);
