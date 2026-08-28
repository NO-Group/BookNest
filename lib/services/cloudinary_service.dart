import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Unsigned Cloudinary uploads for all BookNest images:
/// book covers, profile avatars, profile covers, feed & chat images.
///
/// Uses only public-by-design values from [AppConfig] (cloud name + unsigned
/// upload preset). That combination can only UPLOAD — it can never list,
/// modify, or delete your media library. Anything stronger (transformations
/// management, bulk admin, deletion) belongs to Edge Function secrets.
///
/// Cloudinary resizes/compresses on the fly via URL transforms, and the
/// Flutter app already caches returned URLs with cached_network_image —
/// matching the blueprint's client-side caching requirements.
class CloudinaryService {
  CloudinaryService._();

  static const String _base = 'https://api.cloudinary.com/v1_1';

  /// Uploads [bytes] and returns the optimized `secure_url`, or null on any
  /// failure (offline, preset misconfigured, rejected file).
  ///
  /// [folder] is appended under the preset's asset folder, e.g.
  /// 'covers', 'avatars', 'feed' → booknest/covers/...
  static Future<String?> uploadImage({
    required Uint8List bytes,
    required String folder,
    String? publicId,
    String extension = 'png',
  }) async {
    final uri = Uri.parse('$_base/${AppConfig.cloudinaryCloudName}/image/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = AppConfig.cloudinaryUploadPreset
      ..fields['folder'] = '${AppConfig.cloudinaryBaseFolder}/$folder';
    if (publicId != null && publicId.trim().isNotEmpty) {
      request.fields['public_id'] = publicId.trim();
    }
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: '${publicId?.trim().isNotEmpty == true ? publicId!.trim() : 'upload'}.$extension',
    ));
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final body = jsonDecode(await streamed.stream.bytesToString())
          as Map<String, dynamic>;
      if (streamed.statusCode == 200 && body['secure_url'] is String) {
        return body['secure_url'] as String;
      }
      if (kDebugMode) {
        debugPrint('Cloudinary upload failed: '
            '${body['error'] is Map ? (body['error'] as Map)['message'] : 'HTTP ${streamed.statusCode}'}');
      }
      return null;
    } catch (error) {
      if (kDebugMode) debugPrint('Cloudinary upload unavailable: $error');
      return null;
    }
  }

  /// Helper for on-the-fly resized thumbnails (Cloudinary transformation):
  /// transformUrl(url, width: 320) where url is a secure_url from uploadImage.
  static String transformUrl(String url, {int? width, int? height}) {
    final marker = '/upload/';
    final index = url.indexOf(marker);
    if (index == -1) return url;
    final transforms = <String>[
      'f_auto',
      'q_auto',
      if (width != null) 'w_$width',
      if (height != null) 'h_$height',
      if (width != null || height != null) 'c_fill',
    ].join(',');
    return url.replaceFirst(marker, '/upload/$transforms/');
  }
}
