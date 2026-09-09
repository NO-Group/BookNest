import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'backend_api.dart';
import 'notification_service.dart';

/// Production push, the honest way: Firebase Cloud Messaging for real
/// delivery, our edge for real sends (service-account OAuth minted in
/// the function — no keys in the app). Everything degrades silently when
/// Firebase isn't configured yet (the google-services.json step), so the
/// app never breaks, and in-app notifications keep flowing regardless.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _configured = false;
  String? _token;

  /// Whether FCM came up on this device.
  bool get available => _configured;

  @pragma('vm:entry-point')
  static Future<void> _backgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
    // Background deliveries are shown by the system tray automatically.
  }

  Future<void> warmUp() async {
    if (_configured) return;
    try {
      await Firebase.initializeApp();
      _configured = true;
    } catch (_) {
      // No google-services config yet — pushes wait for the dashboard step.
      return;
    }
    try {
      FirebaseMessaging.onBackgroundMessage(_backgroundHandler);
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
          alert: true, badge: true, sound: true);
      _token = await messaging.getToken();
      await _register(_token);
      messaging.onTokenRefresh.listen((token) async {
        _token = token;
        await _register(token);
      });
      // Foreground: the app is open — surface it as a heads-up card.
      FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        NotificationService.instance.showInstant(
          id: DateTime.now().millisecondsSinceEpoch ~/ 4,
          title: notification.title ?? 'BookNest',
          body: notification.body ?? '',
        );
      });
    } catch (_) {
      // Permission declined or services missing — honest silence.
    }
  }

  Future<void> _register(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await BackendApi.instance
          .call('push.register', {'token': token, 'platform': 'android'});
    } catch (_) {}
  }

  /// Best-effort: stop this device buzzing after account deletion.
  Future<void> tearDown() async {
    final token = _token;
    if (token == null) return;
    try {
      await BackendApi.instance.call('push.unregister', {'token': token});
    } catch (_) {}
  }

  @visibleForTesting
  void debugConfigure() => _configured = true;
}
