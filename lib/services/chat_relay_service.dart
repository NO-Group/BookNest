import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'backend_api.dart';
import 'media_backup_service.dart' show mediaCachePath;
import 'media_storage.dart';

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
        await MediaStorage.keepSent(getUrl, bytes);
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

  /// Saves relay files from [messages] to the BookNest media folder before
  /// their 3 days run out (see MediaStorage.autoSaveFrom).
  static void prefetch(Iterable<Map<String, dynamic>> messages) =>
      MediaStorage.autoSaveFrom(messages);

  /// Gets one relay file into the media folder. Null once it has expired.
  static Future<File?> download(String url) {
    mediaCachePath(url); // moves an older temp copy over, if any
    return MediaStorage.save(url);
  }
}
