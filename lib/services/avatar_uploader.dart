import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../config/app_config.dart';
import 'cloudinary_service.dart';

/// Picks an image from the gallery and uploads it to Cloudinary under
/// booknest/avatars. Returns the secure URL, or null on any failure.
/// Context-free on purpose — callers show their own messaging.
class AvatarUploader {
  AvatarUploader._();

  static Future<String?> pickAndUpload({
    required String userId,
  }) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null) return null; // user cancelled — not an error
      final bytes = await file.readAsBytes();
      final extension = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : 'jpg';
      return await CloudinaryService.uploadImage(
        bytes: bytes,
        folder: 'avatars',
        publicId: 'avatar-$userId-${DateTime.now().millisecondsSinceEpoch}',
        extension: extension,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Re-exported so screens keep a single import for uploads.
typedef UploadedBytes = Uint8List;
