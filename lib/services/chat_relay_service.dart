import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'backend_api.dart';
import 'media_backup_service.dart' show mediaCachePath;

/// Chat files — documents, PDFs, videos and voice notes — travel through a
/// PRIVATE Cloudflare R2 folder and are deleted from it after 3 days.
/// Cloudinary keeps images only (chat photos, for 30 days).
///
/// The sender uploads straight to R2 with a 15-minute signed link from the
/// server (`relay.sign`); the message carries a signed download link that
/// expires together with the file. Receivers download the file when they
/// open the chat (small files automatically), after which it lives on
/// their device and — with media backup on — in their own Google Drive.
class ChatRelay {
  ChatRelay._();

  static const int maxBytes = 150 * 1024 * 1024;
  static const int days = 3;

  /// Why the last [upload] failed (shown to the reader), or null.
  static String? lastError;

  static bool isRelayUrl(String url) =>
      url.contains('.r2.cloudflarestorage.com/') && url.contains('/relay/');

  static String mimeFor(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    const map = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'rtf': 'application/rtf',
      'epub': 'application/epub+zip',
      'zip': 'application/zip',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'm4v': 'video/mp4',
      'webm': 'video/webm',
      '3gp': 'video/3gpp',
      'mkv': 'video/x-matroska',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'opus': 'audio/ogg',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  /// Uploads a chat file and returns its (signed, 3-day) download link, or
  /// null with [lastError] set.
  static Future<String?> upload(Uint8List bytes, String filename) async {
    lastError = null;
    if (bytes.isEmpty) {
      lastError = 'The file is empty.';
      return null;
    }
    if (bytes.length > maxBytes) {
      lastError = 'Files up to ${maxBytes ~/ (1024 * 1024)} MB can be sent.';
      return null;
    }
    final signed = await BackendApi.instance
        .call('relay.sign', {'name': filename, 'size': bytes.length});
    final putUrl = signed?['putUrl']?.toString();
    final getUrl = signed?['getUrl']?.toString();
    if (putUrl == null || getUrl == null) {
      lastError = 'File sharing is unavailable right now — please try again.';
      return null;
    }
    final timeout = Duration(seconds: 60 + bytes.length ~/ (48 * 1024));
    try {
      var res = await http
          .put(Uri.parse(putUrl),
              headers: {'Content-Type': mimeFor(filename)}, body: bytes)
          .timeout(timeout);
      if (res.statusCode == 403) {
        // Some S3 front-ends insist every header is signed — plain retry.
        res = await http.put(Uri.parse(putUrl), body: bytes).timeout(timeout);
      }
      if (res.statusCode == 200) {
        // The sender already has the file: keep it in the shared media
        // cache so it never downloads again and joins the Drive backup.
        try {
          final f = File(mediaCachePath(getUrl));
          await f.parent.create(recursive: true);
          await f.writeAsBytes(bytes);
        } catch (_) {}
        return getUrl;
      }
      lastError = 'The upload was refused (HTTP ${res.statusCode}) — '
          'please try again.';
    } on TimeoutException {
      lastError = 'The upload took too long — check your connection.';
    } catch (_) {
      lastError = 'The upload did not finish — check your connection.';
    }
    return null;
  }

  static final Set<String> _seen = <String>{};
  static Future<void> _queue = Future.value();

  /// Downloads relay files from [messages] onto this device before their
  /// 3 days run out: voice notes and documents up to 40 MB, videos up to
  /// 25 MB (bigger videos download when opened, or with the Drive backup).
  static void prefetch(Iterable<Map<String, dynamic>> messages) {
    for (final m in messages) {
      final url = m['mediaUrl']?.toString() ?? '';
      if (!isRelayUrl(url) || !_seen.add(url)) continue;
      if (m['deletedForEveryone'] == true) continue;
      final size = (m['fileSize'] as num?)?.toInt() ?? 0;
      final video = m['type']?.toString() == 'video';
      if (size > (video ? 25 : 40) * 1024 * 1024) continue;
      _queue = _queue.then((_) => download(url)).catchError((_) => null);
    }
  }

  /// Gets one relay file into the media cache. Null once it has expired.
  static Future<File?> download(String url) async {
    final file = File(mediaCachePath(url));
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
        return file;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }
}
