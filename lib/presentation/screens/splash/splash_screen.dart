import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final session = SupabaseService().auth.currentSession;
    if (session != null) {
      context.go('/feed');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    // The splash is always the brand gradient — it reads identically in
    // light and dark mode (like Telegram's launch screen).
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [BookNestColors.navyDeep, BookNestColors.navy, Color(0xFF0D356E)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [BookNestColors.cyan, BookNestColors.cyanSoft],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: BookNestColors.cyan.withOpacity(.35),
                      blurRadius: 34,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.menu_book,
                    color: BookNestColors.navyDeep,
                    size: 48,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'BookNest',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'by N.O Group',
                style: TextStyle(
                  color: Colors.white.withOpacity(.65),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 48),
              const CircularProgressIndicator(
                color: BookNestColors.cyan,
                strokeWidth: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
