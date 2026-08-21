import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  StreamSubscription<AuthState>? _authSub;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // If the persisted session finishes restoring (or a sign-in happens)
    // while the splash is on screen, route to /feed right away instead of
    // wrongly landing on /login. Supabase restores sessions asynchronously.
    _authSub = SupabaseService().auth.onAuthStateChange.listen((state) {
      if (state.session != null) {
        _goHome();
      }
    });
    _checkAuth();
  }

  void _goHome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    context.go('/feed');
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final session = SupabaseService().auth.currentSession;
    if (session != null) {
      _goHome();
    } else if (!_navigated) {
      _navigated = true;
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NOC.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient:  LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E4FD6), NOC.accent],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E4FD6).withOpacity(0.4),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child:  Center(
                child: Icon(
                  Icons.menu_book,
                  color: NOC.text,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: 24),
             Text(
              'BookNest',
              style: TextStyle(
                color: NOC.text,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
             Text(
              'by N.O Group',
              style: TextStyle(
                color: NOC.textMuted,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
              color: Color(0xFF1E4FD6),
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}
