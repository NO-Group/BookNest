import 'package:flutter/material.dart';
import 'config/router.dart';
import 'config/theme.dart';
import 'services/supabase_service.dart';

class BookNestApp extends StatefulWidget {
  const BookNestApp({super.key});

  @override
  State<BookNestApp> createState() => _BookNestAppState();
}

class _BookNestAppState extends State<BookNestApp> {
  final _supabase = SupabaseService();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _supabase.initialize();
    if (mounted) setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D4FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text(
                      'B',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const CircularProgressIndicator(color: Color(0xFF00D4FF)),
              ],
            ),
          ),
        ),
      );
    }

    return MaterialApp.router(
      title: 'BookNest',
      debugShowCheckedModeBanner: false,
      theme: BookNestTheme.darkTheme,
      darkTheme: BookNestTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
  }
}