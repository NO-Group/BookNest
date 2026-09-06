import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/supabase_service.dart';

/// Global authentication guard used to protect interactive actions and
/// routes across the app.
///
/// If the current Supabase session has no authenticated user, a SnackBar is
/// shown prompting the user to sign in and they are pushed to the `/login`
/// route. Otherwise the provided [onAuthenticated] callback is invoked.
class AuthGuard {
  const AuthGuard._();

  /// Runs the guarded [onAuthenticated] callback, or redirects to `/login`
  /// when the user is not authenticated.
  static void run(BuildContext context, VoidCallback onAuthenticated) {
    final user = SupabaseService().auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to continue.'),
          backgroundColor: Color(0xFF00E5FF),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.push('/login');
      return;
    }
    onAuthenticated();
  }

  /// Whether the current Supabase session has an authenticated user.
  static bool get isAuthenticated => SupabaseService().auth.currentUser != null;
}
