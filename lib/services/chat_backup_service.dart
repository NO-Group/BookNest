import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_api.dart';
import 'chat_store.dart';
import 'dm_crypto.dart';
import 'media_backup_service.dart';
import '../config/app_config.dart';

/// Chat backup, split the way storage costs work:
///
/// • TEXT messages → BookNest (MongoDB). The app compresses the history,
///   seals it with the reader's own passphrase (PBKDF2 → AES-256-GCM) and
///   uploads the envelope. BookNest stores ciphertext only — without the
///   passphrase nobody can open it, including BookNest. Restores on any
///   phone or PC, no Google account needed. Text is tiny (~50–300 KB).
/// • MEDIA (photos, videos, voice notes, files) → the reader's OWN Google
///   Drive ([MediaBackupService]). Never stored by BookNest beyond the
///   30-day relay on Cloudinary.
///
/// Older Google-Drive text backups and exported .bnbk files still restore.
class ChatBackupService {
  ChatBackupService._();
  static final ChatBackupService instance = ChatBackupService._();

  static const _magic = [0x42, 0x4E, 0x42, 0x4B]; // "BNBK"
  // Envelope v1 = JSON (older Drive backups), v2 = gzip(JSON).
  static const _version = 2;
  static const _driveFileName = 'booknest-chat-backup.bnbk';
  static const _maxServerBytes = 3 * 1024 * 1024;

  static const _keyCacheName = 'booknest.backup.pass.key';
  static const _saltCacheName = 'booknest.backup.pass.salt';
  static const _freqPref = 'booknest.backup.frequency';
  static const _lastAtPref = 'booknest.backup.lastAt';
  static const _lastSizePref = 'booknest.backup.lastSize';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  // ── status ──────────────────────────────────────────────────────────

  BackupFrequency get frequency {
    final raw = _prefsSync;
    return BackupFrequency.values.firstWhere(
      (f) => f.name == raw,
      orElse: () => BackupFrequency.off,
    );
  }

  // SharedPreferences has no sync getter — mirror the value on load.
  String? _prefsSync;
  Future<void> warmUp() async {
    final prefs = await SharedPreferences.getInstance();
    _prefsSync = prefs.getString(_freqPref);
  }

