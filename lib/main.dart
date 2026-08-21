import 'package:flutter/material.dart';

import 'config/router.dart';
import 'config/theme.dart';
import 'config/theme_controller.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService().initialize();
  await themeController.load();

  // Keep the router in sync with auth changes (sign-in, sign-out, session
  // restore/refresh/expiry). `Supabase.initialize()` restores the persisted
  // session asynchronously, so without this listener the app could treat a
  // logged-in user as signed out and bounce them to /login.
  SupabaseService().auth.onAuthStateChange.listen((_) {
    authRevision.value++;
  });

  runApp(const BookNestApp());
}

class BookNestApp extends StatelessWidget {
  const BookNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'BookNest',
          debugShowCheckedModeBanner: false,
          theme: BookNestTheme.lightTheme,
          darkTheme: BookNestTheme.darkTheme,
          themeMode: switch (themeController.mode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          routerConfig: appRouter,
        );
      },
    );
  }
}
