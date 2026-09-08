import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/aes/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';

/// BookNest's WhatsApp-style chat vault.
///
/// Every conversation lives on this device as its own encrypted file —
/// AES-256-GCM, key generated on first run and kept in the phone's secure
/// storage (Android Keystore). The server only holds messages for the
/// sync window; this vault holds them forever.
class ChatStore {
  ChatStore._();
  static final ChatStore instance = ChatStore._();

  static const _magic = [0x42, 0x4E, 0x43, 0x48]; // "BNCH"
  static const _version = 1;
  static const _secureKeyName = 'booknest.chat.vault.key';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  Directory? _dir;
  Uint8List? _key;
  final Map<String, List<Map<String, dynamic>>> _mem = {};
  final Map<String, Map<String, dynamic>> _meta = {};
  final Set<String> _dirty = {};
  bool _metaDirty = false;
  Timer? _flushTimer;
  final Map<String, String> _sig = {}; // skip identical rewrites

  // ── keys & paths ────────────────────────────────────────────────────

  Future<Directory> _chatsDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/chat_vault');
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  Future<Uint8List> _vaultKey() async {
    if (_key != null) return _key!;
    final stored = await _secure.read(key: _secureKeyName);
    if (stored != null && stored.length == 64) {
      _key = Uint8List.fromList(_hexDecode(stored));
      return _key!;
    }
    // First run on this device: a fresh 256-bit key, generated locally,
    // never leaving the phone.
    final fresh = Uint8List(32);
    final random = Random.secure();
    for (var i = 0; i < 32; i++) {
      fresh[i] = random.nextInt(256);
    }
    await _secure.write(key: _secureKeyName, value: _hexEncode(fresh));
    _key = fresh;
    return fresh;
  }

  String _fileName(String conversationId) {
    final safe = conversationId.replaceAll(RegExp(r'[^a-zA-Z0-9_:-]'), '_');
    return '$safe.bnchat';
  }

  // ── crypto ──────────────────────────────────────────────────────────

