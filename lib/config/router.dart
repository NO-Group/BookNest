import 'package:flutter/foundation.dart';
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
import '../presentation/screens/dms/dm_list_screen.dart';
import '../presentation/screens/dms/dm_chat_screen.dart';
import '../presentation/screens/profile/profile_screen.dart';
import '../presentation/screens/profile/user_profile_screen.dart';
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
import '../presentation/screens/discover/community_add_books_screen.dart';
import '../presentation/screens/discover/organization_detail_screen.dart';
import '../presentation/screens/discover/school_detail_screen.dart';
import '../presentation/screens/groups/group_profile_screen.dart';
import '../services/supabase_service.dart';

/// Routes that must never be reached while signed out.
///
/// Covers the fullscreen editor/reader plus every "create" flow, since those
/// handlers read [SupabaseService().auth.currentUser] and would otherwise
/// throw for anonymous visitors. Also covers group chat/profile (member-only
/// content) and the community library (member-only).
const Set<String> _protectedRoutes = {
  '/editor',
  '/publish-details',
  // Messages tab + its chat screen and the Profile tab all need a session:
  // the DM list/chat read `conversation_members` and the profile reads the
  // signed-in user's own `profiles` row.
  '/dms',
  '/dm',
  '/profile',
  // Groups are member-only content.
  '/group',
  '/group-chat',
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

/// Bumped whenever the auth state changes (sign-in, sign-out, session
/// restore/refresh/expiry) so [GoRouter] re-runs `_redirect` immediately.
///
/// Without this, the router only re-checks auth on the *next* navigation —
/// which is exactly what caused the "logged in but bounced to /login" loop:
/// `Supabase.initialize()` restores the persisted session *asynchronously*
/// (fire-and-forget `recoverSession()`), so the app could decide the user is
/// signed out before the restore finished, and never re-evaluate afterwards.
final ValueNotifier<int> authRevision = ValueNotifier<int>(0);

/// Global auth redirect.
///
/// Intercepts navigation to protected fullscreen routes and sends
/// unauthenticated users to `/login`.
String? _redirect(BuildContext context, GoRouterState state) {
  final path = state.uri.path;
  // `currentSession` is the source of truth for "am I signed in". `currentUser`
  // can be null in the brief window between a session being restored/refreshed
  // and the auth subscribers being notified, which used to cause false
  // redirects to `/login` even for logged-in users.
  final isLoggedIn = SupabaseService().auth.currentSession != null;

  final isAuthRoute = path == '/login' || path == '/register';
  final isProtected =
      _protectedRoutes.any((route) => path == route || path.startsWith('$route/'));
  // Community libraries are member-only even though the community detail page
  // itself is browsable while signed out.
  final isCommunityLibrary =
      RegExp(r'^/community/[^/]+/library').hasMatch(path);

  if (!isLoggedIn) {
    if (isProtected || isCommunityLibrary) return '/login';
    return null;
  }

  // Already signed in users are sent away from the login/register screens.
  if (isAuthRoute) return '/feed';

  return null;
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  refreshListenable: authRevision,
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
        final communityId = state.uri.queryParameters['communityId'];
        final bookId = state.uri.queryParameters['bookId'];
        return BookEditorScreen(
          clubId: clubId,
          communityId: communityId,
          bookId: bookId,
        );
      },
    ),
    GoRoute(
      path: '/publish-details',
      builder: (context, state) {
        final bookId = state.uri.queryParameters['bookId'] ?? '';
        return PublishDetailsScreen(bookId: bookId);
      },
    ),
    // Fullscreen 1-on-1 chat (covers the bottom nav like /editor does).
    GoRoute(
      path: '/dm/:conversationId',
      builder: (context, state) => ConversationChatScreen(
        conversationId: state.pathParameters['conversationId'] ?? '',
      ),
    ),
    // Fullscreen group chat (announcements + regular groups of any entity).
    GoRoute(
      path: '/group-chat/:conversationId',
      builder: (context, state) => ConversationChatScreen(
        conversationId: state.pathParameters['conversationId'] ?? '',
        isGroup: true,
      ),
    ),
    // Group profile screen (members, admins, open chat).
    GoRoute(
      path: '/group/:groupId',
      builder: (context, state) => GroupProfileScreen(
        groupId: state.pathParameters['groupId'] ?? '',
      ),
    ),
    // Public profile of another user.
    GoRoute(
      path: '/user/:userId',
      builder: (context, state) => UserProfileScreen(
        userId: state.pathParameters['userId'] ?? '',
      ),
    ),
    // Community library "Add books" picker.
    GoRoute(
      path: '/community/:communityId/library/add',
      builder: (context, state) => CommunityAddBooksScreen(
        communityId: state.pathParameters['communityId'] ?? '',
      ),
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
