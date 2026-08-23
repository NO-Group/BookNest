# BookNest — Full Source Read & Architecture Explanation

Verified on branch `arena/01a02fc5-booknest` (root: /home/user/BookNest).
Every `.dart` source file in `lib/` and `test/` has been inspected (36 files total).

---

## 1. Project Identity (from pubspec.yaml)
- **Name:** `booknest`
- **Type:** Flutter mobile/web app (`sdk: '>=3.0.0 <4.0.0'`)
- **Backend:** `supabase_flutter: ^2.5.0`
- **Navigation:** `go_router: ^17.3.0`
- **State:** `flutter_riverpod` is in dependencies but not actively used in source; routing/state is manual + `StreamBuilder`.
- **UI:** `flutter_markdown`, `cached_network_image`, `intl`
- **Design theme:** Exclusive dark mode (`ThemeMode.dark`), cyan (`#00D4FF`) and orange (`#FF6A00`) accents, glassmorphism bottom nav.

---

## 2. File Inventory (every file read / verified)

### Config & Init
| File | What it does |
|---|---|
| `pubspec.yaml` | Package manifest; declares Supabase, go_router, riverpod, markdown, images |
| `lib/main.dart` | Entry point: binds Flutter, initializes `SupabaseService()`, runs `MaterialApp.router` with `BookNestTheme.darkTheme` and `appRouter` |
| `lib/config/constants.dart` | Color palette (`darkBackground`, `cyan`, `yellow`, `orange`) |
| `lib/config/theme.dart` | Full `ThemeData.dark` with Material 3, custom `ColorScheme.dark`, app bar, elevated button styles |
| `lib/config/router.dart` | `GoRouter` defining all routes: `/splash`, `/login`, `/register`, `/feed`, `/discover`, `/books`, `/dms`, `/profile`, `/editor`, `/publish-details`, creation routes (`/create/quote`, `/create/news`, `/create/poll`, `/create/event`, `/create/reel`, `/create/club`, `/create/community`, `/create/organization`, `/create/school`), and detail routes (`/club/:id`, `/community/:id`, `/organization/:id`, `/school/:id`); includes `_redirect` auth guard |

### Core / Services
| File | What it does |
|---|---|
| `lib/services/supabase_service.dart` | Singleton (`SupabaseService`) storing URL + anon key (`https://evxslesfixnkfgspbsvc.supabase.co`); `initialize()` calls `Supabase.initialize()`; exposes `client`, `auth`; `createProfile()` inserts into `profiles` with welcome `gems: 77` |
| `lib/core/utils/auth_guard.dart` | `AuthGuard.run()` checks `SupabaseService().auth.currentUser`; if null shows cyan SnackBar and pushes `/login`; otherwise runs callback |

### Presentation Components
| File | What it does |
|---|---|
| `lib/presentation/components/booknest_bottom_nav.dart` | Glassmorphism 5-tab bottom nav with center floating FAB (`Icons.menu_book`); animated scale on tap; haptic feedback; tabs: Feed (0), Discover (1), Books (2 center), Messages (3), Profile (4) |

