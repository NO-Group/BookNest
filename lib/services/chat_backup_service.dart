import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/aes/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_store.dart';
import '../config/app_config.dart';

/// WhatsApp-style chat backup: the whole chat vault, sealed with the
/// reader's own passphrase (PBKDF2 → AES-256-GCM — without the passphrase
/// the backup is unreadable to anyone, including BookNest), then uploaded
/// to the reader's own hidden Google Drive app folder. Android gets the
/// Drive path; every other platform gets the same encrypted file via
/// share/import so nothing depends on our servers.
class ChatBackupService {
  ChatBackupService._();
  static final ChatBackupService instance = ChatBackupService._();

  static const _magic = [0x42, 0x4E, 0x42, 0x4B]; // "BNBK"
  static const _version = 1;
  static const _driveFileName = 'booknest-chat-backup.bnbk';
  static const _driveScope = 'https://www.googleapis.com/auth/drive.appdata';

  static const _keyCacheName = 'booknest.backup.pass.key';
  static const _saltCacheName = 'booknest.backup.pass.salt';
  static const _freqPref = 'booknest.backup.frequency';
  static const _lastAtPref = 'booknest.backup.lastAt';
  static const _lastSizePref = 'booknest.backup.lastSize';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final GoogleSignIn _google = GoogleSignIn(scopes: const [_driveScope]);

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
    final json = utf8.encode(jsonEncode(payload));
    final iv = _random(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AeadParameters(KeyParameter(key), 128, iv));
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
      ..init(false, AeadParameters(KeyParameter(derived), 128, iv));
    try {
      final plain = cipher.process(sealed);
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

  // ── payload ─────────────────────────────────────────────────────────

  Map<String, dynamic> _payload() => {
        'app': 'BookNest',
        'version': _version,
        'appVersion': AppConfig.appVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'chats': ChatStore.instance.exportAll(),
      };

  // ── Google Drive (hidden app-data folder) ───────────────────────────

  bool get driveSupported => Platform.isAndroid;

  Future<GoogleSignInAccount?> _ensureGoogle({bool interactive = false}) async {
    try {
      var account = await _google.signInSilently();
      if (account == null && interactive) {
        account = await _google.signIn();
      }
      return account;
    } catch (_) {
      // Not configured / no Play services — honest failure upstream.
      return null;
    }
  }

  Future<Map<String, String>?> _driveHeaders(GoogleSignInAccount account) async {
    try {
      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null || token.isEmpty) return null;
      return {'Authorization': 'Bearer $token'};
    } catch (_) {
      return null;
    }
  }

