import 'package:flutter/material.dart';
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
import '../presentation/screens/settings/settings_screen.dart';
import '../presentation/screens/settings/edit_profile_screen.dart';
import '../presentation/screens/library/my_library_screen.dart';
import '../presentation/screens/notifications/notifications_screen.dart';
import '../presentation/screens/profile/author_profile_screen.dart';
import '../presentation/screens/profile/follow_list_screen.dart';
import '../presentation/screens/books/writer_dashboard_screen.dart';
import '../presentation/screens/books/manage_book_screen.dart';
import '../presentation/screens/books/chapter_manager_screen.dart';
import '../presentation/screens/books/chapter_editor_screen.dart';
import '../presentation/screens/books/book_analytics_screen.dart';
import '../presentation/screens/books/reviews_hub_screen.dart';
import '../presentation/screens/books/book_reviews_screen.dart';
import '../presentation/screens/books/book_discussion_screen.dart';
import '../presentation/screens/books/genre_browse_screen.dart';
import '../presentation/screens/search/global_search_screen.dart';
import '../presentation/screens/onboarding/onboarding_screen.dart';
import '../presentation/screens/support/privacy_screen.dart';
import '../presentation/screens/support/about_screen.dart';
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
  '/settings',
  '/library',
  '/notifications',
  '/dashboard',
  '/manage',
  '/write-chapter',
  '/analytics',
  '/my-reviews',
  '/onboarding',
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
    GoRoute(
      path: '/book/:id/reviews',
      builder: (context, state) => BookReviewsScreen(
        bookId: state.pathParameters['id'] ?? '',
      ),
    ),
    GoRoute(
      path: '/book/:id/discussion',
      builder: (context, state) => BookDiscussionScreen(
        bookId: state.pathParameters['id'] ?? '',
      ),
    ),
    // ── Account & library ──
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(
      path: '/settings/edit-profile',
      builder: (context, state) => const EditProfileScreen(),
    ),
    GoRoute(path: '/library', builder: (context, state) => const MyLibraryScreen()),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    // ── Social ──
    GoRoute(
      path: '/user/:id',
      builder: (context, state) => AuthorProfileScreen(
        userId: state.pathParameters['id'] ?? '',
      ),
    ),
    GoRoute(
      path: '/user/:id/follows',
      builder: (context, state) => FollowListScreen(
        userId: state.pathParameters['id'] ?? '',
        type: state.uri.queryParameters['type'] == 'following'
            ? 'following'
            : 'followers',
      ),
    ),
    // ── Writer tools ──
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const WriterDashboardScreen(),
    ),
    GoRoute(
      path: '/manage/:bookId',
      builder: (context, state) => ManageBookScreen(
        bookId: state.pathParameters['bookId'] ?? '',
      ),
    ),
    GoRoute(
      path: '/manage/:bookId/chapters',
      builder: (context, state) => ChapterManagerScreen(
        bookId: state.pathParameters['bookId'] ?? '',
      ),
    ),
    GoRoute(
      path: '/write-chapter',
      builder: (context, state) => ChapterEditorScreen(
        bookId: state.uri.queryParameters['bookId'] ?? '',
        chapterNumber:
            int.tryParse(state.uri.queryParameters['number'] ?? '1') ?? 1,
        initialTitle: state.uri.queryParameters['title'] ?? '',
      ),
    ),
    GoRoute(
      path: '/analytics/:bookId',
      builder: (context, state) => BookAnalyticsScreen(
        bookId: state.pathParameters['bookId'] ?? '',
      ),
    ),
    GoRoute(
      path: '/my-reviews',
      builder: (context, state) => const ReviewsHubScreen(),
    ),
    // ── Discovery ──
    GoRoute(
      path: '/genre',
      builder: (context, state) => GenreBrowseScreen(
        genre: state.uri.queryParameters['name'] ?? 'Romance',
      ),
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => const GlobalSearchScreen(),
    ),
    // ── Support ──
    GoRoute(path: '/privacy', builder: (context, state) => const PrivacyScreen()),
    GoRoute(path: '/about', builder: (context, state) => const AboutScreen()),
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
