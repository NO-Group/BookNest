import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';
import '../../../services/reader_profile.dart';

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
      // Compulsory profile: gender and birth year power the moderator's
      // insights — readers who slipped past setup finish it here first.
      await ReaderProfile.ensureLoaded();
      final profile = ReaderProfile.instance;
      if (!mounted) return;
      if ((profile.gender == null || profile.gender!.isEmpty) ||
          profile.birthYear == null) {
        context.go('/profile-setup');
      } else {
        context.go('/feed');
      }
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
              // The logo is navy ink — it sits on a white tile (like its
              // app icon), never on black. Soft cyan glow ties it to the page.
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: BookNestColors.cyan.withOpacity(.28),
                      blurRadius: 40,
                      spreadRadius: 2,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(18),
                // NB: despite its name this file is the navy logo (for light
                // backgrounds); "…light_theme.png" is the white one.
                child: Image.asset(
                  'assets/logo/booknest_logo_new_transparent_dark_theme.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
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