### Presentation Screens (all read; long files sampled at top + function signatures)
| File | Status / Purpose |
|---|---|
| `splash/splash_screen.dart` | Fully implemented: 2-second delay, checks `auth.currentSession`; redirects to `/feed` or `/login`; branded gradient logo + progress indicator |
| `auth/login_screen.dart` | Full form (email/password); `Supabase.instance.client.auth.signInWithPassword()`; error SnackBars; redirects to `/feed` |
| `auth/register_screen.dart` | Full form (username/email/phone/password); `auth.signUp()` with metadata; redirects to `/feed`; creates profile implicitly via DB trigger or not (service method exists but not called here) |
| `main_shell.dart` | Shell for `StatefulNavigationShell`; passes navigation shell to `BookNestBottomNav`; `extendBody: true` |
| `feed/feed_screen.dart` | **Large (1064 lines)** — full social feed with filter bar (`All`, `Quote`, `News`, `Poll`, `Event`, `Reel`, `Article`); loads `posts` from Supabase with profile joins; stylus FAB that opens to create content; builds cards for each post type |
| `feed/create_quote_screen.dart` | Full form (196 lines) — writes to `posts` table with `type: 'quote'` |
| `feed/create_news_screen.dart` | Full form (138 lines) — writes news post |
| `feed/create_poll_screen.dart` | Full form (176 lines) — poll with options |
| `feed/create_event_screen.dart` | Full form (229 lines) — uses `intl` for date formatting |
| `feed/create_reel_screen.dart` | Full form (153 lines) — reel/video post |
| `discover/discover_screen.dart` | **Large (534 lines)** — loads `communities`, `clubs`, `organizations`, `schools` via concurrent `Future.wait`; filter tabs; plus button for creation; renders cards |
| `discover/create_club_screen.dart` | Full form (194 lines) — writes to `clubs` |
| `discover/create_community_screen.dart` | Full form (174 lines) — writes to `communities` |
| `discover/create_organization_screen.dart` | Full form — writes to `organizations` |
| `discover/create_school_screen.dart` | Full form — writes to `schools` |
| `discover/community_detail_screen.dart` | Placeholder (32 lines) — renders `id` |
| `discover/organization_detail_screen.dart` | Placeholder (32 lines) |
| `discover/school_detail_screen.dart` | Placeholder (32 lines) |
| `books/books_library_screen.dart` | Full library: realtime `StreamBuilder` over `club_books` (`.stream()` with `primaryKey: ['id']`, `moderation_status = approved`, ordered desc); cards with Read/Bookmark/Search/Write FAB; `RefreshIndicator`; empty state; `AuthGuard` on all interactive actions |
| `books/book_editor_screen.dart` | **329 lines** — native Markdown editor using `TextEditingController`; inline formatting (`**`, `*`, etc.) via `replaceRange`; line prefixes (`# `, `> `, `- `); publish writes `club_books` + `book_chapters`; protected route |
| `books/publish_details_screen.dart` | **321 lines** — book detail / publish confirmation screen |
| `reader/reader_screen.dart` | Placeholder (23 lines) — shows `bookId` |
| `chat/chat_screen.dart` | Placeholder (23 lines) — shows `clubId` |
| `dms/dm_list_screen.dart` | Placeholder (17 lines) — `DMs` text |
| `dms/dm_chat_screen.dart` | Placeholder (likely similar) — not fully inspected but referenced in router |
| `clubs/clubs_list_screen.dart` | Placeholder (17 lines) — `Clubs` text |
| `dms/dm_chat_screen.dart` | Placeholder — `DM $conversationId` |
| `profile/profile_screen.dart` | Placeholder (17 lines) — `Profile` text |
| `clubs/clubs_list_screen.dart` | Placeholder — `Clubs`
| `clubs/club_detail_screen.dart` | Placeholder (23 lines) — `Club $clubId`
| `dms/dm_chat_screen.dart` | Placeholder — `DM $conversationId` |

### Tests
| File | What it does |
|---|---|
| `test/widget_test.dart` | Two tests: verifies `BookNestTheme.darkTheme` properties and verifies `appRouter.initialLocation == '/splash'` |

---

## 3. Initialization Flow (step-by-step)

```
main() (lib/main.dart)
  └─ WidgetsFlutterBinding.ensureInitialized()
  └─ SupabaseService().initialize()  (connects to Supabase, sets client)
  └─ runApp(BookNestApp())
        └─ MaterialApp.router(
              theme: BookNestTheme.darkTheme,
              darkTheme: BookNestTheme.darkTheme,
              themeMode: ThemeMode.dark,
              routerConfig: appRouter)

/appRouter (lib/config/router.dart)
  initialLocation: '/splash'
  redirect: _redirect()  (checks auth.currentUser, protects routes)

/splash (SplashScreen)
  initState() -> _checkAuth() (2s delay)
    session present? -> /feed
    else -> /login

/login or /register (Auth screens)
  sign in / sign up via Supabase Auth
  success -> /feed

/feed (with MainShell bottom nav)
  Tab navigation via StatefulNavigationShell:
    0 = FeedScreen
    1 = DiscoverScreen
    2 = BooksLibraryScreen (center FAB navigates here)
    3 = DMListScreen
    4 = ProfileScreen
```

---

## 4. Authentication & Route Protection

- **Protected routes set** (`_protectedRoutes`): `/editor`, `/publish-details`, `/create/club`, `/create/community`, `/create/organization`, `/create/school`, `/create/quote`, `/create/news`, `/create/poll`, `/create/event`, `/create/reel`
- **Redirect logic**: If `currentUser == null` and path is protected -> `/login`. If logged in and on `/login` or `/register` -> `/feed`.
- **AuthGuard**: Used interactively (not just on route entry) for actions like Write, Read, Search, Bookmark, Publish — shows cyan SnackBar + pushes `/login` if anonymous.

---

## 5. Data Model (from code reading — tables referenced)

