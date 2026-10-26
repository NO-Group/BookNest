import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BookNest's own media folder on the device — WhatsApp-style. Every chat
/// photo, video, voice note and file that is sent or received is saved here
/// by default and is NEVER deleted by BookNest (the servers only keep chat
/// photos 30 days and chat files 3 days; the phone keeps everything).
///
///  • Android: Android/media/com.n_o_group.booknest/BookNest/Media/…
///    (no storage permission needed; visible in file managers, photos and
///    videos appear in the Gallery; removed only if the app is uninstalled)
///  • iPhone:  Files app → On My iPhone → BookNest → BookNest/Media/…
///  • PC:      Documents/BookNest/Media/…
///
/// Sub-folders: BookNest Images, BookNest Video, BookNest Voice Notes,
/// BookNest Audio, BookNest Documents.
class MediaStorage {
  MediaStorage._();

  static const images = 'BookNest Images';
  static const video = 'BookNest Video';
  static const voice = 'BookNest Voice Notes';
  static const audio = 'BookNest Audio';
  static const documents = 'BookNest Documents';
  static const _folders = [images, video, voice, audio, documents];

  static const _autoPref = 'booknest.media.autosave';
  static const _videosPref = 'booknest.media.autosaveVideos';
  static const _galleryPref = 'booknest.media.gallery';

  static const _channel = MethodChannel('booknest/storage');

  static String? _base;

  /// Save chat media to the phone automatically (default on).
  static bool autoSave = true;

  /// Include videos in the automatic saving (default on).
  static bool autoSaveVideos = true;

  /// Android: show BookNest photos and videos in the Gallery (default on).
  static bool showInGallery = true;

  /// The media folder (falls back to the temp cache until [init] ran).
  static String get base =>
      _base ?? '${Directory.systemTemp.path}/booknest_media';

  /// True once the permanent folder is in use.
  static bool get permanent => _base != null;

