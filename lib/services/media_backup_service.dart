import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'chat_store.dart';
import 'doc_extract.dart' show isVideoExtension;
import 'google_desktop_auth.dart';

/// Where a chat media file lives on this device once downloaded. The media
/// viewer, the bubbles and the Google Drive backup all share this cache, so
/// nothing is downloaded twice.
String mediaCachePath(String url) {
  final safe = url.hashCode.abs().toRadixString(36);
  return '${Directory.systemTemp.path}/booknest_media/$safe';
}

/// The reader's own Google account (hidden Drive app folder). Shared by the
/// media backup and the older Drive text backups.
class DriveClient {
  DriveClient._();
  static final DriveClient instance = DriveClient._();

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';

  late final GoogleSignIn google = GoogleSignIn(
    scopes: const [scope],
    // iOS needs its OAuth client id (Android resolves it from the package
    // name + signing certificate). Built in by CI from a GitHub secret.
    clientId: Platform.isIOS && AppConfig.googleIosClientId.isNotEmpty
        ? AppConfig.googleIosClientId
        : null,
  );

  /// Google Drive works on Android; on iPhone once the iOS OAuth client id
  /// is built in; on PC (Windows/macOS/Linux) once the desktop OAuth client
  /// is built in (browser sign-in, see DesktopGoogleAuth).
  bool get supported =>
      Platform.isAndroid ||
      (Platform.isIOS && AppConfig.googleIosClientId.isNotEmpty) ||
      DesktopGoogleAuth.instance.configured;

  /// The connected Google account's email (silent), or null.
  Future<String?> email() async {
    if (DesktopGoogleAuth.isDesktop) return DesktopGoogleAuth.instance.email();
    return (await account())?.email;
  }

  Future<GoogleSignInAccount?> account({bool interactive = false}) async {
    if (!supported || DesktopGoogleAuth.isDesktop) return null;
    try {
      var account = await google.signInSilently();
      if (account == null && interactive) account = await google.signIn();
      return account;
    } catch (_) {
      return null; // not configured / no Play services
    }
  }

  Future<Map<String, String>?> headers({bool interactive = false}) async {
    if (DesktopGoogleAuth.isDesktop) {
      final token = await DesktopGoogleAuth.instance
          .accessToken(interactive: interactive);
      return token == null ? null : {'Authorization': 'Bearer $token'};
    }
    final acc = await account(interactive: interactive);
    if (acc == null) return null;
    try {
      final token = (await acc.authentication).accessToken;
      if (token == null || token.isEmpty) return null;
      return {'Authorization': 'Bearer $token'};
    } catch (_) {
      return null;
    }
  }