  Future<void> setFrequency(BackupFrequency value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_freqPref, value.name);
    _prefsSync = value.name;
  }

  Future<DateTime?> get lastBackupAt async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastAtPref);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  Future<int> get lastBackupSize async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastSizePref) ?? 0;
  }

  /// Whether the reader has set a backup passphrase on this device.
  Future<bool> get hasPassphraseKey async {
    final key = await _secure.read(key: _keyCacheName);
    final salt = await _secure.read(key: _saltCacheName);
    return key != null && salt != null;
  }

  // ── crypto: passphrase → key (PBKDF2-HMAC-SHA256) ───────────────────

  Future<({Uint8List key, Uint8List salt})> _deriveKey(
      String passphrase, Uint8List? salt) async {
    final useSalt = salt ?? _random(16);
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(useSalt, 120000, 32));
    final passBytes = utf8.encode(passphrase);
    final key = derivator.process(Uint8List.fromList(passBytes));
    return (key: Uint8List.fromList(key), salt: useSalt);
  }

  Future<void> _cacheKey(String passphrase) async {
    final derived = await _deriveKey(passphrase, null);
    await _secure.write(key: _keyCacheName, value: _hex(derived.key));
    await _secure.write(key: _saltCacheName, value: _hex(derived.salt));
  }

  Future<({Uint8List key, Uint8List salt})?> _cachedKey() async {
    final keyHex = await _secure.read(key: _keyCacheName);
    final saltHex = await _secure.read(key: _saltCacheName);
    if (keyHex == null || saltHex == null) return null;
    return (key: _unhex(keyHex), salt: _unhex(saltHex));
  }

  Future<void> forgetPassphraseKey() async {
    await _secure.delete(key: _keyCacheName);
    await _secure.delete(key: _saltCacheName);
  }

  // ── envelope: "BNBK" + ver + salt + iv + AES-GCM ────────────────────

  Uint8List _seal(Map<String, dynamic> payload, Uint8List key,
      Uint8List salt) {
    final json = gzip.encode(utf8.encode(jsonEncode(payload)));
    final iv = _random(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final sealed = cipher.process(Uint8List.fromList(json));
    final out = Uint8List(4 + 1 + 16 + 12 + sealed.length);
    var at = 0;
    out.setRange(at, at + 4, _magic);
    at += 4;
    out[at++] = _version;
    out.setRange(at, at + 16, salt);
    at += 16;
    out.setRange(at, at + 12, iv);
    at += 12;
    out.setRange(at, out.length, sealed);
    return out;
  }

  /// Opens a backup envelope. Throws [BackupPassphraseWrong] when the
  /// passphrase does not open it, [ArgumentError] when it is not a
  /// BookNest backup at all.
  Map<String, dynamic> _open(Uint8List blob, String passphrase) {
    if (blob.length < 33) throw ArgumentError('This file is not a '
        'BookNest backup — it may have been truncated.');
    for (var i = 0; i < 4; i++) {
      if (blob[i] != _magic[i]) {
        throw ArgumentError('This file is not a BookNest backup.');
      }
    }
    final salt = Uint8List.sublistView(blob, 5, 21);
    final iv = Uint8List.sublistView(blob, 21, 33);
    final sealed = Uint8List.sublistView(blob, 33);
    final derived = _deriveSync(passphrase, salt);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(derived), 128, iv,
          Uint8List(0)));
    try {
      var plain = cipher.process(sealed);
      if (blob[4] >= 2) plain = Uint8List.fromList(gzip.decode(plain));
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw ArgumentError('This backup is empty or damaged.');
    } on ArgumentError {
      rethrow;
    } catch (_) {
      throw BackupPassphraseWrong();
    }
  }

  Uint8List _deriveSync(String passphrase, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, 120000, 32));
    return Uint8List.fromList(
        derivator.process(Uint8List.fromList(utf8.encode(passphrase))));
  }

  // ── payload: text history only ──────────────────────────────────────

  /// The chats as text: messages keep their media *link* (so the media can
  /// be found again in the reader's Google Drive), never media bytes.
  Map<String, dynamic> _textChats() {
    final all = ChatStore.instance.exportAll();
    final out = <String, dynamic>{};
    all.forEach((id, chat) {
      if (chat is! Map) return;
      final messages = <Map<String, dynamic>>[];
      for (final m in (chat['messages'] as List? ?? const [])) {
        if (m is! Map) continue;
        final row = <String, dynamic>{};
        m.forEach((k, v) {
          final key = '$k';
          // Device-only fields (local file paths, upload state) stay here.
          if (key.startsWith('local') || key.startsWith('_') ||
              key == 'pending' || key == 'uploading') return;
          row[key] = v;
        });
        messages.add(row);
      }
      out[id] = {'meta': chat['meta'] ?? const {}, 'messages': messages};
    });
    return out;
  }

  Future<Map<String, dynamic>> _payload() async => {
        'app': 'BookNest',
        'version': _version,
        'appVersion': AppConfig.appVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'chats': _textChats(),
        // Lets a restored phone open end-to-end sealed messages that were
        // sealed to this phone — inside the passphrase envelope only.
        'dmKeys': await DmCrypto.instance.exportForBackup(),
      };

  static int _countMessages(Map<String, dynamic> chats) {
    var n = 0;
    for (final c in chats.values) {
      if (c is Map && c['messages'] is List) n += (c['messages'] as List).length;
    }
    return n;
  }

  // ── where backups go ────────────────────────────────────────────────

  /// Google Drive is used for MEDIA (and to restore older text backups).
  bool get driveSupported => DriveClient.instance.supported;

  Future<Map<String, String>?> _driveHeaders({bool interactive = false}) =>
      DriveClient.instance.headers(interactive: interactive);

  /// Uploads the sealed text backup to BookNest. True when stored.
  Future<bool> _uploadToServer(Uint8List blob, int messages) async {
    if (blob.length > _maxServerBytes) {
      throw BackupUnavailable('Your text backup is over 3 MB — that is a lot '
          'of history! Delete a few very old chats and try again.');
    }
    final res = await BackendApi.instance.call('backup.put', {
      'blob': base64Encode(blob),
      'messages': messages,
      'appVersion': AppConfig.appVersion,
    });
    return res?['saved'] == true;
  }

  Future<void> _remember(int size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _lastAtPref, DateTime.now().toUtc().toIso8601String());
    await prefs.setInt(_lastSizePref, size);
  }

  // ── public operations ───────────────────────────────────────────────

  /// The text backup stored with BookNest, or null when there is none (or
  /// the server can't be reached).
  Future<ServerBackupInfo?> peekServerBackup() async {
    final res = await BackendApi.instance.call('backup.status');
    if (res == null || res['exists'] != true) return null;
    return ServerBackupInfo(
      size: (res['size'] as num?)?.toInt() ?? 0,
      messages: (res['messages'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse('${res['updatedAt'] ?? ''}')?.toLocal(),
    );
  }

  /// Backs up the TEXT history now (sealed with [passphrase]) to BookNest.
  /// Returns the backup's size in bytes, or -1 when it could not complete.
  Future<int> backupNow(String passphrase) async {
    await _cacheKey(passphrase);
    return _backupWithCachedKey();
  }

  Future<int> _backupWithCachedKey() async {
    await ChatStore.instance.flush();
    final cached = await _cachedKey();
    if (cached == null) return -1;
    final payload = await _payload();
    final blob = _seal(payload, cached.key, cached.salt);
    final ok = await _uploadToServer(
        blob, _countMessages(payload['chats'] as Map<String, dynamic>));
    if (!ok) return -1;
    await _remember(blob.length);
    return blob.length;
  }

  /// Also hands the sealed text backup to the reader as a file (share
  /// sheet) — an extra copy they keep wherever they like.
  Future<int> exportCopy(String passphrase) async {
    await _cacheKey(passphrase);
    await ChatStore.instance.flush();
    final cached = await _cachedKey();
    if (cached == null) return -1;
    final blob = _seal(await _payload(), cached.key, cached.salt);
    return await _exportBlobLocally(blob) ? blob.length : -1;
  }

  Future<bool> _exportBlobLocally(Uint8List blob) async {
    try {
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/BookNest-chat-backup-${DateTime.now().millisecondsSinceEpoch}.bnbk');
      await file.writeAsBytes(blob, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Your encrypted BookNest chat backup (text) — keep it '
            'somewhere safe.',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Restores the text history from BookNest. Returns messages restored.
  Future<int> restoreFromServer(String passphrase) async {
    final res = await BackendApi.instance.call('backup.get');
    if (res == null) {
      throw BackupUnavailable('Could not reach BookNest — check your '
          'connection and try again.');
    }
    if (res['exists'] != true || res['blob'] is! String) {
      throw BackupUnavailable('No chat backup is stored for this account yet.');
    }
    return _restoreBlob(base64Decode(res['blob'] as String), passphrase);
  }

  /// Older versions backed text up to Google Drive — still restorable.
  Future<int> restoreFromDrive(String passphrase) async {
    final headers = await _driveHeaders(interactive: true);
    if (headers == null) {
      throw BackupUnavailable('Google sign-in is not available on this '
          'device — restore from BookNest or a backup file instead.');
    }
    final found = await DriveClient.instance.find(headers, _driveFileName);
    if (found == null) {
      throw BackupUnavailable('No older backup found in your Google account.');
    }
    final blob = await DriveClient.instance.downloadBytes(headers, found.id);
    if (blob == null) {
      throw BackupUnavailable('The backup could not be downloaded — try '
          'again in a moment.');
    }
    return _restoreBlob(blob, passphrase);
  }

  /// Restores from an exported .bnbk file. Returns restored message count.
  Future<int> restoreFromFile(String passphrase, String filePath) async {
    final blob = await File(filePath).readAsBytes();
    return _restoreBlob(Uint8List.fromList(blob), passphrase);
  }

  Future<int> _restoreBlob(Uint8List blob, String passphrase) async {
    final payload = _open(blob, passphrase);
    final chats = payload['chats'];
    if (chats is! Map) throw ArgumentError('This backup is empty.');
    final count = _countMessages(Map<String, dynamic>.from(chats));
    await ChatStore.instance.importAll(Map<String, dynamic>.from(chats));
    final keys = payload['dmKeys'];
    if (keys is Map) {
      await DmCrypto.instance.adoptFromBackup(Map<String, dynamic>.from(keys));
    }
    // The restored passphrase becomes this device's cache so scheduled
    // backups keep working.
    await _cacheKey(passphrase);
    return count;
  }

  /// Deletes the text backup stored with BookNest (confirm upstream!).
  Future<bool> deleteServerBackup() async {
    final res = await BackendApi.instance.call('backup.delete');
    if (res?['deleted'] != true) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastAtPref);
    await prefs.remove(_lastSizePref);
    return true;
  }

  /// The connected Google account's email (media backup), silently.
  Future<String?> connectedAccountEmail() async =>
      DriveClient.instance.email();

  /// Scheduled backups — daily/weekly/monthly, WhatsApp-style, silent:
  /// text to BookNest (only with the passphrase key already on this phone)
  /// and new media to the reader's Google Drive (only when switched on and
  /// the Google account is already connected).
  Future<void> maybeRunScheduled() async {
    await warmUp();
    final freq = frequency;
    if (freq == BackupFrequency.off) return;
    final every = switch (freq) {
      BackupFrequency.daily => const Duration(days: 1),
      BackupFrequency.weekly => const Duration(days: 7),
      BackupFrequency.monthly => const Duration(days: 30),
      BackupFrequency.off => const Duration(days: 36500),
    };
    final last = await lastBackupAt;
    if (await hasPassphraseKey &&
        (last == null || DateTime.now().difference(last) >= every)) {
      try {
        await _backupWithCachedKey();
      } catch (_) {}
    }
    try {
      await MediaBackupService.instance.maybeRunScheduled(every);
    } catch (_) {}
  }
}

// ── supporting types ────────────────────────────────────────────────────

enum BackupFrequency { off, daily, weekly, monthly }

class ServerBackupInfo {
  final int size;
  final int messages;
  final DateTime? updatedAt;
  const ServerBackupInfo(
      {required this.size, required this.messages, this.updatedAt});
}

/// The passphrase did not open this backup — exactly like WhatsApp's
/// "incorrect password" for end-to-end encrypted backups.
class BackupPassphraseWrong implements Exception {
  @override
  String toString() => 'That passphrase does not open this backup.';
}

class BackupUnavailable implements Exception {
  final String message;
  BackupUnavailable(this.message);
  @override
  String toString() => message;
}

// ── tiny helpers ────────────────────────────────────────────────────────

Uint8List _random(int length) {
  final out = Uint8List(length);
  final random = Random.secure();
  for (var i = 0; i < length; i++) {
    out[i] = random.nextInt(256);
  }
  return out;
}

String _hex(Uint8List bytes) {
  const digits = '0123456789abcdef';
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(digits[(b >> 4) & 0xF]);
    out.write(digits[b & 0xF]);
  }
  return out.toString();
}

Uint8List _unhex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
