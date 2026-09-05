import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'config/app_state.dart';
import 'config/router.dart';
import 'config/theme.dart';
import 'services/home_widgets_service.dart';
import 'services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.load();
  await SupabaseService().initialize();
  // Self-heal: guarantee a profiles row exists for returning users whose
  // signup predated the auto-create trigger (fixes empty chat/search results).
  if (SupabaseService().auth.currentUser != null) {
    await SupabaseService().ensureProfile();
  }
  unawaited(_startupAftercare());
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

class BookNestApp extends StatelessWidget {
  const BookNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (context, mode, _) => MaterialApp.router(
        title: 'BookNest',
        debugShowCheckedModeBanner: false,
        theme: BookNestTheme.lightTheme,
        darkTheme: BookNestTheme.darkTheme,
        themeMode: mode,
        routerConfig: appRouter,
      ),
    );
  }
}
