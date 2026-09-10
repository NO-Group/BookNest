import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'backend_api.dart';
import 'supabase_service.dart';

/// BookNest's own background link — notifications with zero external
/// services. A slim foreground service keeps the process alive while other
/// apps run, and its task isolate sweeps the message queue directly against
/// our edge function using a revocable 30-day "link pass" (a capability
/// token — never the user's session, so rotation can never break sign-in).
///
/// Ownership contract between the two isolates:
/// · The app's InboxWatcher (main isolate) banners messages while the app
///   is alive — open or in recents. It pings the service on every sweep.
/// · When the app is swiped away, the pings stop; after 90 seconds of
///   silence the service isolate takes over and surfaces messages on the
///   persistent "BookNest is connected" notification itself.
class LinkService {
  LinkService._();
  static final LinkService instance = LinkService._();

  static const String _prefKey = 'bn.background.link';
  static const String _dataPass = 'bn.link.pass';
  static const String _dataMe = 'bn.link.me';

  bool _preferred = false;
  bool _started = false;
  bool _initialized = false;

  /// Whether the reader asked for the background link.
  bool get preferred => _preferred;

  /// Whether the service isolate is actually running.
  bool get running => _started;

  /// Wakes the port used to talk to the service isolate. Call once from
  /// main(), before runApp.
  void initCommunication() {
    FlutterForegroundTask.initCommunicationPort();
  }

  /// Restores the link on app start when the reader prefers it on.
  Future<void> ensureStartedIfPreferred() async {
    try {
      if (!Platform.isAndroid) return;
      final prefs = await SharedPreferences.getInstance();
      _preferred = prefs.getBool(_prefKey) ?? false;
      if (!_preferred) return;
      if (SupabaseService().auth.currentUser == null) return;
      await _provisionPass();
      await _initService();
      _started = await _startService();
    } catch (_) {
      // The link is a courtesy; never let it disturb startup.
    }
  }

  /// Flips the Settings toggle. The battery-optimization dialog shows at
  /// most when the system still plans to kill our link.
  Future<bool> setEnabled(bool on) async {
    try {
      if (!Platform.isAndroid) return false;
      _preferred = on;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, on);
      if (on) {
        if (SupabaseService().auth.currentUser != null) {
          // Android 13+ banner permission, then the battery-optimization
          // exemption — the OS only honors the link reliably with both.
          try {
            final permission =
                await FlutterForegroundTask.checkNotificationPermission();
            if (permission != NotificationPermission.granted) {
              await FlutterForegroundTask.requestNotificationPermission();
            }
          } catch (_) {}
          try {
            if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
              await FlutterForegroundTask.requestIgnoreBatteryOptimization();
            }
          } catch (_) {}
          await _provisionPass();
          await _initService();
          _started = await _startService();
        }
      } else {
        _started = false;
        try {
          await FlutterForegroundTask.stopService();
        } catch (_) {}
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Poked by the InboxWatcher on every sweep — proves the main isolate is
  /// alive, so the service stays quiet and lets it own the banners.
  void ping() {
    if (!_started) return;
    try {
      FlutterForegroundTask.sendDataToTask(
        <String, dynamic>{
          'ping': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } catch (_) {}
  }

  /// Exchanges the signed-in reader's pass with the service isolate via
  /// the plugin's own data store (works on both isolates by design).
  Future<void> _provisionPass() async {
    final res = await BackendApi.instance.call('link.pass');
    final pass = res?['pass']?.toString() ?? '';
    if (pass.isEmpty) return;
    await FlutterForegroundTask.saveData(key: _dataPass, value: pass);
    await FlutterForegroundTask.saveData(
      key: _dataMe,
      value: SupabaseService().auth.currentUser?.id ?? '',
    );
  }

  void _initService() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'bn_link',
        channelName: 'BookNest Link',
        channelDescription:
            'Keeps BookNest connected for new messages — no Google services',
        onlyAlertOnce: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(45000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
      ),
    );
  }

  Future<bool> _startService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) return true;
      await FlutterForegroundTask.startService(
        serviceId: 771,
        notificationTitle: 'BookNest is connected',
        notificationText: 'Watching for new messages — no Google services',
        notificationInitialRoute: '/',
        serviceTypes: [ForegroundServiceTypes.remoteMessaging],
        callback: linkCallback,
      );
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }
}

/// The task isolate entry point. Must be top-level and annotated.
@pragma('vm:entry-point')
void linkCallback() {
  FlutterForegroundTask.setTaskHandler(LinkTaskHandler());
}

class LinkTaskHandler extends TaskHandler {
  static const int _mainSilenceSeconds = 90;

  DateTime _lastPingAt = DateTime.now();
  bool _primed = false;
  String _me = '';
  final Map<String, String> _seen = {}; // convId -> 'sender|text'
  final Map<String, String> _names = {}; // userId -> display name