  /// First file in the app folder with this exact name: (id, size) or null.
  Future<({String id, int size})?> find(
      Map<String, String> h, String name) async {
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files'
        '?spaces=appDataFolder'
        '&q=${Uri.encodeQueryComponent("name='$name' and trashed=false")}'
        '&fields=${Uri.encodeQueryComponent('files(id,size)')}&pageSize=1');
    final res =
        await http.get(uri, headers: h).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final files = (jsonDecode(res.body) as Map)['files'];
    if (files is! List || files.isEmpty || files.first is! Map) return null;
    final f = files.first as Map;
    return (id: '${f['id']}', size: int.tryParse('${f['size'] ?? 0}') ?? 0);
  }

  /// Uploads [file] (any size — resumable upload, streamed from disk) into
  /// the app folder. Replaces [existingId] when given. Returns the file id.
  Future<String?> uploadFile(Map<String, String> h, File file, String name,
      {String? existingId, String mime = 'application/octet-stream'}) async {
    try {
      final length = await file.length();
      final start = existingId == null
          ? http.Request(
              'POST',
              Uri.parse('https://www.googleapis.com/upload/drive/v3/files'
                  '?uploadType=resumable&fields=id'))
          : http.Request(
              'PATCH',
              Uri.parse(
                  'https://www.googleapis.com/upload/drive/v3/files/$existingId'
                  '?uploadType=resumable&fields=id'));
      start.headers.addAll({
        ...h,
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': mime,
        'X-Upload-Content-Length': '$length',
      });
      start.body = jsonEncode(existingId == null
          ? {'name': name, 'parents': ['appDataFolder']}
          : <String, dynamic>{});
      final started =
          await start.send().timeout(const Duration(seconds: 30));
      final location = started.headers['location'];
      await started.stream.drain<void>();
      if (location == null || started.statusCode != 200) return null;
      final put = http.StreamedRequest('PUT', Uri.parse(location))
        ..headers.addAll({...h, 'Content-Type': mime})
        ..contentLength = length;
      // Stream the file from disk (never the whole video in memory).
      file.openRead().listen(put.sink.add,
          onError: put.sink.addError, onDone: put.sink.close);
      final done = await put.send().timeout(const Duration(minutes: 30));
      final body = await done.stream.bytesToString();
      if (done.statusCode != 200 && done.statusCode != 201) return null;
      return (jsonDecode(body) as Map)['id']?.toString() ?? existingId;
    } catch (_) {
      return null;
    }
  }

  Future<String?> uploadBytes(
      Map<String, String> h, Uint8List bytes, String name,
      {String? existingId, String mime = 'application/json'}) async {
    final tmp = File('${Directory.systemTemp.path}/bn_drive_${bytes.hashCode}');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      return await uploadFile(h, tmp, name, existingId: existingId, mime: mime);
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  /// Streams a Drive file to [dest]. True when complete.
  Future<bool> downloadTo(Map<String, String> h, String id, File dest) async {
    final client = http.Client();
    try {
      final res = await client
          .send(http.Request('GET',
              Uri.parse('https://www.googleapis.com/drive/v3/files/$id?alt=media'))
            ..headers.addAll(h))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return false;
      await dest.parent.create(recursive: true);
      final part = File('${dest.path}.part');
      final sink = part.openWrite();
      await res.stream.pipe(sink);
      await part.rename(dest.path);
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<Uint8List?> downloadBytes(Map<String, String> h, String id) async {
    try {
      final res = await http
          .get(Uri.parse('https://www.googleapis.com/drive/v3/files/$id?alt=media'),
              headers: h)
          .timeout(const Duration(seconds: 60));
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> delete(Map<String, String> h, String id) async {
    try {
      final res = await http
          .delete(Uri.parse('https://www.googleapis.com/drive/v3/files/$id'),
              headers: h)
          .timeout(const Duration(seconds: 20));
      return res.statusCode == 204 || res.statusCode == 200 || res.statusCode == 404;
    } catch (_) {
      return false;
    }
  }
}

/// Progress of a running media backup, for the Chat backup screen.
class MediaBackupProgress {
  final int done;
  final int total;
  final int bytes;
  const MediaBackupProgress(this.done, this.total, this.bytes);
}

/// Chat photos, videos, voice notes and files → the reader's OWN Google
/// Drive (hidden BookNest app folder). BookNest's servers keep chat media
/// for 30 days only (it is just relayed through Cloudinary); after that
/// the phone and the reader's Google account are where it lives. Text
/// messages are backed up separately, sealed, to BookNest (MongoDB).
///
/// Incremental: an index file in the same Drive folder remembers what is
/// already there, so each run uploads only new media. When a chat photo or
/// file is no longer on Cloudinary, [recover] fetches the Drive copy.
class MediaBackupService {
  MediaBackupService._();
  static final MediaBackupService instance = MediaBackupService._();

  static const _indexName = 'booknest-media-index.json';
  static const _enabledPref = 'booknest.media.backup';
  static const _videosPref = 'booknest.media.videos';
  static const _lastAtPref = 'booknest.media.lastAt';
  static const _countPref = 'booknest.media.count';
  static const _bytesPref = 'booknest.media.bytes';
  static const _maxFileBytes = 200 * 1024 * 1024;

  final ValueNotifier<MediaBackupProgress?> progress =
      ValueNotifier<MediaBackupProgress?>(null);

  bool _running = false;
  bool get running => _running;

  Map<String, dynamic>? _index; // hash → {id, n, s, t}
  String? _indexId;
  bool _indexLoaded = false;

  bool get supported => DriveClient.instance.supported;

  Future<bool> get enabled async =>
      (await SharedPreferences.getInstance()).getBool(_enabledPref) ?? false;
  Future<void> setEnabled(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_enabledPref, v);

  Future<bool> get includeVideos async =>
      (await SharedPreferences.getInstance()).getBool(_videosPref) ?? true;
  Future<void> setIncludeVideos(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_videosPref, v);

  Future<DateTime?> get lastAt async {
    final raw = (await SharedPreferences.getInstance()).getString(_lastAtPref);
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  /// (files, bytes) in the reader's Drive media backup.
  Future<(int, int)> get stored async {
    final p = await SharedPreferences.getInstance();
    return (p.getInt(_countPref) ?? 0, p.getInt(_bytesPref) ?? 0);
  }

  static String _hash(String url) {
    final d = SHA256Digest().process(Uint8List.fromList(utf8.encode(url)));
    final b = StringBuffer();
    for (final x in d.take(16)) {
      b.write(x.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  Future<File> _localIndexFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/booknest_media_index.json');
  }

  Future<void> _loadIndex(Map<String, String>? h) async {
    if (_indexLoaded && _index != null) return;
    // 1) the copy on this phone, 2) the one in the reader's Drive.
    try {
      final f = await _localIndexFile();
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString());
        if (m is Map) {
          _index = Map<String, dynamic>.from(m['items'] as Map? ?? {});
          _indexId = m['driveId']?.toString();
        }
      }
    } catch (_) {}
    if (h != null) {
      try {
        final found = await DriveClient.instance.find(h, _indexName);
        if (found != null) {
          _indexId = found.id;
          final bytes = await DriveClient.instance.downloadBytes(h, found.id);
          if (bytes != null) {
            final m = jsonDecode(utf8.decode(bytes));
            if (m is Map && m['items'] is Map) {
              _index = {
                ...?_index,
                ...Map<String, dynamic>.from(m['items'] as Map),
              };
            }
          }
        }
        _indexLoaded = true;
      } catch (_) {}
    }
    _index ??= <String, dynamic>{};
  }

  Future<void> _saveIndex(Map<String, String>? h) async {
    final items = _index ?? const <String, dynamic>{};
    try {
      final f = await _localIndexFile();
      await f.writeAsString(jsonEncode({'items': items, 'driveId': _indexId}));
    } catch (_) {}
    if (h == null) return;
    final bytes =
        Uint8List.fromList(utf8.encode(jsonEncode({'v': 1, 'items': items})));
    final id = await DriveClient.instance
        .uploadBytes(h, bytes, _indexName, existingId: _indexId);
    if (id != null) _indexId = id;
    var total = 0;
    for (final v in items.values) {
      if (v is Map) total += (v['s'] as num?)?.toInt() ?? 0;
    }
    final p = await SharedPreferences.getInstance();
    await p.setInt(_countPref, items.length);
    await p.setInt(_bytesPref, total);
  }

  /// Every media message this phone holds: url → (type, name).
  List<({String url, String type, String name})> _mediaMessages() {
    final out = <({String url, String type, String name})>[];
    final seen = <String>{};
    final all = ChatStore.instance.exportAll();
    for (final chat in all.values) {
      if (chat is! Map || chat['messages'] is! List) continue;
      for (final m in chat['messages'] as List) {
        if (m is! Map) continue;
        final url = m['mediaUrl']?.toString() ?? '';
        if (!url.startsWith('http') || !seen.add(url)) continue;
        if (m['deletedForEveryone'] == true) continue;
        out.add((
          url: url,
          type: m['type']?.toString() ?? 'file',
          name: m['fileName']?.toString() ?? '',
        ));
      }
    }
    return out;
  }

  static String _ext(String url, String name) {
    for (final s in [name, url.split('?').first]) {
      final dot = s.lastIndexOf('.');
      if (dot > 0 && s.length - dot <= 6) return s.substring(dot + 1).toLowerCase();
    }
    return 'bin';
  }

  /// Gets the media onto this phone (cache) from Cloudinary. Null when the
  /// relay copy is gone.
  Future<File?> _localCopy(String url) async {
    final file = File(mediaCachePath(url));
    if (await file.exists() && await file.length() > 0) return file;
    final client = http.Client();
    try {
      final res = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        await res.stream.drain<void>();
        return null;
      }
      if ((res.contentLength ?? 0) > _maxFileBytes) {
        await res.stream.drain<void>();
        return null;
      }
      await file.parent.create(recursive: true);
      final part = File('${file.path}.part');
      await res.stream.pipe(part.openWrite());
      await part.rename(file.path);
      return file;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Backs up new chat media to the reader's Google Drive. [interactive]
  /// may show the Google account picker. Returns files uploaded this run,
  /// or -1 when Google Drive is not reachable.
  Future<int> backupNow({bool interactive = true, int limit = 1 << 30}) async {
    if (_running) return 0;
    _running = true;
    try {
      final h = await DriveClient.instance.headers(interactive: interactive);
      if (h == null) return -1;
      await ChatStore.instance.flush();
      await _loadIndex(h);
      final videos = await includeVideos;
      final todo = _mediaMessages().where((m) {
        if (_index!.containsKey(_hash(m.url))) return false;
        final ext = _ext(m.url, m.name);
        if (!videos && (m.type == 'video' || isVideoExtension(ext))) return false;
        return true;
      }).toList();
      var done = 0;
      var bytes = 0;
      var sinceSave = 0;
      progress.value = MediaBackupProgress(0, todo.length, 0);
      for (final m in todo) {
        if (done >= limit) break;
        final file = await _localCopy(m.url);
        if (file != null) {
          final size = await file.length();
          if (size <= _maxFileBytes) {
            final hash = _hash(m.url);
            final ext = _ext(m.url, m.name);
            final id = await DriveClient.instance
                .uploadFile(h, file, 'm_$hash.$ext');
            if (id != null) {
              _index![hash] = {
                'id': id,
                'n': m.name.isEmpty ? 'm_$hash.$ext' : m.name,
                's': size,
                't': m.type,
              };
              bytes += size;
              sinceSave++;
            }
          }
        }
        done++;
        progress.value = MediaBackupProgress(done, todo.length, bytes);
        if (sinceSave >= 15) {
          await _saveIndex(h);
          sinceSave = 0;
        }
      }
      await _saveIndex(h);
      final p = await SharedPreferences.getInstance();
      await p.setString(_lastAtPref, DateTime.now().toUtc().toIso8601String());
      return done;
    } finally {
      _running = false;
      progress.value = null;
    }
  }

  /// A chat file that is no longer on Cloudinary (older than 30 days):
  /// bring it back from the reader's Google Drive into the cache. Silent —
  /// never shows a Google prompt. Null when there is no Drive copy.
  Future<File?> recover(String url) async {
    if (!url.startsWith('http')) return null;
    final file = File(mediaCachePath(url));
    try {
      if (await file.exists() && await file.length() > 0) return file;
      if (!supported) return null;
      final h = await DriveClient.instance.headers();
      await _loadIndex(h);
      final entry = _index?[_hash(url)];
      if (entry is! Map || h == null) return null;
      final ok = await DriveClient.instance
          .downloadTo(h, entry['id'].toString(), file);
      return ok ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Removes every backed-up media file from the reader's Drive.
  Future<bool> deleteAll() async {
    final h = await DriveClient.instance.headers(interactive: true);
    if (h == null) return false;
    await _loadIndex(h);
    var ok = true;
    for (final v in (_index ?? const {}).values) {
      if (v is Map && !await DriveClient.instance.delete(h, '${v['id']}')) {
        ok = false;
      }
    }
    if (_indexId != null) await DriveClient.instance.delete(h, _indexId!);
    _index = {};
    _indexId = null;
    await _saveIndex(null);
    final p = await SharedPreferences.getInstance();
    await p.remove(_lastAtPref);
    await p.setInt(_countPref, 0);
    await p.setInt(_bytesPref, 0);
    return ok;
  }

  /// Daily/weekly/monthly with the text backup — silent, Google account
  /// must already be connected. At most 150 files per scheduled run.
  Future<void> maybeRunScheduled(Duration every) async {
    if (!supported || !await enabled || _running) return;
    final last = await lastAt;
    if (last != null && DateTime.now().difference(last) < every) return;
    await backupNow(interactive: false, limit: 150);
  }
}
