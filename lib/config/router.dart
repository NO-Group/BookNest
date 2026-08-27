import 'package:go_router/go_router.dart';

import '../presentation/screens/splash/splash_screen.dart';
import '../presentation/screens/auth/login_screen.dart';
import '../presentation/screens/auth/register_screen.dart';
import '../presentation/screens/main_shell.dart';
import '../presentation/screens/feed/feed_screen.dart';
import '../presentation/screens/discover/discover_screen.dart';
import '../presentation/screens/books/books_library_screen.dart';
import '../presentation/screens/books/book_editor_screen.dart';
import '../presentation/screens/books/publish_details_screen.dart';
import '../presentation/screens/books/book_details_screen.dart';
import '../presentation/screens/dms/dm_list_screen.dart';
import '../presentation/screens/dms/dm_chat_screen.dart';
import '../presentation/screens/profile/profile_screen.dart';
import '../presentation/screens/feed/create_quote_screen.dart';
import '../presentation/screens/feed/create_news_screen.dart';
import '../presentation/screens/feed/create_poll_screen.dart';
import '../presentation/screens/feed/create_event_screen.dart';
import '../presentation/screens/feed/create_reel_screen.dart';
import '../presentation/screens/discover/create_club_screen.dart';
import '../presentation/screens/discover/create_community_screen.dart';
import '../presentation/screens/discover/create_organization_screen.dart';
import '../presentation/screens/discover/create_school_screen.dart';
import '../presentation/screens/clubs/club_detail_screen.dart';
import '../presentation/screens/discover/community_detail_screen.dart';
import '../presentation/screens/discover/organization_detail_screen.dart';
import '../presentation/screens/discover/school_detail_screen.dart';
import '../services/supabase_service.dart';

/// Routes that must never be reached while signed out.
///
/// Covers the fullscreen editor/reader plus every "create" flow, since those
/// handlers read [SupabaseService().auth.currentUser] and would otherwise
/// throw for anonymous visitors.
const Set<String> _protectedRoutes = {
  '/editor',
  '/publish-details',
  '/chat',
  '/create/club',
  '/create/community',
  '/create/organization',
  '/create/school',
  '/create/quote',
  '/create/news',
  '/create/poll',
  '/create/event',
  '/create/reel',
};

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
  if (isAuthRoute) return '/feed';

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
      path: '/book/:id',
      builder: (context, state) => BookDetailsScreen(
        bookId: state.pathParameters['id'] ?? '',
      ),
    ),
    // Telegram-style chat, opened full-screen (nav bar hidden).
    // `/chat/<conversationId>` continues a chat; `/chat/peer/<peerId>`
    // starts one (the edge function reuses the 1:1 conversation).
    GoRoute(
      path: '/chat/peer/:peerId',
      builder: (context, state) => DMChatScreen(
        peerId: state.pathParameters['peerId'] ?? '',
      ),
    ),
    GoRoute(
      path: '/chat/:conversationId',
      builder: (context, state) => DMChatScreen(
        conversationId: state.pathParameters['conversationId'] ?? '',
        peerId: state.uri.queryParameters['peer'],
      ),
    ),
    GoRoute(
      path: '/publish-details',
      builder: (context, state) {
        final bookId = state.uri.queryParameters['bookId'] ?? '';
        return PublishDetailsScreen(bookId: bookId);
      },
    ),
    // Feed content creation routes (fullscreen, hide the nav bar).
    GoRoute(
      path: '/create/quote',
      builder: (context, state) => const CreateQuoteScreen(),
    ),
    GoRoute(
      path: '/create/news',
      builder: (context, state) => const CreateNewsScreen(),
    ),
    GoRoute(
      path: '/create/poll',
      builder: (context, state) => const CreatePollScreen(),
    ),
    GoRoute(
      path: '/create/event',
      builder: (context, state) => const CreateEventScreen(),
    ),
    GoRoute(
      path: '/create/reel',
      builder: (context, state) => const CreateReelScreen(),
    ),
    // Discover creation routes (fullscreen, hide the nav bar).
    GoRoute(
      path: '/create/club',
      builder: (context, state) => const CreateClubScreen(),
    ),
    GoRoute(
      path: '/create/community',
      builder: (context, state) => const CreateCommunityScreen(),
    ),
    GoRoute(
      path: '/create/organization',
      builder: (context, state) => const CreateOrganizationScreen(),
    ),
    GoRoute(
      path: '/create/school',
      builder: (context, state) => const CreateSchoolScreen(),
    ),
    GoRoute(
      path: '/club/:id',
      builder: (context, state) => ClubDetailScreen(
        clubId: state.pathParameters['id'] ?? '',
      ),
    ),
    GoRoute(
      path: '/community/:id',
      builder: (context, state) => CommunityDetailScreen(
        id: state.pathParameters['id'] ?? '',
      ),
    ),
    GoRoute(
      path: '/organization/:id',
      builder: (context, state) => OrganizationDetailScreen(
        id: state.pathParameters['id'] ?? '',
      ),
    ),
    GoRoute(
      path: '/school/:id',
      builder: (context, state) => SchoolDetailScreen(
        id: state.pathParameters['id'] ?? '',
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      branches: [
        // Tab 1: Feed
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/feed',
              builder: (context, state) => const FeedScreen(),
            ),
          ],
        ),
        // Tab 2: Discover
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/discover',
              builder: (context, state) => const DiscoverScreen(),
            ),
          ],
        ),
        // Tab 3: Books (center FAB)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/books',
              builder: (context, state) => const BooksLibraryScreen(),
            ),
          ],
        ),
        // Tab 4: Messages
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/dms',
              builder: (context, state) => const DMListScreen(),
            ),
          ],
        ),
        // Tab 5: Profile
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
