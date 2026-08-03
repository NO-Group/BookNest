import 'package:go_router/go_router.dart';

import '../presentation/screens/splash/splash_screen.dart';
import '../presentation/screens/auth/login_screen.dart';
import '../presentation/screens/auth/register_screen.dart';
import '../presentation/screens/main_shell.dart';
import '../presentation/screens/books/books_library_screen.dart';
import '../presentation/screens/books/book_editor_screen.dart';
import '../presentation/screens/books/publish_details_screen.dart';
import '../presentation/screens/discover/discover_screen.dart';
import '../presentation/screens/clubs/clubs_list_screen.dart';
import '../presentation/screens/profile/profile_screen.dart';
import '../services/supabase_service.dart';

/// Routes that must never be reached while signed out.
const Set<String> _protectedRoutes = {'/editor', '/publish-details'};

/// Global auth redirect.
///
/// Intercepts navigation to protected fullscreen routes and sends
/// unauthenticated users to `/login`.
String? _redirect(BuildContext context, GoRouterState state) {
  final path = state.uri.path;
  final isLoggedIn = SupabaseService().auth.currentUser != null;

  final isAuthRoute = path == '/login' || path == '/register';
  final isProtected =
      _protectedRoutes.any((route) => path == route || path.startsWith('$route/'));

  if (!isLoggedIn) {
    if (isProtected) return '/login';
    return null;
  }

  // Already signed in users are sent away from the login/register screens.
  if (isAuthRoute) return '/library';

  return null;
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  redirect: _redirect,
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/editor',
      builder: (context, state) {
        final clubId = state.uri.queryParameters['clubId'];
        return BookEditorScreen(clubId: clubId);
      },
    ),
    GoRoute(
      path: '/publish-details',
      builder: (context, state) {
        final bookId = state.uri.queryParameters['bookId'] ?? '';
        return PublishDetailsScreen(bookId: bookId);
      },
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              builder: (context, state) => const BooksLibraryScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/discover',
              builder: (context, state) => const DiscoverScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/clubs',
              builder: (context, state) => const ClubsListScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
