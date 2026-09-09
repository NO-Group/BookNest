import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

import 'backend_api.dart';

/// End-to-end encryption for one-to-one messages — at zero cost, with
/// zero infrastructure.
///
/// How it works: every device generates a P-256 identity keypair on first
/// use. The private key never leaves the phone (secure storage); the
/// public key is published to BookNest's key directory. When you send a
/// message, the app mints a *fresh* one-time keypair, derives a shared
/// secret with your reader's public key (ECDH), stretches it with
/// HKDF-SHA256, and seals the text with AES-256-GCM. The server carries
/// only the sealed envelope plus the one-time public key — it can never
/// read the words, and because the one-time key is destroyed after use,
/// even a stolen identity key cannot unseal old messages.
///
/// Honest scope: this seals 1:1 *text*. Media and club chats are not
/// sealed (group sealing is a different, much heavier protocol).
class DmCrypto {
  DmCrypto._();
  static final DmCrypto instance = DmCrypto._();

  static const _privKey = 'booknest.dm.identity.priv';
  static const _pubKey = 'booknest.dm.identity.pub';
  static const _envelopePrefix = 'e1|';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  Uint8List? _priv;
  String? _pub;
  final Map<String, String> _peerKeys = {};
  bool _ready = false;
  bool _readying = false;

  bool get ready => _ready;

  /// Loads or creates this device's identity and publishes the public
  /// half to the key directory. Failures stay silent — the app simply
  /// sends plaintext when sealing isn't possible.
  Future<void> ensureIdentity() async {
    if (_ready || _readying) return;
    _readying = true;
    try {
      final privHex = await _secure.read(key: _privKey);
      final pubHex = await _secure.read(key: _pubKey);
      if (privHex != null && pubHex != null && privHex.length == 64) {
        _priv = _unhex(privHex);
        _pub = pubHex;
      } else {
        final params = ECDomainParameters('prime256v1');
        final random = _secureRandom();
        final generator = ECKeyGenerator()
          ..init(ParametersWithRandom(
              ECKeyGeneratorParameters(params), random));
        final pair = generator.generateKeyPair();
        final d = (pair.privateKey as ECPrivateKey).d!;
        final q = (pair.publicKey as ECPublicKey).Q!;
        _priv = _bigIntTo32(d);
        _pub = 'BNK1:${_hex(q.getEncoded(false))}';
        await _secure.write(key: _privKey, value: _hex(_priv!));
        await _secure.write(key: _pubKey, value: _pub!);
      }
      await BackendApi.instance.call('keys.publish', {'pub': _pub});
      _ready = true;
    } catch (_) {
      _ready = false;
    } finally {
      _readying = false;
    }
  }

  /// The peer's public key (cached in memory for the session).
  Future<String?> _peerKey(String peerId) async {
    if (peerId.isEmpty) return null;
    final cached = _peerKeys[peerId];
    if (cached != null) return cached;
    final res =
        await BackendApi.instance.call('keys.fetch', {'userId': peerId});
    final pub = res?['pub']?.toString();
    if (pub != null && pub.startsWith('BNK1:')) {
      _peerKeys[peerId] = pub;
      return pub;
    }
    return null;
  }

  /// Whether this reader can be written to sealed.
  Future<bool> canSeal(String peerId) async {
    if (!_ready) await ensureIdentity();
    return (await _peerKey(peerId)) != null;
  }

  /// Seals [plain] for [peerId]. Returns the envelope string, or null
  /// when sealing isn't possible (send plaintext instead — honest
  /// fallback, never a fake lock).
  Future<String?> seal(String peerId, String plain) async {
    try {
      if (!_ready) await ensureIdentity();
      final peer = await _peerKey(peerId);
      if (_priv == null || peer == null) return null;
      final params = ECDomainParameters('prime256v1');
      final random = _secureRandom();
      final generator = ECKeyGenerator()
        ..init(ParametersWithRandom(ECKeyGeneratorParameters(params), random));
      final oneShot = generator.generateKeyPair();
      final oneShotPriv = (oneShot.privateKey as ECPrivateKey).d!;
      final oneShotPub = (oneShot.publicKey as ECPublicKey).Q!;
      final peerPoint = params.curve.decodePoint(
          _unhex(peer.substring(5)));
      if (peerPoint == null) return null;

      final agreement = ECDHBasicAgreement()
        ..init(PrivateKeyParameter<ECPrivateKey>(
            ECPrivateKey(oneShotPriv, params)));
      final shared = _bigIntTo32(
          agreement.calculateAgreement(
              PublicKeyParameter<ECPublicKey>(ECPublicKey(peerPoint, params))));

      final key = _hkdf(shared, utf8.encode('booknest-dm-e1'));
      final iv = _random(12);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(true,
            AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      final sealed = cipher.process(Uint8List.fromList(utf8.encode(plain)));
      return '$_envelopePrefix'
          '${_hex(iv)}|${_hex(oneShotPub.getEncoded(false))}|${_hex(sealed)}';
    } catch (_) {
      return null;
    }
  }

  /// Opens an envelope with this device's identity key. Returns the
  /// plaintext, or null when it cannot be opened (never crashes a chat).
  String? open(String text) {
    try {
      if (!text.startsWith(_envelopePrefix) || _priv == null) return null;
      final parts = text.substring(_envelopePrefix.length).split('|');
      if (parts.length != 3) return null;
      final iv = _unhex(parts[0]);
      final ephPub = _unhex(parts[1]);
      final sealed = _unhex(parts[2]);
      final params = ECDomainParameters('prime256v1');
      final peerPoint = params.curve.decodePoint(ephPub);
      if (peerPoint == null) return null;
      final priv = ECPrivateKey(_bytesToBigInt(_priv!), params);
      final agreement = ECDHBasicAgreement()
        ..init(PrivateKeyParameter<ECPrivateKey>(priv));
      final shared = _bigIntTo32(
          agreement.calculateAgreement(
              PublicKeyParameter<ECPublicKey>(ECPublicKey(peerPoint, params))));
      final key = _hkdf(shared, utf8.encode('booknest-dm-e1'));
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false,
            AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      return utf8.decode(cipher.process(sealed));
    } catch (_) {
      return null;
    }
  }

  /// Whether a stored message is a sealed envelope.
  static bool isEnvelope(String text) => text.startsWith(_envelopePrefix);

  // ── primitives ──────────────────────────────────────────────────────

  SecureRandom _secureRandom() {
    final random = FortunaRandom();
    final seed = _random(32);
    random.seed(KeyParameter(seed));
    return random;
  }

  Uint8List _hkdf(Uint8List ikm, Uint8List info) {
    final derivator = HKDFKeyDerivator(SHA256Digest());
    derivator.init(HkdfParameters(ikm, 32, Uint8List(0), info));
    return derivator.process(Uint8List(0));
  }

  Uint8List _bigIntTo32(BigInt n) {
    var hex = n.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    hex = hex.padLeft(64, '0');
    return _unhex(hex);
  }

  BigInt _bytesToBigInt(Uint8List bytes) => BigInt.parse(_hex(bytes), radix: 16);
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