  bool get _mainAlive =>
      DateTime.now().difference(_lastPingAt).inSeconds <
      _mainSilenceSeconds;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      final me = await FlutterForegroundTask.getData(key: 'bn.link.me');
      _me = me?.toString() ?? '';
    } catch (_) {}
    await _sweep();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _sweep();
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map && data['ping'] != null) {
      _lastPingAt = DateTime.now();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  Future<void> _sweep() async {
    try {
      String? pass;
      try {
        final stored = await FlutterForegroundTask.getData(
            key: 'bn.link.pass');
        pass = stored?.toString();
      } catch (_) {}
      if (pass == null || pass.isEmpty) return;

      var latestTitle = '';
      var latestBody = '';
      var fresh = 0;

      final dms = await _callEdge('dm.list', pass);
      final conversations = dms?['conversations'];
      if (conversations is List) {
        for (final row in conversations) {
          if (row is! Map) continue;
          final conv = Map<String, dynamic>.from(row);
          final last = conv['lastMessage'];
          final sender = last is Map ? last['senderId']?.toString() ?? '' : '';
          final text = last is Map ? last['text']?.toString() ?? '' : '';
          final id = conv['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          final known = _seen['dm:$id'];
          _seen['dm:$id'] = '$sender|$text';
          if (!_primed ||
              known == null ||
              known == '$sender|$text' ||
              sender.isEmpty ||
              sender == _me) {
            continue;
          }
          fresh++;
          final name = await _nameOf(conv['peerId']?.toString() ?? '', pass);
          latestTitle = name.isEmpty ? 'New message' : name;
          latestBody = _preview(text);
        }
      }

      final rooms = await _callEdge('chats.list', pass);
      final roomRows = rooms?['rooms'];
      if (roomRows is List) {
        for (final row in roomRows) {
          if (row is! Map) continue;
          final room = Map<String, dynamic>.from(row);
          final last = room['lastMessage'];
          final sender = last is Map ? last['senderId']?.toString() ?? '' : '';
          final text = last is Map ? last['text']?.toString() ?? '' : '';
          final id = room['conversationId']?.toString() ?? '';
          if (id.isEmpty) continue;
          final known = _seen['club:$id'];
          _seen['club:$id'] = '$sender|$text';
          if (!_primed ||
              known == null ||
              known == '$sender|$text' ||
              sender.isEmpty ||
              sender == _me) {
            continue;
          }
          fresh++;
          latestTitle = room['title']?.toString().isNotEmpty == true
              ? room['title'].toString()
              : 'Group chat';
          latestBody = _preview(text);
        }
      }

      if (fresh > 0 && !_mainAlive) {
        final body = fresh > 1 ? '$fresh new messages · $latestBody' : latestBody;
        try {
          await FlutterForegroundTask.updateService(
            notificationTitle: fresh > 1 ? 'BookNest · 💬 $fresh' : latestTitle,
            notificationText: body,
          );
        } catch (_) {}
      }
      _primed = true;
    } catch (_) {
      // The link never crashes; the next tick tries again.
    }
  }

  Future<String> _nameOf(String peerId, String pass) async {
    if (peerId.isEmpty) return '';
    final cached = _names[peerId];
    if (cached != null) return cached;
    try {
      final res = await _callEdge('link.names', pass, ids: [peerId]);
      final names = res?['names'];
      if (names is Map) {
        final name = names[peerId]?.toString() ?? '';
        _names[peerId] = name;
        return name;
      }
    } catch (_) {}
    return '';
  }

  String _preview(String text) {
    if (text.startsWith('e1|')) return '🔒 Encrypted message';
    final clean = text.trim();
    if (clean.isEmpty) return 'Sent a message';
    return clean.length > 80 ? '${clean.substring(0, 77)}…' : clean;
  }

  /// Speaks to the edge function with plain dart:io — no plugins needed in
  /// this isolate. The link pass stands in for the user's session.
  Future<Map<String, dynamic>?> _callEdge(String action, String pass,
      {List<String> ids = const []}) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);
      final request = await client.postUrl(Uri.parse(
          '${AppConfig.supabaseUrl}/functions/v1/${AppConfig.edgeFunctionName}'));
      request.headers.set('apikey', AppConfig.supabaseAnonKey);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      final payload = <String, dynamic>{'linkPass': pass};
      if (ids.isNotEmpty) payload['ids'] = ids;
      request.add(utf8.encode(jsonEncode(
          <String, dynamic>{'action': action, 'payload': payload})));
      final response = await request.close();
      final body =
          await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['ok'] == true && decoded['data'] is Map) {
        return Map<String, dynamic>.from(decoded['data'] as Map);
      }
    } catch (_) {
      return null;
    } finally {
      client?.close();
    }
    return null;
  }
}