  Uint8List _encryptBytes(Uint8List plain, Uint8List key) {
    final iv = Uint8List(12);
    final random = Random.secure();
    for (var i = 0; i < 12; i++) {
      iv[i] = random.nextInt(256);
    }
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AeadParameters(KeyParameter(key), 128, iv));
    final sealed = cipher.process(plain);
    final out = Uint8List(4 + 1 + 12 + sealed.length);
    out.setRange(0, 4, _magic);
    out[4] = _version;
    out.setRange(5, 17, iv);
    out.setRange(17, out.length, sealed);
    return out;
  }

  /// Throws [ArgumentError] when the envelope is not a BookNest vault file.
  Uint8List _decryptBytes(Uint8List blob, Uint8List key) {
    if (blob.length < 18) throw ArgumentError('Truncated vault file');
    for (var i = 0; i < 4; i++) {
      if (blob[i] != _magic[i]) {
        throw ArgumentError('Not a BookNest vault file');
      }
    }
    final iv = Uint8List.sublistView(blob, 5, 17);
    final sealed = Uint8List.sublistView(blob, 17);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AeadParameters(KeyParameter(key), 128, iv));
    return cipher.process(sealed);
  }

  // ── public API ──────────────────────────────────────────────────────

  /// The conversation's messages from this device (empty when none yet).
  Future<List<Map<String, dynamic>>> load(String conversationId) async {
    if (conversationId.isEmpty) return const [];
    if (_mem.containsKey(conversationId)) return _mem[conversationId]!;
    try {
      final dir = await _chatsDir();
      final file = File('${dir.path}/${_fileName(conversationId)}');
      if (!await file.exists()) {
        _mem[conversationId] = <Map<String, dynamic>>[];
        return _mem[conversationId]!;
      }
      final key = await _vaultKey();
      final plain = _decryptBytes(await file.readAsBytes(), key);
      final decoded = jsonDecode(utf8.decode(plain));
      final messages = <Map<String, dynamic>>[];
      if (decoded is Map && decoded['messages'] is List) {
        for (final row in decoded['messages'] as List) {
          if (row is Map) {
            messages.add(Map<String, dynamic>.from(row));
          }
        }
        if (decoded['meta'] is Map) {
          _meta[conversationId] =
              Map<String, dynamic>.from(decoded['meta'] as Map);
        }
      }
      _mem[conversationId] = messages;
      return messages;
    } catch (_) {
      // A corrupt file never breaks the chat — the server window still loads.
      _mem[conversationId] = <Map<String, dynamic>>[];
      return _mem[conversationId]!;
    }
  }

  /// Replaces the stored history (deduped by id, oldest first).
  Future<void> replace(
      String conversationId, List<Map<String, dynamic>> messages) async {
    if (conversationId.isEmpty) return;
    await load(conversationId);
    final merged = _dedupe(messages);
    _mem[conversationId] = merged;
    // Polling reloads land here every few seconds — only rewrite the
    // encrypted file when the history actually changed.
    final sig = merged.isEmpty
        ? '0'
        : '${merged.length}:${merged.first['id']}:${merged.last['id']}';
    if (_sig[conversationId] == sig && !_dirty.contains(conversationId)) {
      return;
    }
    _sig[conversationId] = sig;
    _dirty.add(conversationId);
    _scheduleFlush();
  }

  /// Adds one message (deduped) and schedules the encrypted write.
  Future<void> append(
      String conversationId, Map<String, dynamic> message) async {
    if (conversationId.isEmpty) return;
    await load(conversationId);
    final list = _mem[conversationId]!;
    final id = message['id']?.toString() ?? '';
    if (id.isNotEmpty && list.any((m) => m['id']?.toString() == id)) return;
    list.add(message);
    _dirty.add(conversationId);
    _scheduleFlush();
  }

  /// Remembers how to show a restored chat in the list (name, peer, kind).
  Future<void> setMeta(
      String conversationId, Map<String, dynamic> meta) async {
    if (conversationId.isEmpty) return;
    await load(conversationId);
    _meta[conversationId] = meta;
    _metaDirty = true;
    _dirty.add(conversationId);
    _scheduleFlush();
  }

  Map<String, dynamic>? meta(String conversationId) => _meta[conversationId];

  /// Moves a conversation (a DM that earned its real id after the first
  /// message) — history follows.
  Future<void> rename(String oldId, String newId) async {
    if (oldId.isEmpty || newId.isEmpty || oldId == newId) return;
    await load(oldId);
    final messages = _mem.remove(oldId);
    final meta = _meta.remove(oldId);
    _dirty.remove(oldId);
    if (messages == null) return;
    await load(newId);
    _mem[newId] = _dedupe([...(_mem[newId] ?? const []), ...messages]);
    if (meta != null) _meta[newId] = meta;
    _dirty.add(newId);
    final dir = await _chatsDir();
    final stale = File('${dir.path}/${_fileName(oldId)}');
    if (await stale.exists()) await stale.delete();
    _scheduleFlush();
  }

  /// Conversation ids this device holds (for the restored-chats section).
  Set<String> get conversationIds => Set<String>.from(_mem.keys);

  /// The newest stored message of a conversation (for previews).
  Map<String, dynamic>? lastMessage(String conversationId) {
    final list = _mem[conversationId];
    if (list == null || list.isEmpty) return null;
    return list.last;
  }

  /// Everything, for the backup payload: {conversationId: {meta, messages}}.
  Map<String, dynamic> exportAll() {
    final out = <String, dynamic>{};
    for (final entry in _mem.entries) {
      if (entry.value.isEmpty) continue;
      out[entry.key] = {
        'meta': _meta[entry.key] ?? const {},
        'messages': entry.value,
      };
    }
    return out;
  }

  /// Restores a backup payload ({conversationId: {meta, messages}}).
  Future<int> importAll(Map<String, dynamic> payload) async {
    var count = 0;
    for (final entry in payload.entries) {
      final id = entry.key;
      final value = entry.value;
      if (value is! Map) continue;
      final messages = <Map<String, dynamic>>[];
      if (value['messages'] is List) {
        for (final row in value['messages'] as List) {
          if (row is Map) messages.add(Map<String, dynamic>.from(row));
        }
      }
      if (value['meta'] is Map) {
        _meta[id] = Map<String, dynamic>.from(value['meta'] as Map);
        _metaDirty = true;
      }
      await replace(id, messages);
      count += messages.length;
    }
    await flush();
    return count;
  }

  /// Writes every pending conversation to its encrypted file now.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_dirty.isEmpty && !_metaDirty) return;
    final key = await _vaultKey();
    final dir = await _chatsDir();
    for (final id in _dirty.toList()) {
      final messages = _mem[id];
      if (messages == null) continue;
      final payload = utf8.encode(jsonEncode({
        'meta': _meta[id] ?? const {},
        'messages': messages,
      }));
      final file = File('${dir.path}/${_fileName(id)}');
      try {
        await file.writeAsBytes(_encryptBytes(
            Uint8List.fromList(payload), key), flush: true);
      } catch (_) {
        // A failed local write must never crash a chat screen.
      }
    }
    _dirty.clear();
    _metaDirty = false;
  }

  /// Forgets everything on this device (account deletion).
  Future<void> wipe() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _mem.clear();
    _meta.clear();
    _dirty.clear();
    try {
      final dir = await _chatsDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  // ── internals ───────────────────────────────────────────────────────

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(milliseconds: 900), () {
      flush();
    });
  }

  List<Map<String, dynamic>> _dedupe(List<Map<String, dynamic>> messages) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    final sorted = [...messages]..sort((a, b) {
        final at = DateTime.tryParse(a['createdAt']?.toString() ?? '');
        final bt = DateTime.tryParse(b['createdAt']?.toString() ?? '');
        if (at == null || bt == null) return 0;
        return at.compareTo(bt);
      });
    for (final m in sorted) {
      final id = m['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        if (!seen.add(id)) continue;
      }
      out.add(m);
    }
    return out;
  }
}

// ── tiny hex + timer imports live here to keep the file self-contained ──

String _hexEncode(Uint8List bytes) {
  const digits = '0123456789abcdef';
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(digits[(b >> 4) & 0xF]);
    out.write(digits[b & 0xF]);
  }
  return out.toString();
}

Uint8List _hexDecode(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
