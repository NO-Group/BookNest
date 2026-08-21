import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/supabase_service.dart';

/// Global authentication guard used to protect interactive actions and
/// routes across the app.
///
/// If there is no active Supabase session, a SnackBar is shown prompting the
/// user to sign in and they are pushed to the `/login` route. Otherwise the
/// provided [onAuthenticated] callback is invoked.
class AuthGuard {
  const AuthGuard._();

  /// Runs the guarded [onAuthenticated] callback, or redirects to `/login`
  /// when the user is not authenticated.
  static void run(BuildContext context, VoidCallback onAuthenticated) {
    // `currentSession` (not `currentUser`) is the source of truth: the user
    // object can lag behind the session during restore/refresh windows, which
    // previously bounced logged-in users back to `/login`.
    final hasSession = SupabaseService().auth.currentSession != null;
    if (!hasSession) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to continue.'),
          backgroundColor: Color(0xFF1E4FD6),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.push('/login');
      return;
    }
    onAuthenticated();
  }

  /// Whether the current Supabase session has an authenticated user.
  static bool get isAuthenticated =>
      SupabaseService().auth.currentSession != null;
}