  /// The existing backup's file id, or null.
  Future<String?> _driveFileId(Map<String, String> headers) async {
    final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        '?spaces=appDataFolder'
        '&q=${Uri.encodeQueryComponent("name='$_driveFileName'")}'
        '&fields=${Uri.encodeQueryComponent('files(id,name,size,modifiedTime)')}');
    final res = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    final files = body is Map && body['files'] is List
        ? body['files'] as List
        : const [];
    if (files.isEmpty) return null;
    final first = files.first;
    return first is Map ? first['id']?.toString() : null;
  }

  Future<bool> _driveUpload(
      Map<String, String> headers, Uint8List blob, String? existingId) async {
    try {
      if (existingId != null) {
        final uri = Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files/$existingId'
            '?uploadType=media');
        final res = await http
            .patch(uri,
                headers: {
                  ...headers,
                  'Content-Type': 'application/octet-stream',
                },
                body: blob)
            .timeout(const Duration(seconds: 120));
        return res.statusCode == 200;
      }
      // First backup: create the file inside the hidden app folder.
      final boundary = 'booknest_${DateTime.now().millisecondsSinceEpoch}';
      final metadata = jsonEncode({
        'name': _driveFileName,
        'parents': ['appDataFolder'],
      });
      final body = [
        '--$boundary',
        'Content-Type: application/json; charset=UTF-8',
        '',
        metadata,
        '--$boundary',
        'Content-Type: application/octet-stream',
        'Content-Transfer-Encoding: binary',
        '',
        '',
      ].join('\r\n');
      final request = http.Request(
        'POST',
        Uri.parse('https://www.googleapis.com/upload/drive/v3/files'
            '?uploadType=multipart'),
      );
      request.headers.addAll({
        ...headers,
        'Content-Type': 'multipart/related; boundary=$boundary',
      });
      request.bodyBytes = Uint8List.fromList([
        ...utf8.encode(body),
        ...blob,
        ...utf8.encode('\r\n--$boundary--'),
      ]);
      final res =
          await request.send().timeout(const Duration(seconds: 120));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List?> _driveDownload(
      Map<String, String> headers, String fileId) async {
    try {
      final uri = Uri.parse(
          'https://www.googleapis.com/drive/v3/files/$fileId?alt=media');
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 120));
      if (res.statusCode != 200) return null;
      return Uint8List.fromList(res.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _driveDelete(Map<String, String> headers, String fileId) async {
    try {
      final uri =
          Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId');
      final res = await http
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 20));
      return res.statusCode == 204 || res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── public operations ───────────────────────────────────────────────

  /// Whether a Google backup exists (silent sign-in only — no prompts).
  Future<DriveBackupInfo?> peekDriveBackup({bool interactive = false}) async {
    if (!driveSupported) return null;
    final account = await _ensureGoogle(interactive: interactive);
    if (account == null) return null;
    final headers = await _driveHeaders(account);
    if (headers == null) return null;
    final id = await _driveFileId(headers);
    if (id == null) return null;
    return DriveBackupInfo(fileId: id, email: account.email);
  }

  /// Runs a backup now with the given passphrase. Returns the backup's
  /// size in bytes, or -1 when something could not complete.
  Future<int> backupNow(String passphrase) async {
    await _cacheKey(passphrase);
    await ChatStore.instance.flush();
    final cached = await _cachedKey();
    if (cached == null) return -1;
    final blob = _seal(_payload(), cached.key, cached.salt);

    if (driveSupported) {
      final account = await _ensureGoogle(interactive: true);
      if (account == null) return -1;
      final headers = await _driveHeaders(account);
      if (headers == null) return -1;
      final existing = await _driveFileId(headers);
      final ok = await _driveUpload(headers, blob, existing);
      if (!ok) return -1;
    } else {
      // Non-Android: hand the encrypted file to the reader (share sheet —
      // they can park it in iCloud/Drive/Files themselves).
      final ok = await _exportBlobLocally(blob);
      if (!ok) return -1;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _lastAtPref, DateTime.now().toUtc().toIso8601String());
    await prefs.setInt(_lastSizePref, blob.length);
    return blob.length;
  }

  Future<bool> _exportBlobLocally(Uint8List blob) async {
    try {
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/BookNest-chat-backup-${DateTime.now().millisecondsSinceEpoch}.bnbk');
      await file.writeAsBytes(blob, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Your encrypted BookNest chat backup — keep it somewhere '
            'safe (Google Drive, iCloud, anywhere you trust).',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Restores from Google Drive. Returns the number of messages restored.
  Future<int> restoreFromDrive(String passphrase) async {
    final account = await _ensureGoogle(interactive: true);
    if (account == null) throw BackupUnavailable('Google sign-in is not '
        'available on this phone — restore from a backup file instead.');
    final headers = await _driveHeaders(account);
    if (headers == null) {
      throw BackupUnavailable('Could not reach your Google Drive — check '
          'your connection and try again.');
    }
    final id = await _driveFileId(headers);
    if (id == null) {
      throw BackupUnavailable('No backup found in your Google account yet.');
    }
    final blob = await _driveDownload(headers, id);
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
    var count = 0;
    for (final entry in chats.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final messages = value['messages'];
      if (messages is List) count += messages.length;
    }
    await ChatStore.instance.importAll(Map<String, dynamic>.from(chats));
    // The restored passphrase becomes this device's cache so scheduled
    // backups keep working.
    await _cacheKey(passphrase);
    return count;
  }

  /// Deletes the Google Drive backup (confirm upstream!).
  Future<bool> deleteDriveBackup() async {
    final account = await _ensureGoogle(interactive: true);
    if (account == null) return false;
    final headers = await _driveHeaders(account);
    if (headers == null) return false;
    final id = await _driveFileId(headers);
    if (id == null) return true;
    return _driveDelete(headers, id);
  }

  /// The signed-in Google account's email, when one is available silently.
  Future<String?> connectedAccountEmail() async {
    if (!driveSupported) return null;
    final account = await _ensureGoogle();
    return account?.email;
  }

  /// Silent scheduled backup — daily/weekly/monthly, WhatsApp-style.
  Future<void> maybeRunScheduled() async {
    await warmUp();
    final freq = frequency;
    if (freq == BackupFrequency.off) return;
    if (!await hasPassphraseKey) return;
    final last = await lastBackupAt;
    final due = switch (freq) {
      BackupFrequency.daily =>
        last == null || DateTime.now().difference(last) >= const Duration(days: 1),
      BackupFrequency.weekly =>
        last == null || DateTime.now().difference(last) >= const Duration(days: 7),
      BackupFrequency.monthly =>
        last == null || DateTime.now().difference(last) >= const Duration(days: 30),
      BackupFrequency.off => false,
    };
    if (!due) return;
    final cached = await _cachedKey();
    if (cached == null) return; // never prompt silently
    await ChatStore.instance.flush();
    final blob = _seal(_payload(), cached.key, cached.salt);
    if (!driveSupported) return;
    final account = await _ensureGoogle();
    if (account == null) return;
    final headers = await _driveHeaders(account);
    if (headers == null) return;
    final existing = await _driveFileId(headers);
    final ok = await _driveUpload(headers, blob, existing);
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _lastAtPref, DateTime.now().toUtc().toIso8601String());
      await prefs.setInt(_lastSizePref, blob.length);
    }
  }
}

// ── supporting types ────────────────────────────────────────────────────

enum BackupFrequency { off, daily, weekly, monthly }

class DriveBackupInfo {
  final String fileId;
  final String email;
  const DriveBackupInfo({required this.fileId, required this.email});
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
