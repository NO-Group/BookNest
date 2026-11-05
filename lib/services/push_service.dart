import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/router.dart';
import 'backend_api.dart';
import 'supabase_service.dart';

/// Push notifications (Android, Firebase Cloud Messaging).
///
/// Firebase lives on the native side (android/app: MainActivity +
/// BookNestMessagingService), so the PC builds carry no Firebase SDK. This
/// class registers the device token with our server, opens the right
/// screen when a notification is tapped, and removes the token on sign-out.
/// When the Android build has no google-services.json, everything here
/// quietly does nothing and the in-app watcher keeps delivering alerts.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const MethodChannel _channel = MethodChannel('booknest/push');
  static const String _prefKey = 'bn.push.registered';

  bool _configured = false;
  String? _token;
  bool _handlerSet = false;
  StreamSubscription<dynamic>? _authSub;

  /// Push kept its old name for compatibility. In-app delivery is
  /// always available.
  bool get available => _configured;

  /// True when this device receives push from the server (token
  /// registered). The in-app watcher then leaves background alerts to push.
  bool get active => _token != null;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<void> warmUp() async {
    _configured = true;
    if (!_supported) return;
    _setHandler();
    // Register again whenever someone signs in.
    _authSub ??= SupabaseService().auth.onAuthStateChange.listen((event) {
      if (event.session != null) unawaited(_register());
    });
    await _register();
    try {
      final initial = await _channel.invokeMethod<String>('initialRoute');
      if (initial != null && initial.isNotEmpty) _open(initial);
    } catch (_) {}
  }

  void _setHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) {
        _open(call.arguments as String);
      }
      return null;
    });
  }

  void _open(String route) {
    if (!route.startsWith('/')) return;
    unawaited(_openWhenReady(route));
  }

  /// A tap that cold-started the app lands on the splash screen, which
  /// then navigates on its own — wait until we're past splash / sign-in so
  /// the chat isn't replaced (gives up after ~20 s).
  Future<void> _openWhenReady(String route) async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      String path;
      try {
        path = appRouter.routerDelegate.currentConfiguration.uri.path;
      } catch (_) {
        continue;
      }
      const waiting = ['/splash', '/login', '/register', '/profile-setup', '/onboarding'];
      if (path.isEmpty || waiting.any(path.startsWith)) continue;
      if (SupabaseService().auth.currentUser == null) continue;
      try {
        appRouter.push(route);
      } catch (_) {}
      return;
    }
  }

  Future<void> _register() async {
    try {
      final uid = SupabaseService().auth.currentUser?.id;
      if (uid == null) return;
      final ready = await _channel.invokeMethod<bool>('available') ?? false;
      if (!ready) return;
      final token = await _channel.invokeMethod<String>('token');
      if (token == null || token.isEmpty) return;
      // Re-register at most once a day per account and token (the server
      // upserts, so this only saves requests).
      final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final stamp = '$uid|$token|$day';
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_prefKey) == stamp) {
        _token = token;
        return;
      }
      final res = await BackendApi.instance.call(
          'push.register', <String, dynamic>{'token': token, 'platform': 'android'});
      if (res != null) {
        _token = token;
        await prefs.setString(_prefKey, stamp);
      }
    } catch (_) {
      // Push is a courtesy — the in-app watcher still works.
    }
  }

  /// Sign-out / account deletion: this device stops receiving pushes.
  Future<void> tearDown() async {
    final token = _token;
    _token = null;
    if (!_supported) return;
    try {
      if (token != null) {
        await BackendApi.instance
            .call('push.unregister', <String, dynamic>{'token': token});
      }
      await _channel.invokeMethod<bool>('deleteToken');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
  }

  @visibleForTesting
  void debugConfigure() => _configured = true;
}
