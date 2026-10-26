import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' show SHA256Digest;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

/// Google sign-in for the PC app (Windows, macOS, Linux), where the
/// google_sign_in plugin does not run. Standard "installed app" OAuth:
/// the browser opens Google's consent page, Google redirects to a one-time
/// listener on 127.0.0.1, and the code is exchanged with PKCE. Only the
/// Drive app-folder scope is requested. The refresh token stays in the OS
/// keychain, so later backups run silently.
///
/// Needs a "Desktop app" OAuth client from Google Cloud, built in by CI
/// from GitHub secrets GOOGLE_DESKTOP_CLIENT_ID / GOOGLE_DESKTOP_CLIENT_SECRET.
/// (Google treats desktop client secrets as public by design.)
class DesktopGoogleAuth {
  DesktopGoogleAuth._();
  static final DesktopGoogleAuth instance = DesktopGoogleAuth._();

  static const _refreshKey = 'booknest.google.desktop.refresh';
  static const _emailKey = 'booknest.google.desktop.email';
  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _secure = FlutterSecureStorage();

  String? _access;
  DateTime _expires = DateTime(2000);
  Future<String?>? _signingIn;

  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  bool get configured =>
      isDesktop && AppConfig.googleDesktopClientId.isNotEmpty;

  Future<String?> _read(String key) async {
    try {
      final v = await _secure.read(key: key);
      if (v != null) return v;
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    return p.getString(key);
  }

  Future<void> _write(String key, String? value) async {
    var stored = false;
    try {
      if (value == null) {
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
      stored = true;
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    // Keychain unavailable (e.g. Linux without libsecret): app prefs.
    if (value == null || !stored) {
      if (value == null) {
        await p.remove(key);
      } else {
        await p.setString(key, value);
      }
    }
  }

  /// The connected Google account's email, or null.
  Future<String?> email() async {
    if (!configured) return null;
    final refresh = await _read(_refreshKey);
    if (refresh == null || refresh.isEmpty) return null;
    return _read(_emailKey);
  }

  /// A valid access token. [interactive] may open the browser for consent.
  Future<String?> accessToken({bool interactive = false}) async {
    if (!configured) return null;
    if (_access != null && DateTime.now().isBefore(_expires)) return _access;
    final refresh = await _read(_refreshKey);
    if (refresh != null && refresh.isNotEmpty) {
      final t = await _token(
          {'grant_type': 'refresh_token', 'refresh_token': refresh});
      if (t != null) return t;
    }
    if (!interactive) return null;
    return _signingIn ??= _interactive().whenComplete(() => _signingIn = null);
  }

  Future<String?> _token(Map<String, String> form) async {
    try {
      final res = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'client_id': AppConfig.googleDesktopClientId,
          if (AppConfig.googleDesktopClientSecret.isNotEmpty)
            'client_secret': AppConfig.googleDesktopClientSecret,
          ...form,
        },
      ).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) {
        // A revoked/expired refresh token: forget it (next time asks again).
        if (form['grant_type'] == 'refresh_token' &&
            (res.statusCode == 400 || res.statusCode == 401)) {
          await _write(_refreshKey, null);
        }
        return null;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final access = j['access_token'] as String?;
      if (access == null || access.isEmpty) return null;
      _access = access;
      final secs = (j['expires_in'] as num?)?.toInt() ?? 3600;
      _expires = DateTime.now().add(Duration(seconds: max(60, secs - 120)));
      final refresh = j['refresh_token'] as String?;
      if (refresh != null && refresh.isNotEmpty) {
        await _write(_refreshKey, refresh);
      }
      final idToken = j['id_token'] as String?;
      if (idToken != null) {
        try {
          final part = idToken.split('.')[1];
          final claims = jsonDecode(
                  utf8.decode(base64Url.decode(base64Url.normalize(part))))
              as Map<String, dynamic>;
          final mail = claims['email']?.toString();
          if (mail != null && mail.isNotEmpty) await _write(_emailKey, mail);
        } catch (_) {}
      }
      return _access;
    } catch (_) {
      return null;
    }
  }

  static String _random(int bytes) {
    final r = Random.secure();
    return base64Url
        .encode(List<int>.generate(bytes, (_) => r.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<String?> _interactive() async {
    HttpServer? server;
    StreamSubscription<HttpRequest>? sub;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirect = 'http://127.0.0.1:${server.port}';
      final verifier = _random(48);
      final challenge = base64Url
          .encode(SHA256Digest()
              .process(Uint8List.fromList(utf8.encode(verifier))))
          .replaceAll('=', '');
      final state = _random(16);
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': AppConfig.googleDesktopClientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': '$_scope openid email',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
        'state': state,
      });
      final reply = Completer<Map<String, String>>();
      sub = server.listen((req) async {
        final q = req.uri.queryParameters;
        if (!q.containsKey('code') && !q.containsKey('error')) {
          req.response.statusCode = 404; // favicon and friends
          await req.response.close();
          return;
        }
        final good = q['state'] == state && (q['code'] ?? '').isNotEmpty;
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('<!doctype html><html><head><meta charset="utf-8">'
              '<title>BookNest</title></head><body style="font-family:'
              'system-ui,sans-serif;text-align:center;padding-top:80px;'
              'background:#0b1a2e;color:#fff"><h2>'
              '${good ? 'BookNest is connected to your Google Drive' : 'Google sign-in was cancelled'}'
              '</h2><p>You can close this tab and go back to BookNest.</p>'
              '</body></html>');
        await req.response.close();
        if (!reply.isCompleted) reply.complete(q);
      });
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        return null;
      }
      final q = await reply.future.timeout(const Duration(minutes: 5));
      if (q['state'] != state || (q['code'] ?? '').isEmpty) return null;
      return _token({
        'grant_type': 'authorization_code',
        'code': q['code']!,
        'redirect_uri': redirect,
        'code_verifier': verifier,
      });
    } catch (_) {
      return null;
    } finally {
      await sub?.cancel();
      await server?.close(force: true);
    }
  }

  /// Disconnects Google on this PC (revokes the token, forgets it).
  Future<void> signOut() async {
    final refresh = await _read(_refreshKey);
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await http.post(Uri.parse('https://oauth2.googleapis.com/revoke'),
            body: {'token': refresh}).timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    _access = null;
    await _write(_refreshKey, null);
    await _write(_emailKey, null);
  }
}