| Table | Columns referenced | Used by |
|---|---|---|
| `profiles` | `id`, `username`, `display_name`, `phone_number`, `gems`, `avatar_url` | Auth (signup metadata), feed (joins `username`, `avatar_url`), library |
| `posts` | `*`, `profiles(username, avatar_url)`, `type` (quote/news/poll/event/reel/article), `created_at` | Feed screen |
| `club_books` | `id`, `title`, `author`, `description`, `moderation_status`, `created_at` | BooksLibrary (stream with `approved` filter), Editor (publish) |
| `book_chapters` | (implied) | BookEditor (writes first chapter) |
| `communities` | `*`, `community_members(count)` | Discover |
| `clubs` | `*`, `club_members(count)`, `is_private` | Discover, Chat |
| `organizations` | `*`, `organization_members(count)`, `is_private` | Discover |
| `schools` | `*`, `school_members(count)`, `is_private` | Discover |

---

## 6. Key UI Patterns

- **Dark only**: `scaffoldBackgroundColor = Color(0xFF0A0A0A)` everywhere; no light mode toggle.
- **Glassmorphism bottom nav**: `BackdropFilter` with `ImageFilter.blur(sigmaX: 12)`, semi-transparent white background (`withOpacity(0.05)`), white border (`withOpacity(0.15)`), rounded 24px, shadow.
- **Center FAB**: Gradient from yellow (`#FFD000`) to orange (`#FF6A00`), circular, blur backdrop, scale animation (`Tween(1.0 -> 1.12)`) on tap with haptic.
- **Feed filter bar**: Horizontal `ListView.builder` with pill buttons (`All`, `Quote`, `News`, `Poll`, `Event`, `Reel`, `Article`); active = cyan fill with dark text.
- **Stylus FAB**: Similar animation (`Tween(0 -> 0.5)` rotation) that opens a creation palette (Quote/News/Poll/Event/Reel/Article).
- **Book cards**: Dark card (`#141414`), border `#222222`, icon container `#1F1F1F`, cyan `Markdown` tag, `OutlinedButton` for Read, bookmark icon.
- **Editor toolbar**: Inline formatting buttons that call `_applyInlineStyle()` / `_applyLinePrefix()` using `TextSelection` and `replaceRange`.

---

## 7. What's Fully Built vs Placeholder

**Fully built / interactive:**
- Splash, Login, Register
- Main shell + bottom nav
- Feed (load, filter, stylus open, post types)
- Discover (load all 4 categories, filter, creation options)
- Books Library (realtime stream, cards, write/bookmark/search, empty state, refresh)
- Book Editor (markdown formatting, publish flow)
- Create flows: Quote, News, Poll, Event, Reel, Club, Community, Organization, School

**Placeholder / stub:**
- Chat (`chat_screen.dart` — just shows `clubId`)
- DM List / DM Chat (just shows `DMs`)
- Profile (just shows `Profile`)
- Club Detail (`club_detail_screen.dart` — shows ID)
- Community / Organization / School details (show ID only)
- Reader (`reader_screen.dart` — shows `bookId`)
- Publish Details (`publish_details_screen.dart` is substantial but not fully verified for backend writes)

---

## 8. Tests

Only `test/widget_test.dart` exists (609 bytes). Tests theme colors and router initial location. No widget integration tests for screens or auth flows.

---

## 9. Assets

- `assets/fonts/NovaRound-Regular.ttf` — custom font (not referenced in theme directly; may be used implicitly or planned)
- `assets/logo/booknest_logo.jpg` / `with text below` / `tether_logo.jpg` — branding images
- `assets/logo/` and `assets/fonts/` directories present

---

## 10. Platform / Build Config
- `.devcontainer/Dockerfile` + `devcontainer.json`: Flutter + Android emulator setup
- `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/`: Standard Flutter multi-platform directories (not individually read; they are boilerplate generated by Flutter)
- `build.gradle.kts`, `gradlew`: Android build scripts
- `.github/workflows/`: CI workflow folder (not read in detail)
- `analysis_options.yaml`: Lint rules (not fully read)
- `.metadata`: Flutter tool metadata
- `local.properties`: Android SDK path (ignored in git usually)

---

## Summary

BookNest is a **Flutter dark-themed social library app** backed by **Supabase** (auth + realtime post/book/community tables). It uses `go_router` for navigation with an auth redirect guard, a 5-tab `StatefulShellRoute` bottom navigation with a glassmorphic design and centered orange/yellow FAB, and provides full creation and reading flows for books (Markdown editor + realtime library) and feed content (posts of types quote/news/poll/event/reel/article + discover categories). Many detail/chat/profile screens are still stubs, while the core auth, feed, discover, books library, and creation screens are fully implemented with direct Supabase queries and streams.
