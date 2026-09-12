import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'config/app_state.dart';
import 'config/router.dart';
import 'presentation/screens/calls/call_screen.dart';
import 'config/theme.dart';
import 'services/home_widgets_service.dart';
import 'services/push_service.dart';
import 'services/call_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'presentation/screens/auth/suspend_gate_screen.dart';
import 'services/backend_api.dart';
import 'services/punishment_gate.dart';
import 'services/profile_layout.dart';
import 'services/inbox_watcher.dart';
import 'services/background_link.dart';
import 'services/notification_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:shared_preferences/shared_preferences.dart';
import 'services/supabase_service.dart';
import 'presentation/components/booknest_keyboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.load();
  await loadKeyboardEnabled();
  await SupabaseService().initialize();
  // Self-heal: guarantee a profiles row exists for returning users whose
  // signup predated the auto-create trigger (fixes empty chat/search results).
  if (SupabaseService().auth.currentUser != null) {
    await SupabaseService().ensureProfile();
  }
  unawaited(_startupAftercare());
  unawaited(PushService.instance.warmUp());
    // Zero-external notifications while the app is alive (no Firebase
    // needed): a light sweep of the message queue every 30 seconds.
    InboxWatcher.instance.start();
    // Calls: listen for incoming rings; the ring opens the call room
    // over whatever is on screen.
    CallService.instance.onIncoming = (session) {
      final context = rootNavigatorKey.currentContext;
      if (context != null) CallScreen.open(context);
    };
    unawaited(CallService.instance.ensureInitialized());
    unawaited(loadProfileLayout());
    unawaited(refreshPunishmentGate());
    unawaited(_checkBroadcast());
    unawaited(_syncPhoneOnce());
    // BookNest's own background link (no Google): restores the foreground
    // service when the reader keeps it enabled.
    unawaited(LinkService.instance.ensureStartedIfPreferred());
  // Port for the background-link service isolate, before anything runs.
  LinkService.instance.initCommunication();
  runApp(const BookNestApp());
}

/// Non-blocking startup extras: reminder engine, home-screen widgets, and
/// home-screen shortcut deep links. Each is independent and best-effort —
/// none of them can delay or break the app itself.
Future<void> _startupAftercare() async {
  try {
    await NotificationService.instance.init();
  } catch (_) {}

  try {
    final links = AppLinks();
    void goTo(Uri uri) {
      switch (uri.host) {
        case 'word':
        case 'search':
          appRouter.go('/dictionary');
          break;
        case 'write':
          appRouter.go('/editor');
          break;
        case 'wallet':
          appRouter.go('/wallet');
          break;
        case 'streaks':
          appRouter.go('/streaks');
          break;
        case 'feed':
          appRouter.go('/feed');
          break;
      }
    }

    final initial = await links.getInitialLink();
    if (initial != null) goTo(initial);
    links.uriLinkStream.listen(goTo, onError: (_) {});
  } catch (_) {}

  try {
    await HomeWidgetsService.pushAll();
  } catch (_) {}

  // One-time permissions primer — only ever after the reader is signed in.
  try {
    if (SupabaseService().auth.currentUser != null) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('perm_primer_done') != true) {
        await appRouter.push('/permissions');
      }
    }
  } catch (_) {}
}

/// Checks for a moderator broadcast the reader hasn't seen and greets
/// them once with it. Best-effort; silence on any hiccup.
Future<void> _checkBroadcast() async {
  try {
    final res = await BackendApi.instance.massLatest();
    final message = res?['message'];
    if (message is! Map) return;
    final id = message['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('bn_mass_seen_$id') == true) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await prefs.setBool('bn_mass_seen_$id', true);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(children: [
          const Icon(Icons.campaign_rounded, color: BookNestColors.cyan),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message['title']?.toString() ?? 'News',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ]),
        content: Text(message['body']?.toString() ?? '',
            style: const TextStyle(fontSize: 14, height: 1.45)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Got it',
                  style: TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.w800))),
        ],
      ),
    );
  } catch (_) {}
}

/// Mirrors the signup phone into the auth user record so the phone
/// column is filled in the Supabase dashboard. Runs once per install.
Future<void> _syncPhoneOnce() async {
  try {
    final user = SupabaseService().auth.currentUser;
    final phone = user?.userMetadata?['phone']?.toString() ?? '';
    if (phone.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('bn_phone_synced') == true) return;
    final res = await BackendApi.instance.syncPhone(phone);
    if (res != null) await prefs.setBool('bn_phone_synced', true);
  } catch (_) {}
}

class BookNestApp extends StatelessWidget {
  const BookNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: punishmentGate,
      builder: (context, punishment, __) {
        if (punishment != null) {
          return MaterialApp(
            title: 'BookNest',
            debugShowCheckedModeBanner: false,
            theme: BookNestTheme.lightTheme,
            darkTheme: BookNestTheme.darkTheme,
            home: SuspendGateScreen(
              mode: punishment['mode']?.toString() ?? 'ban',
              reason: punishment['reason']?.toString() ?? '',
              until: DateTime.tryParse(punishment['until']?.toString() ?? ''),
            ),
          );
        }
        return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (context, mode, _) => MaterialApp.router(
        title: 'BookNest',
        debugShowCheckedModeBanner: false,
        theme: BookNestTheme.lightTheme,
        darkTheme: BookNestTheme.darkTheme,
        themeMode: mode,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        routerConfig: appRouter,
      ),
        );
      },
    );
  }
}
