# 📚 BookNest

> **The Digital Library Ecosystem for Bookworms** — by **N.O Group**

BookNest is a Flutter mobile application that turns reading into a social,
creative experience. It blends a familiar social feed (quotes, news, polls,
events, reels, articles) with a discovery layer for communities, clubs,
organizations and schools, and a first-class **writing studio** where authors
publish books in native Markdown and readers consume them in a clean, dark,
distraction-free reader.

The app is built around five primary surfaces — **Feed · Discover · Books ·
Messages · Profile** — stitched together by a persistent bottom navigation bar
with a center "write a book" action, a global authentication guard, and a
declarative `go_router` routing tree.

---

## 📑 Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Navigation Map](#navigation-map)
4. [Tech Stack](#tech-stack)
5. [Project Structure](#project-structure)
6. [Architecture & Data Flow](#architecture--data-flow)
7. [Authentication & Authorization](#authentication--authorization)
8. [Supabase Backend](#supabase-backend)
9. [Theming](#theming)
10. [Getting Started](#getting-started)
11. [Useful Commands](#useful-commands)
12. [Testing](#testing)
13. [Known Limitations & Placeholders](#known-limitations--placeholders)
14. [Roadmap](#roadmap)
15. [License & Credits](#license--credits)

---

## Overview

BookNest targets book lovers who want more than a plain e-reader. It lets them:

- Share short-form literary content (quotes, news, polls, events, reels, articles).
- Discover and join **Clubs**, **Communities**, **Organizations**, and **Schools**.
- Write and publish **books** in Markdown, with real-time moderation status.
- Read published books in a native Markdown reader.
- Message other readers (DMs) and, per-group, chat inside clubs.

The UI is a fully custom, dark, "glassmorphism"-accented design system built
directly on Flutter widgets — no UI kit dependency beyond the Flutter framework
itself. State is managed locally with `StatefulWidget` + `setState` and backed by
live Supabase Postgres subscriptions where realtime matters (the book library).

---

## Features

### 🔐 Authentication
- Email + password **sign up** and **login** via Supabase Auth.
- A 2-second **splash** screen that routes returning users straight to the feed
  and new users to login.
- A **global auth guard** (`AuthGuard`) that protects interactive actions and a
  router-level redirect that bounces anonymous users away from protected routes.

### 📰 Feed (`/feed`)
- Reverse-chronological feed of posts pulled from the `posts` table joined with
  `profiles`.
- Post types rendered by dedicated card widgets:
  - **Quote** — attributed quotation.
  - **News** — headline + body + optional source/cover image.
  - **Poll** — question with selectable options and a vote count.
  - **Event** — date, location, RSVP.
  - **Reel** — video thumbnail with duration badge (upload is a placeholder).
  - **Article** — long-form text with a "Read" link into the book reader.
- Filter chips (All / Quote / News / Poll / Event / Reel / Article).
- A rotating **"stylus" FAB** that expands into a vertical menu of post types.

### 🧭 Discover (`/discover`)
- Aggregated directory of **Communities**, **Clubs**, **Organizations**, and
  **Schools**, each with member counts and verified badges.
- Search field and filter tabs.
- A rotating **"+" FAB** that expands into create actions:
  New Club · New Organization · New School · New Community.
- Tapping a card navigates to its detail route.

### 📖 Books (`/books`)
- Realtime library of published books (`club_books` where
  `moderation_status = 'approved'`) via a Supabase `.stream()`.
- Pull-to-refresh, empty states, and per-book cards.
- **Write** FAB opens the Markdown editor; **Read** opens the reader;
  **Bookmark** is guarded.

### ✍️ Book Editor (`/editor`)
- A **native Markdown editor** — no third-party rich-text package.
- Toolbar applies formatting with Dart's own selection APIs
  (`TextEditingController.replaceRange` + `TextSelection`):
  bold (`**`), italic (`*`), headings (`# `, `## `), quote (`> `), list (`- `).
- Publishing writes a `club_books` row (status `pending`) plus a first
  `book_chapters` row, then pops back.

### 📜 Book Reader (`/publish-details`)
- Loads a book and its first chapter, then renders the chapter's Markdown with
  `flutter_markdown` in a custom dark stylesheet.
- Bottom action bar (Like / Comment / Bookmark / Share) guarded by `AuthGuard`.

### 💬 Messages & Profile
- **DMs** (`/dms`) list screen and supporting chat/reader stubs.
- **Profile** (`/profile`) placeholder screen.

---

## Navigation Map

| Route                  | Screen                    | In bottom nav? | Protected |
|-----------------------|---------------------------|----------------|-----------|
| `/splash`             | `SplashScreen`            | –              | No        |
| `/login`              | `LoginScreen`             | –              | No*       |
| `/register`           | `RegisterScreen`          | –              | No*       |
| `/feed`               | `FeedScreen`              | Tab 1          | No        |
| `/discover`           | `DiscoverScreen`          | Tab 2          | No        |
| `/books`              | `BooksLibraryScreen`      | Tab 3 (center) | No        |
| `/dms`                | `DMListScreen`            | Tab 4          | No        |
| `/profile`            | `ProfileScreen`           | Tab 5          | No        |
| `/editor`             | `BookEditorScreen`        | FAB            | **Yes**   |
| `/publish-details`    | `PublishDetailsScreen`    | Book "Read"    | **Yes**   |
| `/create/quote`       | `CreateQuoteScreen`       | FAB            | **Yes**   |
| `/create/news`        | `CreateNewsScreen`        | FAB            | **Yes**   |
| `/create/poll`        | `CreatePollScreen`        | FAB            | **Yes**   |
| `/create/event`       | `CreateEventScreen`       | FAB            | **Yes**   |
| `/create/reel`        | `CreateReelScreen`        | FAB            | **Yes**   |
| `/create/club`        | `CreateClubScreen`        | FAB            | **Yes**   |
| `/create/community`   | `CreateCommunityScreen`   | FAB            | **Yes**   |
| `/create/organization`| `CreateOrganizationScreen`| FAB            | **Yes**   |
| `/create/school`      | `CreateSchoolScreen`      | FAB            | **Yes**   |
| `/club/:id`           | `ClubDetailScreen`        | Card tap       | No        |
| `/community/:id`      | `CommunityDetailScreen`   | Card tap       | No        |
| `/organization/:id`   | `OrganizationDetailScreen`| Card tap       | No        |
| `/school/:id`         | `SchoolDetailScreen`      | Card tap       | No        |

\* The login/register routes are *redirect targets* for signed-out users; once
authenticated, visiting them bounces you to `/feed`.

---

## Tech Stack

| Concern            | Choice                                            |
|--------------------|---------------------------------------------------|
| Language           | Dart `>=3.0.0 <4.0.0`                             |
| UI Toolkit         | Flutter (Material, custom dark theme)             |
| Backend / DB       | [Supabase](https://supabase.com) (Postgres + Auth + Realtime) |
| Routing            | `go_router` `^17.3.0` (shell router, redirects)  |
| Markdown           | `flutter_markdown` `^0.7.4`                       |
| State (optional)   | `flutter_riverpod` `^2.5.0` (dependency present, not yet wired) |
| Images (planned)   | `cached_network_image` `^3.3.0` (dependency present, not yet used) |
| Dates              | `intl` `^0.20.3`                                  |
| Lints              | `flutter_lints` `^6.0.0`                          |

> **Note:** `flutter_riverpod` and `cached_network_image` are declared in
> `pubspec.yaml` for upcoming features but are not imported by the current
> source, so they have no effect yet.

---

## Project Structure

```
lib/
├── main.dart                      # App entry: init Supabase, build BookNestApp
├── config/
│   ├── constants.dart             # (reserved for shared constants)
│   ├── router.dart                # go_router tree + global auth redirect
│   └── theme.dart                 # BookNestColors + BookNestTheme.darkTheme
├── core/
│   └── utils/
│       └── auth_guard.dart        # AuthGuard.run / isAuthenticated
├── services/
│   └── supabase_service.dart      # Singleton wrapper around Supabase client
└── presentation/
    ├── components/
    │   └── booknest_bottom_nav.dart  # 5-tab nav + center FAB
    └── screens/
        ├── splash/splash_screen.dart
        ├── auth/
        │   ├── login_screen.dart
        │   └── register_screen.dart
        ├── main_shell.dart           # StatefulNavigationShell host
        ├── feed/
        │   ├── feed_screen.dart
        │   ├── create_quote_screen.dart
        │   ├── create_news_screen.dart
        │   ├── create_poll_screen.dart
        │   ├── create_event_screen.dart
        │   └── create_reel_screen.dart
        ├── discover/
        │   ├── discover_screen.dart
        │   ├── create_club_screen.dart
        │   ├── create_community_screen.dart
        │   ├── create_organization_screen.dart
        │   ├── create_school_screen.dart
        │   ├── community_detail_screen.dart
        │   ├── organization_detail_screen.dart
        │   └── school_detail_screen.dart
        ├── books/
        │   ├── books_library_screen.dart
        │   ├── book_editor_screen.dart
        │   └── publish_details_screen.dart
        ├── clubs/
        │   ├── clubs_list_screen.dart
        │   └── club_detail_screen.dart
        ├── dms/
        │   ├── dm_list_screen.dart
        │   └── dm_chat_screen.dart
        ├── chat/
        │   └── chat_screen.dart
        ├── reader/
        │   └── reader_screen.dart
        └── profile/
            └── profile_screen.dart
test/
└── widget_test.dart              # Theme + router smoke tests
```

---

## Architecture & Data Flow

**Entry point (`main.dart`)**
1. `WidgetsFlutterBinding.ensureInitialized()`
2. `await SupabaseService().initialize()` — calls `Supabase.initialize(...)`
   and caches `Supabase.instance.client`.
3. `runApp(const BookNestApp())` → `MaterialApp.router(routerConfig: appRouter)`.

**Routing (`config/router.dart`)**
- A single `GoRouter` with `initialLocation: '/splash'`.
- Top-level `GoRoute`s for auth, editor, reader, create flows, and the four
  detail routes.
- A `StatefulShellRoute.indexedStack` wraps the five primary tabs so each tab
  keeps its own navigation stack (preserved via `navigationShell.goBranch`).
- A `_redirect` callback enforces the auth guard (see below).

**Service layer (`services/supabase_service.dart`)**
- Singleton (`factory SupabaseService() => _instance`).
- Exposes `client` (raw `SupabaseClient`) and convenience getters
  `supabase` and `auth` (`client.auth`).
- `createProfile(...)` inserts a `profiles` row with a `gems: 77` welcome bonus.

**UI layer**
- Most screens are self-contained `StatefulWidget`s that call
  `SupabaseService().client.from(...)` directly inside `async` handlers.
- The book library is the exception: it subscribes to a
  `client.from('club_books').stream(primaryKey: ['id'])` so the list updates
  live as books are approved.

---

## Authentication & Authorization

Two complementary guards keep anonymous users out of write paths:

1. **Router redirect (`_redirect` in `router.dart`)**
   - If the user is **not** signed in and the target route is in
     `_protectedRoutes` (`/editor`, `/publish-details`, and every `/create/*`
     route), they are redirected to `/login`.
   - If the user **is** signed in and hits `/login` or `/register`, they are
     sent to `/feed`.

2. **`AuthGuard` (`core/utils/auth_guard.dart`)**
   - `AuthGuard.run(context, onAuthenticated)` shows a SnackBar ("Please sign
     in to continue.") and navigates to `/login` when there is no session;
     otherwise it invokes the callback. Used to guard the Books library's
     Write / Read / Bookmark actions and the reader's action bar.

> **Why both?** The router guard protects *routes*; `AuthGuard` protects
> *in-app actions* (e.g., tapping "Bookmark") even on routes that are
> technically viewable while signed out.

---

## Supabase Backend

BookNest expects a Supabase project with Auth enabled and the following tables
(referenced by the app's queries). Column names below are inferred from the
source; enforce Row-Level Security (RLS) appropriate to your trust model.

| Table                | Key columns (inferred)                                                      |
|----------------------|-----------------------------------------------------------------------------|
| `profiles`           | `id` (uuid, = auth user), `username`, `display_name`, `phone_number`, `gems` (int, default 77) |
| `posts`              | `id`, `type` (quote/news/poll/event/reel/article/text), `title`, `content`, `metadata` (jsonb), `created_by`, `created_at` |
| `clubs`              | `id`, `name`, `description`, `genre_tags` (text[]), `is_private` (bool), `owner_id`, `vice_moderator_id` |
| `communities`        | `id`, `name`, `description`, `owner_id`, `vice_moderator_id`                |
| `organizations`      | `id`, `name`, `description`, `mission`, `org_type`, `owner_id`, `vice_moderator_id`, `is_verified` |
| `schools`            | `id`, `name`, `description`, `location`, `website`, `school_type`, `owner_id`, `vice_moderator_id`, `is_verified` |
| `club_books`         | `id`, `club_id` (nullable), `title`, `author`, `description`, `content_format` ('markdown'), `moderation_status` ('pending'/'approved'), `added_by`, `created_at` |
| `book_chapters`      | `id`, `club_book_id`, `chapter_number`, `title`, `content`                  |
| `community_members`  | `community_id`, `user_id`, `role` (e.g. 'owner')                            |
| `club_members`       | `club_id`, `user_id` (+ `count` aggregate used by Discover)                 |
| `organization_members`| `organization_id`, `user_id`                                              |
| `school_members`     | `school_id`, `user_id`                                                      |
| `announcement_groups`| `id`, `community_id`, `name`                                               |

The `metadata` JSONB on `posts` carries type-specific fields:
`quote_author`, `source`, `options`, `votes`, `date`, `time`, `location`,
`is_online`, `datetime`, `thumbnail_url`, `duration`, `views`.

> Database migrations / SQL are **not** included in this repository. Create the
> schema (and RLS policies) in your Supabase dashboard or via `supabase db`.

---

## Theming

`config/theme.dart` defines:

- **`BookNestColors`** — the palette (near-black backgrounds `#0A0A0A`,
  cyan accent `#00D4FF`, warm orange/yellow gradients `#FF6A00` / `#FFD000`).
- **`BookNestTheme.darkTheme`** — a `ThemeData` with `useMaterial3: true`,
  `Brightness.dark`, a custom `ColorScheme.dark`, and styled `AppBar` /
  `ElevatedButton` themes. The app forces `ThemeMode.dark`.

Glass effects (nav bar, FAB, cards) are achieved with `BackdropFilter` +
`ImageFilter.blur` over semi-transparent surfaces.

---

## Getting Started

### Prerequisites
- Flutter SDK **3.22 or newer** (developed against a 3.27+ toolchain).
- Dart 3.x.
- A Supabase project (free tier is fine).
- For device/emulator runs: Xcode (iOS) or Android SDK (Android).

### 1. Clone & install
```bash
git clone https://github.com/NO-Group/BookNest.git
cd BookNest
flutter pub get
```

### 2. Configure Supabase
Open `lib/services/supabase_service.dart` and set your project URL and anon key:
```dart
static const String _supabaseUrl = 'https://YOUR-PROJECT.supabase.co';
static const String _supabaseAnonKey = 'YOUR-ANON-KEY';
```
> The anon key is public by design and safe to ship in a client; protect data
> with RLS policies, not by hiding the key.

### 3. Create the backend
Provision the tables listed in [Supabase Backend](#supabase-backend) and enable
RLS with policies that fit your app.

### 4. Run
```bash
flutter run          # emulator / connected device
flutter run -d chrome  # web (great for quick UI checks)
```

---

## Useful Commands

```bash
flutter pub get            # install dependencies
flutter analyze           # static analysis (errors + warnings + lints)
flutter test              # run the widget/unit tests
flutter build apk         # Android release build
flutter build ios         # iOS release build (macOS only)
flutter build web         # web build
```

---

## Testing

`test/widget_test.dart` contains two smoke tests:
- Verifies the dark theme uses the expected background and cyan accent.
- Verifies the router boots to `/splash`.

Run them with:
```bash
flutter test
```

---

## Known Limitations & Placeholders

This is an actively evolving codebase. The following are intentionally
lightweight and expect deeper implementation later:

- **Profile**, **DM chat**, **club chat**, and **book reader** route targets
  (`ProfileScreen`, `DMChatScreen`, `ChatScreen`, `ReaderScreen`) are currently
  minimal stubs.
- **Community / Organization / School detail** screens are placeholders that
  display the entity id; the richer experiences are roadmapped.
- **Reel** creation stores a placeholder record ("video upload coming soon").
- **Bookmark / Like / Comment / Share** actions show confirmation toasts but do
  not yet persist to the backend.
- `flutter_riverpod` and `cached_network_image` are present in `pubspec.yaml`
  but not yet used.

---

## Roadmap

- [ ] Full Profile screen (avatar, bio, authored books, gems).
- [ ] Real-time DM and club chat with message persistence.
- [ ] Rich Book reader with chapters, bookmarks, and reading progress.
- [ ] Complete Community / Organization / School detail experiences.
- [ ] Video upload + playback for Reels.
- [ ] Persisted likes/comments/bookmarks.
- [ ] Adopt `flutter_riverpod` for cross-screen state and
      `cached_network_image` for cover/avatar images.

---

## License & Credits

BookNest is built by **N.O Group**. See the repository for license details.

Built with ❤️ and a lot of Markdown on Flutter + Supabase.
