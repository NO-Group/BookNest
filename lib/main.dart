import 'package:flutter/material.dart';

import 'config/app_state.dart';
import 'config/router.dart';
import 'config/theme.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService().initialize();
  runApp(const BookNestApp());
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