  /// Resolves and creates the folder. Called once at start-up; fast.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      autoSave = prefs.getBool(_autoPref) ?? true;
      autoSaveVideos = prefs.getBool(_videosPref) ?? true;
      showInGallery = prefs.getBool(_galleryPref) ?? true;
      String? root;
      if (Platform.isAndroid) {
        try {
          root = await _channel.invokeMethod<String>('mediaDir');
        } catch (_) {}
        root ??= (await getExternalStorageDirectory())?.path;
      }
      root ??= (await getApplicationDocumentsDirectory()).path;
      final dir = Directory('$root/BookNest/Media');
      await dir.create(recursive: true);
      for (final f in _folders) {
        await Directory('${dir.path}/$f').create(recursive: true);
      }
      // Voice notes never clutter music players.
      final nomediaVoice = File('${dir.path}/$voice/.nomedia');
      if (!await nomediaVoice.exists()) await nomediaVoice.create();
      _base = dir.path;
      await _applyGallery();
    } catch (_) {
      _base = null; // temp cache keeps working
    }
  }

  static Future<void> setAutoSave(bool v) async {
    autoSave = v;
    (await SharedPreferences.getInstance()).setBool(_autoPref, v);
  }

  static Future<void> setAutoSaveVideos(bool v) async {
    autoSaveVideos = v;
    (await SharedPreferences.getInstance()).setBool(_videosPref, v);
  }

  static Future<void> setShowInGallery(bool v) async {
    showInGallery = v;
    (await SharedPreferences.getInstance()).setBool(_galleryPref, v);
    await _applyGallery();
    if (v && Platform.isAndroid) {
      for (final f in [images, video]) {
        try {
          await for (final e in Directory('$base/$f').list()) {
            if (e is File) announce(e.path);
          }
        } catch (_) {}
      }
    }
  }

  static Future<void> _applyGallery() async {
    if (!permanent) return;
    for (final f in [images, video]) {
      final marker = File('$base/$f/.nomedia');
      try {
        if (showInGallery) {
          if (await marker.exists()) await marker.delete();
        } else if (!await marker.exists()) {
          await marker.create();
        }
      } catch (_) {}
    }
  }

  // ── naming ───────────────────────────────────────────────────────────────

  static const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp'};
  static const _videoExt = {'mp4', 'mov', 'm4v', 'webm', '3gp', 'mkv', 'avi'};
  static const _audioExt = {'m4a', 'aac', 'mp3', 'wav', 'ogg', 'opus', 'flac', 'amr'};

  /// Stable 64-bit FNV-1a of the URL → 11 base-36 chars.
  static String _hash(String s) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final b in utf8.encode(s)) {
      h = ((h ^ BigInt.from(b)) * prime) & mask;
    }
    final t = h.toRadixString(36);
    return t.length > 11 ? t.substring(0, 11) : t;
  }

  /// Where [url]'s file lives in the media folder (deterministic, so every
  /// screen finds the same copy).
  static final Map<String, String> _paths = <String, String>{};

  static String pathFor(String url) {
    final hit = _paths[url];
    if (hit != null && hit.startsWith(base)) return hit; // same folder
    if (_paths.length > 3000) _paths.clear();
    return _paths[url] = _pathFor(url);
  }

  static String _pathFor(String url) {
    final clean = url.split('?').first;
    var last = clean.split('/').last;
    try {
      last = Uri.decodeComponent(last);
    } catch (_) {}
    final dot = last.lastIndexOf('.');
    var ext = dot > 0 && last.length - dot <= 6
        ? last.substring(dot + 1).toLowerCase()
        : '';
    final stem = dot > 0 ? last.substring(0, dot) : last;
    final h = _hash(url);
    String folder;
    String name;
    if (_imageExt.contains(ext)) {
      folder = images;
      name = 'IMG-$h.$ext';
    } else if (_videoExt.contains(ext)) {
      folder = video;
      name = 'VID-$h.$ext';
    } else if (_audioExt.contains(ext) && stem.startsWith('voice_')) {
      folder = voice;
      name = 'PTT-$h.$ext';
    } else if (_audioExt.contains(ext)) {
      folder = audio;
      name = 'AUD-$h.$ext';
    } else {
      folder = documents;
      if (ext.isEmpty) ext = 'bin';
      final safe = stem
          .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final short = safe.length > 60 ? safe.substring(0, 60) : safe;
      name = '${short.isEmpty ? 'file' : short}-$h.$ext';
    }
    return '$base/$folder/$name';
  }

  /// Tells the Android Gallery about a newly saved photo/video.
  static void announce(String path) {
    if (!Platform.isAndroid || !permanent || !showInGallery) return;
    if (!path.contains('/$images/') && !path.contains('/$video/')) return;
    _channel.invokeMethod('scan', {'path': path}).catchError((_) => null);
  }

  /// Bytes on disk in the media folder.
  static Future<int> usage() async {
    var total = 0;
    try {
      await for (final e in Directory(base).list(recursive: true)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  // ── automatic saving ─────────────────────────────────────────────────────

  static final Set<String> _seen = <String>{};
  static Future<void> _queue = Future.value();

  /// Saves the media of [messages] into the folder (in the background, one
  /// at a time). Runs when a chat opens and when the inbox sees new media,
  /// so files are on the phone long before the server copy expires.
  static void autoSaveFrom(Iterable<Map<String, dynamic>> messages) {
    if (!autoSave) return;
    for (final m in messages) {
      final url = m['mediaUrl']?.toString() ?? '';
      if (!url.startsWith('http') || m['deletedForEveryone'] == true) continue;
      final type = m['type']?.toString() ?? '';
      final isVideo = type == 'video' || _videoExt.contains(_extOf(url));
      if (isVideo && !autoSaveVideos) continue;
      if (!_seen.add(url)) continue;
      _queue = _queue.then((_) => save(url)).catchError((_) => null);
    }
  }

  static String _extOf(String url) {
    final last = url.split('?').first.split('/').last;
    final dot = last.lastIndexOf('.');
    return dot > 0 ? last.substring(dot + 1).toLowerCase() : '';
  }

  /// Downloads [url] into the folder unless it is already there. Null when
  /// the server copy is gone (the Drive backup can still bring it back).
  static Future<File?> save(String url) async {
    final file = File(pathFor(url));
    try {
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
        await file.parent.create(recursive: true);
        final part = File('${file.path}.part');
        await res.stream.pipe(part.openWrite());
        await part.rename(file.path);
        announce(file.path);
        return file;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Keeps a copy of media this device just sent.
  static Future<void> keepSent(String url, List<int> bytes) async {
    try {
      final f = File(pathFor(url));
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes);
      announce(f.path);
    } catch (_) {}
  }
}
