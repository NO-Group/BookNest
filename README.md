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

## ⚙️ Session Rules (read before every session)

> These are the standing rules for every working session on BookNest. Do not
> repeat them per-session; just follow them.

1. **Keep the README in sync, in detail.** Make detailed and long notes in this
   README on every work you do — what was built, how it works, what was
   decided, what is still missing — so that another session (or developer) can
   carry on with ease. Never delete or rewrite the important stuff that is
   already here; build on it.
2. **Provide Supabase SQL for every backend edit.** Any change that touches the
   database schema, RLS policies, functions/triggers, or realtime publication
   MUST ship with the exact SQL to run (a migration file under
   `supabase/migrations/` **and** the SQL pasted into the
   [Supabase Backend](#supabase-backend) section below).
3. **Scan for errors before building on top.** Before adding new code, check
   the current tree for errors (`flutter analyze`, or a careful manual review
   when the toolchain is unavailable) and fix what you find — so that new work
   never buries pre-existing errors.

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
15. [Development Session Log](#development-session-log)
16. [License & Credits](#license--credits)

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
- **Optional profile photo** at sign-up (picked before registering, uploaded
  in HD to the `avatars` bucket once the account exists).
- A 2-second **splash** screen that routes returning users straight to the feed
  and new users to login — and that listens for the async session restore so a
  slow restore never strands a logged-in user on `/login`.
- A **global auth guard** (`AuthGuard`) that protects interactive actions and a
  router-level redirect that bounces anonymous users away from protected
  routes. The router listens to `auth.onAuthStateChange` (`authRevision`
  `refreshListenable`), so sign-in / sign-out / session expiry re-evaluate
  redirects immediately — this fixed the "logged in but bounced to /login"
  loop.
- A `profiles` row is guaranteed for every signed-in user
  (`ensureProfileForCurrentUser()` runs on login/signup).

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

### 💬 Messages (DMs) (`/dms`)
- Real-time DM inbox: conversation list with partner avatar/name, last-message
  preview, relative timestamps, and unread-count badges.
- Live updates two ways: a Supabase `.stream()` on `conversation_members`
  (new conversations appear instantly) and a realtime "ticker" on `messages`
  that re-orders the list and refreshes previews when a new message lands.
- A compose FAB opens a **New message** sheet that searches `profiles`
  (username/display name) and starts a conversation via the
  `get_or_create_dm(other_user)` RPC — no duplicate conversations.
- Tapping a conversation opens the fullscreen chat (`/dm/:conversationId`):
  - Realtime message bubbles via a `messages` `.stream()` (ascending), rendered
    in a reversed `ListView` so the newest message sits at the bottom.
    Sent bubbles are dark-cyan right-aligned; received bubbles are grey
    left-aligned, with day-aware timestamps.
  - Sending persists a `messages` row; a DB trigger bumps
    `conversations.last_message_at` so the inbox reorders itself.
  - Opening the chat (and while it is open) bumps the user's
    `conversation_members.last_read_at`, clearing the unread badge.

### 👤 Profile (`/profile`)
- Live profile header (streamed from `profiles`): avatar, display name,
  `@username`, bio, gem balance, and join date.
- Stats row: books published · posts made · gems.
- **My Drafts** — personal drafts (`club_books` with `moderation_status =
  'draft'` and no community) with Continue (reopens the editor with the draft
  loaded) and Delete actions.
- **My Books** — the user's `club_books` with Pending/Approved status chips;
  tapping one opens the reader.
- **My Posts** — the user's `posts` with type badges and content previews.
- **Edit profile** sheet: display name, username, bio, and profile photo —
  a gallery picker uploads the original (HD) image to the `avatars` Storage
  bucket, with an optional avatar URL override. The streamed header updates
  instantly.
- **Theme** switcher — System / Light / Dark (N.O Group Black/White scheme;
  persisted with `shared_preferences`, follows system by default).
- **Sign out** (with confirmation dialog) → clears the session and returns to
  `/login`.

### 👥 Groups & Community (`/community/:id`, `/group/:groupId`, `/group-chat/:id`)
- Every entity (community, club, organization, school) gets **groups** with
  chat, backed by the same `conversations`/`messages` infrastructure as DMs:
  - Communities are created with two default groups: an **Announcements**
    group (only owners/admins can post — members can read and react) and a
    normal **Chat** group (everyone chats).
  - Clubs / organizations / schools are created with a default Chat group.
  - Only the **Owner** can create additional groups (`create_group` RPC);
    owners/admins of a group can pin/unpin and delete messages
    (server-enforced trigger), remove regular members and promote members to
    admin — never the owner.
- **Community profile** (`/community/:id`) with Groups / Library / Members
  tabs:
  - *Groups* — list + open group chat; owner-only "New group" button.
  - *Library* — books reposted into the community with status chips. A "+"
    FAB expands vertically (like the Feed stylus) into:
    - **Add** — a picker of all public books with a search bar and a **Hot 🔥**
      section (most-read books, algorithmized from `book_reads` in the last 7
      days + total views); tap to select, Done reposts them into the library.
    - **Write** — reuses the Book editor (`/editor?communityId=…`); saving a
      draft stores it in the community library, publishing submits it as
      pending with the community attached.
  - *Members* — member list where each user who is an admin of one or more
    groups shows "Admin · <group name>" chips beside their name.
- **Group profile** (`/group/:groupId`) — group info, entity it belongs to,
  member list with Owner/Admin/Member roles, promote/demote/remove actions for
  admins, and an "Open chat" button.
- **User profile** (`/user/:userId`) — public view of another reader (avatar,
  bio, gems, published books, posts) with a **Message** button that opens (or
  reuses) a DM.

### 📎 Attachments (paper clip)
- Every chat (DM or group) has a **paper-clip** button → Photo / Video /
  Document.
- Photos, videos and documents are uploaded at **original HD quality** (no
  compression) to the `attachments` Storage bucket.
- Photos show as inline image bubbles (tap to zoom full-screen); videos open
  in a **built-in full-screen player** (`video_player`: play/pause, seek,
  progress); documents (PDF, Word, TXT, …) open in the system default app via
  `url_launcher`.
- The DM inbox preview shows "📷 Photo" / "📎 Attachment" for media messages.

### ✍️ Drafts & read tracking
- The Book editor now has **Save** (draft) + **Publish** buttons. Drafts
  resume from Profile (personal) or the community library (community drafts).
- Opening a book in the reader calls `record_book_read` (one read per user per
  book per day, deduped server-side) — this powers the Hot 🔥 algorithm and
  the view counters shown on book cards / profiles.

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
| `/dms`                | `DMListScreen`            | Tab 4          | **Yes**   |
| `/profile`            | `ProfileScreen`           | Tab 5          | **Yes**   |
| `/editor`             | `BookEditorScreen` (clubId?/communityId?/bookId?) | FAB          | **Yes**   |
| `/publish-details`    | `PublishDetailsScreen`    | Book "Read"    | **Yes**   |
| `/dm/:conversationId` | `ConversationChatScreen`  | DM list tap    | **Yes**   |
| `/group-chat/:conversationId` | `ConversationChatScreen` (group mode) | Group tap | **Yes** |
| `/group/:groupId`     | `GroupProfileScreen`      | Group info     | **Yes**   |
| `/user/:userId`       | `UserProfileScreen`       | Avatar tap     | No        |
| `/community/:id/library/add` | `CommunityAddBooksScreen` | Library "+" → Add | **Yes*** |
| `/create/quote`       | `CreateQuoteScreen`       | FAB            | **Yes**   |
| `/create/news`        | `CreateNewsScreen`        | FAB            | **Yes**   |
| `/create/poll`        | `CreatePollScreen`        | FAB            | **Yes**   |
| `/create/event`       | `CreateEventScreen`       | FAB            | **Yes**   |
| `/create/reel`        | `CreateReelScreen`        | FAB            | **Yes**   |
| `/create/club`        | `CreateClubScreen`        | FAB            | **Yes**   |
| `/create/community`   | `CreateCommunityScreen`   | FAB            | **Yes**   |
| `/create/organization`| `CreateOrganizationScreen`| FAB            | **Yes**   |
| `/create/school`      | `CreateSchoolScreen`      | FAB            | **Yes**   |
| `/club/:id`           | `ClubDetailScreen` (with Groups & Chat panel) | Card tap | No   |
| `/community/:id`      | `CommunityDetailScreen` (Groups/Library/Members) | Card tap | No |
| `/organization/:id`   | `OrganizationDetailScreen` (with Groups & Chat panel) | Card tap | No |
| `/school/:id`         | `SchoolDetailScreen` (with Groups & Chat panel) | Card tap | No |

\* The `/community/:id/library` prefix is additionally protected (member-only)
via a regex in `_redirect`. The login/register routes are *redirect targets*
for signed-out users; once authenticated, visiting them bounces you to
`/feed`.

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
| Image picking      | `image_picker` `^1.1.2` (avatars + HD photo/video attachments) |
| Video playback     | `video_player` `^2.9.2` (in-app HD video playback) |
| File picking       | `file_picker` `^8.1.2` (document attachments) |
| URL launching      | `url_launcher` `^6.3.0` (open document attachments externally) |
| Preferences        | `shared_preferences` `^2.3.2` (persists the theme mode) |
| Dates              | `intl` `^0.20.3`                                  |
| Lints              | `flutter_lints` `^6.0.0`                          |

> **Note:** `flutter_riverpod` and `cached_network_image` are declared in
> `pubspec.yaml` for upcoming features but are not imported by the current
> source, so they have no effect yet.

---

## Project Structure

```
lib/
├── main.dart                      # App entry: init Supabase, theme controller, router
├── config/
│   ├── constants.dart             # (reserved for shared constants)
│   ├── router.dart                # go_router tree + global auth redirect
│   ├── theme.dart                 # N.O palette (deep blue + 0.1% cyan) + light/dark ThemeData + Glass helpers
│   └── theme_controller.dart      # ThemeController (System/Light/Dark) + global instance
├── core/
│   └── utils/
│       ├── auth_guard.dart        # AuthGuard.run / isAuthenticated
│       └── time_format.dart       # Relative time / chat timestamps / full dates
├── services/
│   └── supabase_service.dart      # Singleton wrapper + uploadPublicImage (Storage)
└── presentation/
    ├── components/
    │   ├── booknest_bottom_nav.dart   # 5-tab nav + center FAB
    │   ├── user_avatar.dart           # Reusable initials/image avatar
    │   └── entity_groups_panel.dart   # Groups & Chat section for club/org/school details
    └── screens/
        ├── splash/splash_screen.dart
        ├── auth/
        │   ├── login_screen.dart
        │   └── register_screen.dart
        ├── main_shell.dart            # StatefulNavigationShell host
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
        │   ├── community_detail_screen.dart       # Full: Groups / Library / Members
        │   ├── community_add_books_screen.dart    # Library "+" → Add picker (search + Hot 🔥)
        │   ├── organization_detail_screen.dart
        │   └── school_detail_screen.dart
        ├── books/
        │   ├── books_library_screen.dart
        │   ├── book_editor_screen.dart    # Save (draft) + Publish; community context; edit drafts
        │   └── publish_details_screen.dart # Records reads (Hot 🔥) + shows views
        ├── clubs/
        │   ├── clubs_list_screen.dart
        │   └── club_detail_screen.dart    # Identity + Groups & Chat panel
        ├── dms/
        │   ├── dm_list_screen.dart        # Realtime DM inbox (Tab 4)
        │   └── dm_chat_screen.dart        # ConversationChatScreen: DMs + group chat
        ├── groups/
        │   └── group_profile_screen.dart  # Group info, members, roles, admin actions
        ├── chat/
        │   └── chat_screen.dart           # Legacy stub (superseded by group chat)
        ├── reader/
        │   └── reader_screen.dart         # Book reader stub (roadmapped)
        └── profile/
            ├── profile_screen.dart        # Full profile (Tab 5): drafts, theme toggle, avatar upload
            └── user_profile_screen.dart   # Public profile of another user (/user/:id)
supabase/
└── migrations/
    ├── 0001_messages_and_profile.sql        # DMs + profile fields (see below)
    └── 0002_groups_communities_roles.sql    # Groups, community core, roles, reads, storage
test/
└── widget_test.dart              # Theme (N.O light+dark) + router smoke tests
```


#### Migration 0002 — full SQL

<details>
<summary>Click to expand <code>0002_groups_communities_roles.sql</code> (~908 lines)</summary>

```sql
-- ============================================================================
-- BookNest — Migration 0002: Groups (all entities), community core, roles,
--                            read tracking (Hot 🔥), drafts, storage buckets
-- ============================================================================
-- Adds:
--   1. `club_books.community_id` + `'draft'` moderation status + `views` count.
--   2. `groups` (one per entity type: community/club/organization/school),
--      `group_members` (owner/admin/member), `message_reactions`,
--      `book_reads` (read log), `community_books` (community library reposts).
--   3. Roles: entity Owner (ultimate) vs per-group Admin (delete/pin messages,
--      remove normal members, promote members to admin — never touch the owner).
--   4. Default groups auto-created on entity creation: communities get an
--      Announcements group (admin/owner-only posting) + a normal Chat group;
--      clubs/organizations/schools get a normal Chat group. Owner-only group
--      creation afterwards via the `create_group` RPC.
--   5. Sync triggers: joining/leaving an entity adds/removes the user in all
--      of that entity's groups + group conversations.
--   6. RPCs: `record_book_read` (deduped, powers Hot 🔥), `get_hot_books`,
--      `create_group` (owner-only), `is_entity_member` / `is_entity_owner`
--      helpers.
--   7. Storage buckets `avatars` + `attachments` (public read, authenticated
--      upload) for profile pictures (now) and HD attachments (next session).
--
-- Re-runnable (DROP ... IF EXISTS / IF NOT EXISTS guards).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. club_books: community linkage, draft status, views counter
-- ----------------------------------------------------------------------------
alter table club_books add column if not exists community_id uuid
  references communities(id) on delete set null;
alter table club_books add column if not exists views integer not null default 0;

alter table club_books drop constraint if exists club_books_moderation_status_check;
alter table club_books add constraint club_books_moderation_status_check
  check (moderation_status in ('draft', 'pending', 'approved', 'rejected'));

-- ----------------------------------------------------------------------------
-- 2. conversation_members: add 'admin' role (group admins)
-- ----------------------------------------------------------------------------
alter table conversation_members drop constraint if exists conversation_members_role_check;
alter table conversation_members add constraint conversation_members_role_check
  check (role in ('owner', 'admin', 'moderator', 'member'));

-- ----------------------------------------------------------------------------
-- 3. messages: pinned flag
-- ----------------------------------------------------------------------------
alter table messages add column if not exists is_pinned boolean not null default false;

-- ----------------------------------------------------------------------------
-- 4. New tables
-- ----------------------------------------------------------------------------
create table if not exists groups (
  id              uuid primary key default gen_random_uuid(),
  entity_type     text not null check (entity_type in ('community', 'club', 'organization', 'school')),
  entity_id       uuid not null,
  name            text not null,
  group_type      text not null default 'regular' check (group_type in ('announcement', 'regular')),
  conversation_id uuid not null references conversations(id) on delete cascade,
  is_default      boolean not null default false,
  created_by      uuid references profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  unique (entity_type, entity_id, name)
);

create index if not exists groups_entity_idx on groups (entity_type, entity_id);
create index if not exists groups_conversation_idx on groups (conversation_id);

create table if not exists group_members (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references groups(id) on delete cascade,
  user_id    uuid not null references profiles(id) on delete cascade,
  role       text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at  timestamptz not null default now(),
  unique (group_id, user_id)
);

create index if not exists group_members_user_idx on group_members (user_id);
create index if not exists group_members_group_idx on group_members (group_id);

create table if not exists message_reactions (
  id         uuid primary key default gen_random_uuid(),
  message_id uuid not null references messages(id) on delete cascade,
  user_id    uuid not null references profiles(id) on delete cascade,
  reaction   text not null default 'like',
  created_at timestamptz not null default now(),
  unique (message_id, user_id)
);

create table if not exists book_reads (
  id           uuid primary key default gen_random_uuid(),
  club_book_id uuid not null references club_books(id) on delete cascade,
  user_id      uuid references profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);

create index if not exists book_reads_book_created_idx
  on book_reads (club_book_id, created_at);

create table if not exists community_books (
  id            uuid primary key default gen_random_uuid(),
  community_id  uuid not null references communities(id) on delete cascade,
  club_book_id  uuid not null references club_books(id) on delete cascade,
  added_by      uuid references profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  unique (community_id, club_book_id)
);

-- ----------------------------------------------------------------------------
-- 5. Unique pair constraints on entity member tables (needed by sync triggers
--    and backfill idempotency)
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'community_members_pair') then
    alter table community_members add constraint community_members_pair unique (community_id, user_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'club_members_pair') then
    alter table club_members add constraint club_members_pair unique (club_id, user_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'organization_members_pair') then
    alter table organization_members add constraint organization_members_pair unique (organization_id, user_id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'school_members_pair') then
    alter table school_members add constraint school_members_pair unique (school_id, user_id);
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 6. Helper functions: entity membership / ownership
-- ----------------------------------------------------------------------------
create or replace function is_entity_member(e_type text, e_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case e_type
    when 'community'    then exists (select 1 from community_members cm where cm.community_id = e_id and cm.user_id = uid)
    when 'club'         then exists (select 1 from club_members cm where cm.club_id = e_id and cm.user_id = uid)
    when 'organization' then exists (select 1 from organization_members cm where cm.organization_id = e_id and cm.user_id = uid)
    when 'school'       then exists (select 1 from school_members cm where cm.school_id = e_id and cm.user_id = uid)
    else false
  end;
$$;

create or replace function is_entity_owner(e_type text, e_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case e_type
    when 'community'    then exists (select 1 from communities c where c.id = e_id and c.owner_id = uid)
    when 'club'         then exists (select 1 from clubs c where c.id = e_id and c.owner_id = uid)
    when 'organization' then exists (select 1 from organizations c where c.id = e_id and c.owner_id = uid)
    when 'school'       then exists (select 1 from schools c where c.id = e_id and c.owner_id = uid)
    else false
  end;
$$;

create or replace function entity_owner_id(e_type text, e_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select case e_type
    when 'community'    then (select owner_id from communities where id = e_id)
    when 'club'         then (select owner_id from clubs where id = e_id)
    when 'organization' then (select owner_id from organizations where id = e_id)
    when 'school'       then (select owner_id from schools where id = e_id)
  end;
$$;

-- ----------------------------------------------------------------------------
-- 7. Default groups on entity creation + member seeding
-- ----------------------------------------------------------------------------
create or replace function seed_group_members(gid uuid, e_type text, e_id uuid, owner uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Entity members (excluding the owner) become regular members.
  if e_type = 'community' then
    insert into group_members (group_id, user_id, role)
    select gid, cm.user_id, 'member' from community_members cm
    where cm.community_id = e_id and cm.user_id <> owner
    on conflict (group_id, user_id) do nothing;
    insert into conversation_members (conversation_id, user_id)
    select g.conversation_id, cm.user_id
    from groups g cross join community_members cm
    where g.id = gid and cm.community_id = e_id and cm.user_id <> owner
    on conflict (conversation_id, user_id) do nothing;
  elsif e_type = 'club' then
    insert into group_members (group_id, user_id, role)
    select gid, cm.user_id, 'member' from club_members cm
    where cm.club_id = e_id and cm.user_id <> owner
    on conflict (group_id, user_id) do nothing;
    insert into conversation_members (conversation_id, user_id)
    select g.conversation_id, cm.user_id
    from groups g cross join club_members cm
    where g.id = gid and cm.club_id = e_id and cm.user_id <> owner
    on conflict (conversation_id, user_id) do nothing;
  elsif e_type = 'organization' then
    insert into group_members (group_id, user_id, role)
    select gid, cm.user_id, 'member' from organization_members cm
    where cm.organization_id = e_id and cm.user_id <> owner
    on conflict (group_id, user_id) do nothing;
    insert into conversation_members (conversation_id, user_id)
    select g.conversation_id, cm.user_id
    from groups g cross join organization_members cm
    where g.id = gid and cm.organization_id = e_id and cm.user_id <> owner
    on conflict (conversation_id, user_id) do nothing;
  elsif e_type = 'school' then
    insert into group_members (group_id, user_id, role)
    select gid, cm.user_id, 'member' from school_members cm
    where cm.school_id = e_id and cm.user_id <> owner
    on conflict (group_id, user_id) do nothing;
    insert into conversation_members (conversation_id, user_id)
    select g.conversation_id, cm.user_id
    from groups g cross join school_members cm
    where g.id = gid and cm.school_id = e_id and cm.user_id <> owner
    on conflict (conversation_id, user_id) do nothing;
  end if;
end;
$$;

create or replace function ensure_entity_default_groups(p_type text, p_id uuid, p_owner uuid, p_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  conv uuid;
  gid  uuid;
begin
  -- Communities get an Announcements group (admin/owner-only posting).
  if p_type = 'community' and not exists (
    select 1 from groups where entity_type = p_type and entity_id = p_id and group_type = 'announcement'
  ) then
    insert into conversations (type, title, created_by)
    values ('group', p_name || ' Announcements', p_owner) returning id into conv;
    insert into groups (entity_type, entity_id, name, group_type, conversation_id, is_default, created_by)
    values (p_type, p_id, p_name || ' Announcements', 'announcement', conv, true, p_owner)
    returning id into gid;
    insert into conversation_members (conversation_id, user_id, role) values (conv, p_owner, 'owner');
    insert into group_members (group_id, user_id, role) values (gid, p_owner, 'owner');
    perform seed_group_members(gid, p_type, p_id, p_owner);
  end if;

  -- Every entity gets a default Chat group (everyone can talk).
  if not exists (
    select 1 from groups where entity_type = p_type and entity_id = p_id and is_default and group_type = 'regular'
  ) then
    insert into conversations (type, title, created_by)
    values ('group', p_name || ' Chat', p_owner) returning id into conv;
    insert into groups (entity_type, entity_id, name, group_type, conversation_id, is_default, created_by)
    values (p_type, p_id, p_name || ' Chat', 'regular', conv, true, p_owner)
    returning id into gid;
    insert into conversation_members (conversation_id, user_id, role) values (conv, p_owner, 'owner');
    insert into group_members (group_id, user_id, role) values (gid, p_owner, 'owner');
    perform seed_group_members(gid, p_type, p_id, p_owner);
  end if;
end;
$$;

-- Trigger wrappers per entity table
create or replace function ensure_entity_default_groups_trigger()
returns trigger
language plpgsql
as $$
begin
  perform ensure_entity_default_groups(
    (case when TG_TABLE_NAME = 'communities' then 'community'
          when TG_TABLE_NAME = 'clubs' then 'club'
          when TG_TABLE_NAME = 'organizations' then 'organization'
          when TG_TABLE_NAME = 'schools' then 'school' end),
    new.id,
    new.owner_id,
    coalesce(new.name, 'Community')
  );
  return new;
end;
$$;

drop trigger if exists communities_ensure_default_groups on communities;
create trigger communities_ensure_default_groups
  after insert on communities for each row execute function ensure_entity_default_groups_trigger();

drop trigger if exists clubs_ensure_default_groups on clubs;
create trigger clubs_ensure_default_groups
  after insert on clubs for each row execute function ensure_entity_default_groups_trigger();

drop trigger if exists organizations_ensure_default_groups on organizations;
create trigger organizations_ensure_default_groups
  after insert on organizations for each row execute function ensure_entity_default_groups_trigger();

drop trigger if exists schools_ensure_default_groups on schools;
create trigger schools_ensure_default_groups
  after insert on schools for each row execute function ensure_entity_default_groups_trigger();

-- ----------------------------------------------------------------------------
-- 8. Sync triggers: joining/leaving an entity joins/leaves all its groups
-- ----------------------------------------------------------------------------
create or replace function sync_entity_member_to_groups()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  e_type text;
  e_id   uuid;
  uid    uuid;
begin
  case TG_TABLE_NAME
    when 'community_members' then
      e_type := 'community'; e_id := coalesce(new.community_id, old.community_id); uid := coalesce(new.user_id, old.user_id);
    when 'club_members' then
      e_type := 'club'; e_id := coalesce(new.club_id, old.club_id); uid := coalesce(new.user_id, old.user_id);
    when 'organization_members' then
      e_type := 'organization'; e_id := coalesce(new.organization_id, old.organization_id); uid := coalesce(new.user_id, old.user_id);
    when 'school_members' then
      e_type := 'school'; e_id := coalesce(new.school_id, old.school_id); uid := coalesce(new.user_id, old.user_id);
    else
      return null;
  end case;

  if TG_OP = 'INSERT' then
    insert into group_members (group_id, user_id, role)
    select g.id, uid, 'member' from groups g
    where g.entity_type = e_type and g.entity_id = e_id
    on conflict (group_id, user_id) do nothing;

    insert into conversation_members (conversation_id, user_id, role)
    select g.conversation_id, uid, 'member' from groups g
    where g.entity_type = e_type and g.entity_id = e_id
    on conflict (conversation_id, user_id) do nothing;
  elsif TG_OP = 'DELETE' then
    delete from group_members gm
    using groups g
    where gm.group_id = g.id and g.entity_type = e_type and g.entity_id = e_id
      and gm.user_id = uid and gm.role = 'member';

    delete from conversation_members cm
    using groups g
    where cm.conversation_id = g.conversation_id and g.entity_type = e_type and g.entity_id = e_id
      and cm.user_id = uid;
  end if;

  return null;
end;
$$;

drop trigger if exists sync_community_members_groups on community_members;
create trigger sync_community_members_groups
  after insert or delete on community_members for each row execute function sync_entity_member_to_groups();

drop trigger if exists sync_club_members_groups on club_members;
create trigger sync_club_members_groups
  after insert or delete on club_members for each row execute function sync_entity_member_to_groups();

drop trigger if exists sync_organization_members_groups on organization_members;
create trigger sync_organization_members_groups
  after insert or delete on organization_members for each row execute function sync_entity_member_to_groups();

drop trigger if exists sync_school_members_groups on school_members;
create trigger sync_school_members_groups
  after insert or delete on school_members for each row execute function sync_entity_member_to_groups();

-- ----------------------------------------------------------------------------
-- 9. Owner-only group creation RPC
-- ----------------------------------------------------------------------------
create or replace function create_group(e_type text, e_id uuid, group_name text, g_type text default 'regular')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  gid uuid;
  conv uuid;
  owner uuid;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  if g_type not in ('announcement', 'regular') then
    raise exception 'Invalid group type';
  end if;
  if not is_entity_owner(e_type, e_id, uid) then
    raise exception 'Only the owner can create groups';
  end if;
  if exists (select 1 from groups where entity_type = e_type and entity_id = e_id and name = group_name) then
    raise exception 'A group with this name already exists';
  end if;

  owner := entity_owner_id(e_type, e_id);
  insert into conversations (type, title, created_by)
  values ('group', group_name, uid) returning id into conv;

  insert into groups (entity_type, entity_id, name, group_type, conversation_id, is_default, created_by)
  values (e_type, e_id, group_name, g_type, conv, false, uid)
  returning id into gid;

  insert into conversation_members (conversation_id, user_id, role) values (conv, owner, 'owner');
  insert into group_members (group_id, user_id, role) values (gid, owner, 'owner');
  perform seed_group_members(gid, e_type, e_id, owner);

  return gid;
end;
$$;

revoke all on function create_group(text, uuid, text, text) from public;
grant execute on function create_group(text, uuid, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 10. Read tracking (Hot 🔥)
-- ----------------------------------------------------------------------------
create or replace function record_book_read(book_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  insert into book_reads (club_book_id, user_id)
  select book_id, auth.uid()
  where auth.uid() is not null
    and not exists (
      select 1 from book_reads br
      where br.club_book_id = book_id and br.user_id = auth.uid()
        and br.created_at > now() - interval '1 day'
    );
$$;

revoke all on function record_book_read(uuid) from public;
grant execute on function record_book_read(uuid) to authenticated;

-- Keep club_books.views in sync with the read log (drives Hot 🔥 tie-break
-- and the view counters shown on book cards / profiles).
create or replace function book_reads_bump_views()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update club_books set views = views + 1 where id = new.club_book_id;
  return new;
end;
$$;

drop trigger if exists book_reads_bump_views on book_reads;
create trigger book_reads_bump_views
  after insert on book_reads
  for each row execute function book_reads_bump_views();

create or replace function get_hot_books(days int default 7, max_count int default 30)
returns setof club_books
language sql
stable
security definer
set search_path = public
as $$
  select cb.*
  from club_books cb
  where cb.moderation_status = 'approved'
  order by (
    select count(*) from book_reads br
    where br.club_book_id = cb.id and br.created_at > now() - make_interval(days => days)
  ) desc, cb.views desc, cb.created_at desc
  limit max_count;
$$;

revoke all on function get_hot_books(int, int) from public;
grant execute on function get_hot_books(int, int) to authenticated;

-- ----------------------------------------------------------------------------
-- 11. Row Level Security
-- ----------------------------------------------------------------------------
alter table groups enable row level security;
alter table group_members enable row level security;
alter table message_reactions enable row level security;
alter table book_reads enable row level security;
alter table community_books enable row level security;

-- club_books: approved = public; drafts/pending = author or community members
alter table club_books enable row level security;

drop policy if exists "public reads approved books" on club_books;
create policy "public reads approved books"
  on club_books for select
  using (
    moderation_status = 'approved'
    or added_by = auth.uid()
    or exists (
      select 1 from community_members cm
      where cm.community_id = club_books.community_id and cm.user_id = auth.uid()
    )
  );

drop policy if exists "authors insert books" on club_books;
create policy "authors insert books"
  on club_books for insert
  with check (added_by = auth.uid());

drop policy if exists "authors update their books" on club_books;
create policy "authors update their books"
  on club_books for update
  using (added_by = auth.uid())
  with check (added_by = auth.uid());

drop policy if exists "authors delete their books" on club_books;
create policy "authors delete their books"
  on club_books for delete
  using (added_by = auth.uid());

-- groups ----------------------------------------------------------------------
drop policy if exists "entity members can view groups" on groups;
create policy "entity members can view groups"
  on groups for select
  using (
    is_entity_member(entity_type, entity_id, auth.uid())
    or is_entity_owner(entity_type, entity_id, auth.uid())
    or exists (
      select 1 from group_members gm
      where gm.group_id = groups.id and gm.user_id = auth.uid()
    )
  );

-- group_members ---------------------------------------------------------------
drop policy if exists "group members can view members" on group_members;
create policy "group members can view members"
  on group_members for select
  using (
    exists (
      select 1 from group_members gm2
      where gm2.group_id = group_id and gm2.user_id = auth.uid()
    )
    or is_entity_member(
         (select entity_type from groups g where g.id = group_id),
         (select entity_id from groups g where g.id = group_id),
         auth.uid())
    or is_entity_owner(
         (select entity_type from groups g where g.id = group_id),
         (select entity_id from groups g where g.id = group_id),
         auth.uid())
  );

drop policy if exists "admins can add members" on group_members;
create policy "admins can add members"
  on group_members for insert
  with check (
    exists (
      select 1 from group_members gm2
      where gm2.group_id = group_id and gm2.user_id = auth.uid()
        and gm2.role in ('owner', 'admin')
    )
    and is_entity_member(
          (select entity_type from groups g where g.id = group_id),
          (select entity_id from groups g where g.id = group_id),
          user_id)
  );

drop policy if exists "admins can manage members" on group_members;
create policy "admins can manage members"
  on group_members for update
  using (
    exists (
      select 1 from group_members gm2
      where gm2.group_id = group_id and gm2.user_id = auth.uid()
        and gm2.role in ('owner', 'admin')
    )
    and user_id <> (
      select entity_owner_id(g.entity_type, g.entity_id)
      from groups g where g.id = group_id
    )
  );

drop policy if exists "admins can remove members" on group_members;
create policy "admins can remove members"
  on group_members for delete
  using (
    role = 'member'
    and exists (
      select 1 from group_members gm2
      where gm2.group_id = group_id and gm2.user_id = auth.uid()
        and gm2.role in ('owner', 'admin')
    )
    and user_id <> (
      select entity_owner_id(g.entity_type, g.entity_id)
      from groups g where g.id = group_id
    )
  );

-- messages: announcement groups are owner/admin-only for posting --------------
drop policy if exists "members can send messages" on messages;
create policy "members can send messages"
  on messages for insert
  with check (
    auth.uid() = sender_id
    and exists (
      select 1 from conversation_members cm
      where cm.conversation_id = messages.conversation_id
        and cm.user_id = auth.uid()
    )
    and (
      not exists (
        select 1 from groups g
        where g.conversation_id = messages.conversation_id
          and g.group_type = 'announcement'
      )
      or exists (
        select 1 from groups g
        join group_members gm on gm.group_id = g.id
        where g.conversation_id = messages.conversation_id
          and g.group_type = 'announcement'
          and gm.user_id = auth.uid()
          and gm.role in ('owner', 'admin')
      )
    )
  );

drop policy if exists "members can delete their own messages" on messages;
create policy "members can delete their own messages"
  on messages for delete
  using (
    auth.uid() = sender_id
    or exists (
      select 1 from groups g
      join group_members gm on gm.group_id = g.id
      where g.conversation_id = messages.conversation_id
        and gm.user_id = auth.uid()
        and gm.role in ('owner', 'admin')
    )
  );

drop policy if exists "admins can update group messages" on messages;
create policy "admins can update group messages"
  on messages for update
  using (
    exists (
      select 1 from groups g
      join group_members gm on gm.group_id = g.id
      where g.conversation_id = messages.conversation_id
        and gm.user_id = auth.uid()
        and gm.role in ('owner', 'admin')
    )
  );

-- Pin guard: only owners/admins of the group may pin messages. (Triggers run
-- with the definer's privileges; check group_members explicitly.)
create or replace function enforce_pin_permission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_pinned is distinct from old.is_pinned then
    if not exists (
      select 1 from groups g
      join group_members gm on gm.group_id = g.id
      where g.conversation_id = new.conversation_id
        and gm.user_id = auth.uid()
        and gm.role in ('owner', 'admin')
    ) then
      raise exception 'Only group admins can pin messages';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists messages_pin_permission on messages;
create trigger messages_pin_permission
  before update of is_pinned on messages
  for each row execute function enforce_pin_permission();

-- message_reactions ------------------------------------------------------------
drop policy if exists "conversation members can react" on message_reactions;
create policy "conversation members can react"
  on message_reactions for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from messages m
      join conversation_members cm on cm.conversation_id = m.conversation_id
      where m.id = message_id and cm.user_id = auth.uid()
    )
  );

drop policy if exists "conversation members can view reactions" on message_reactions;
create policy "conversation members can view reactions"
  on message_reactions for select
  using (
    exists (
      select 1 from messages m
      join conversation_members cm on cm.conversation_id = m.conversation_id
      where m.id = message_id and cm.user_id = auth.uid()
    )
  );

drop policy if exists "users can remove their own reactions" on message_reactions;
create policy "users can remove their own reactions"
  on message_reactions for delete
  using (auth.uid() = user_id);

-- book_reads: private log; only the RPCs touch it -----------------------------
drop policy if exists "users can view their own reads" on book_reads;
create policy "users can view their own reads"
  on book_reads for select
  using (user_id = auth.uid());

-- community_books ---------------------------------------------------------------
drop policy if exists "members can view community books" on community_books;
create policy "members can view community books"
  on community_books for select
  using (
    exists (
      select 1 from community_members cm
      where cm.community_id = community_id and cm.user_id = auth.uid()
    )
    or exists (
      select 1 from communities c where c.id = community_id and c.owner_id = auth.uid()
    )
  );

drop policy if exists "members can add community books" on community_books;
create policy "members can add community books"
  on community_books for insert
  with check (
    exists (
      select 1 from community_members cm
      where cm.community_id = community_id and cm.user_id = auth.uid()
    )
    or exists (
      select 1 from communities c where c.id = community_id and c.owner_id = auth.uid()
    )
  );

drop policy if exists "adders can remove community books" on community_books;
create policy "adders can remove community books"
  on community_books for delete
  using (
    added_by = auth.uid()
    or exists (
      select 1 from communities c where c.id = community_id and c.owner_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- 12. DM list: only direct conversations (groups get their own list)
-- ----------------------------------------------------------------------------
create or replace function get_my_conversations()
returns table (
  conversation_id         uuid,
  conversation_created_at timestamptz,
  last_message_at         timestamptz,
  last_message            text,
  last_message_type       text,
  last_sender_id          uuid,
  unread_count            bigint,
  partner_user_id         uuid,
  partner_username        text,
  partner_display_name    text,
  partner_avatar_url      text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    c.id,
    c.created_at,
    c.last_message_at,
    lm.content,
    lm.type,
    lm.sender_id,
    (
      select count(*)
      from messages m
      where m.conversation_id = c.id
        and m.sender_id <> auth.uid()
        and m.created_at > coalesce(
              (select cm.last_read_at
               from conversation_members cm
               where cm.conversation_id = c.id and cm.user_id = auth.uid()),
              '-infinity'::timestamptz
            )
    )::bigint,
    p.id,
    p.username,
    p.display_name,
    p.avatar_url
  from conversations c
  join conversation_members me
    on me.conversation_id = c.id and me.user_id = auth.uid()
  join conversation_members partner
    on partner.conversation_id = c.id and partner.user_id <> auth.uid()
  join profiles p on p.id = partner.user_id
  left join lateral (
    select m.content, m.type, m.sender_id
    from messages m
    where m.conversation_id = c.id
    order by m.created_at desc, m.id desc
    limit 1
  ) lm on true
  where c.type = 'direct'
  order by c.last_message_at desc;
$$;

revoke all on function get_my_conversations() from public;
grant execute on function get_my_conversations() to authenticated;

-- ----------------------------------------------------------------------------
-- 13. Storage buckets: avatars + attachments
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true),
       ('attachments', 'attachments', true)
on conflict (id) do nothing;

drop policy if exists "public read media" on storage.objects;
create policy "public read media"
  on storage.objects for select
  using (bucket_id in ('avatars', 'attachments'));

drop policy if exists "authenticated upload media" on storage.objects;
create policy "authenticated upload media"
  on storage.objects for insert
  with check (
    bucket_id in ('avatars', 'attachments')
    and auth.role() = 'authenticated'
  );

drop policy if exists "owners update media" on storage.objects;
create policy "owners update media"
  on storage.objects for update
  using (
    bucket_id in ('avatars', 'attachments')
    and owner = auth.uid()
  );

-- ----------------------------------------------------------------------------
-- 14. Backfill for existing data
-- ----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  -- Owners into their entity member tables (creates group membership too via
  -- the sync triggers on INSERT).
  for r in select id, owner_id from communities where owner_id is not null loop
    insert into community_members (community_id, user_id, role) values (r.id, r.owner_id, 'owner')
    on conflict (community_id, user_id) do nothing;
  end loop;
  for r in select id, owner_id from clubs where owner_id is not null loop
    insert into club_members (club_id, user_id, role) values (r.id, r.owner_id, 'owner')
    on conflict (club_id, user_id) do nothing;
  end loop;
  for r in select id, owner_id from organizations where owner_id is not null loop
    insert into organization_members (organization_id, user_id, role) values (r.id, r.owner_id, 'owner')
    on conflict (organization_id, user_id) do nothing;
  end loop;
  for r in select id, owner_id from schools where owner_id is not null loop
    insert into school_members (school_id, user_id, role) values (r.id, r.owner_id, 'owner')
    on conflict (school_id, user_id) do nothing;
  end loop;

  -- Default groups for everything that already exists.
  for r in select id, owner_id, name from communities loop
    perform ensure_entity_default_groups('community', r.id, r.owner_id, coalesce(r.name, 'Community'));
  end loop;
  for r in select id, owner_id, name from clubs loop
    perform ensure_entity_default_groups('club', r.id, r.owner_id, coalesce(r.name, 'Club'));
  end loop;
  for r in select id, owner_id, name from organizations loop
    perform ensure_entity_default_groups('organization', r.id, r.owner_id, coalesce(r.name, 'Organization'));
  end loop;
  for r in select id, owner_id, name from schools loop
    perform ensure_entity_default_groups('school', r.id, r.owner_id, coalesce(r.name, 'School'));
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 15. Realtime publication for the new tables
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['groups', 'group_members', 'message_reactions', 'book_reads', 'community_books'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table %I', t);
    end if;
  end loop;
end $$;
```
</details>

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
- **DMs** are stream-driven in the same style:
  - `DMListScreen` streams `conversation_members` (filtered to the current
    user) so the membership set is live, plus a realtime channel on `messages`
    ("ticker") that triggers a debounced re-fetch. The list rows themselves
    come from the `get_my_conversations()` RPC (partner + last message +
    unread count in one query) because `SupabaseStreamBuilder` cannot embed
    relations (`select()` is not exposed on streams — verified against
    supabase-dart 2.14.0).
  - `DMChatScreen` streams `messages` (filtered by `conversation_id`,
    ascending) and renders them in a reversed `ListView`; sending is a plain
    insert. A DB trigger maintains `conversations.last_message_at`, and a
    5-second timer bumps the user's `last_read_at` while the chat is open.
- **Profile** streams the user's own `profiles` row (so edits appear
  instantly) and fetches `club_books` / `posts` one-shot for the My Books /
  My Posts sections.
- **Groups & community**:
  - Every entity has a `groups` row per chat group; each group owns a
    `conversations` row (type `group`), so messages reuse the exact same
    stream + bubble pipeline as DMs. `conversation_members` /
    `group_members` are kept in sync by DB triggers when users join/leave an
    entity, and default groups (Announcements + Chat for communities; Chat
    for clubs/orgs/schools) are created by triggers on entity insert.
  - Group chat (`ConversationChatScreen` in group mode) loads sender
    profiles from `group_members`, shows sender names, hearts (reactions →
    `message_reactions`), and admin long-press actions (pin/delete). The
    announcement post restriction is enforced by RLS **and** the pin guard by
    a trigger.
  - `CommunityDetailScreen` pulls groups, library entries
    (`community_books` → `club_books`), members and per-member admin group
    names in one `_load()`; the library FAB expands Add/Write like the Feed
    stylus. Adding books goes through `CommunityAddBooksScreen`
    (Hot 🔥 from the `get_hot_books` RPC).
  - Drafts are `club_books.moderation_status = 'draft'`; personal drafts have
    `community_id = null` (Profile tab), community drafts carry the
    `community_id` (community library).
- **Read tracking**: opening a book fires `record_book_read` (deduped to one
  per user per book per day); a trigger bumps `club_books.views`. Hot 🔥 =
  reads in the last 7 days, then total views.

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
| `profiles`           | `id` (uuid, = auth user), `username`, `display_name`, `phone_number`, `gems` (int, default 77), `avatar_url` (text), `bio` (text, default '') |
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
| `conversations`      | `id`, `type` ('direct'/'group'/'channel'), `title`, `avatar_url`, `created_by`, `created_at`, `last_message_at` |
| `conversation_members`| `id`, `conversation_id`, `user_id`, `role` ('owner'/'admin'/'moderator'/'member'), `last_read_at`, `joined_at`, unique(`conversation_id`,`user_id`) |
| `messages`           | `id`, `conversation_id`, `sender_id`, `type` ('text'/'image'/'file'/'system'), `content`, `metadata` (jsonb), `reply_to`, `edited_at`, `created_at`, `is_pinned` (bool) |
| `groups`             | `id`, `entity_type` ('community'/'club'/'organization'/'school'), `entity_id`, `name`, `group_type` ('announcement'/'regular'), `conversation_id` → conversations, `is_default`, `created_by`, `created_at` |
| `group_members`      | `id`, `group_id`, `user_id`, `role` ('owner'/'admin'/'member'), `joined_at`, unique(`group_id`,`user_id`) |
| `message_reactions`  | `id`, `message_id`, `user_id`, `reaction` (default 'like'), `created_at`, unique(`message_id`,`user_id`) |
| `book_reads`         | `id`, `club_book_id`, `user_id`, `created_at` (read log — powers Hot 🔥) |
| `community_books`    | `id`, `community_id`, `club_book_id`, `added_by`, `created_at`, unique(`community_id`,`club_book_id`) |

`club_books` additionally gained `community_id` (nullable), `views` (int) and
a `moderation_status` check that now includes `'draft'`.

**RPCs added by migration 0002** (all granted to `authenticated` only):
- `create_group(e_type text, e_id uuid, group_name text, g_type text)` —
  owner-only group creation; seeds members + the group conversation.
- `record_book_read(book_id uuid)` — deduped read log insert (1/user/book/day).
- `get_hot_books(days int, max_count int)` — most-read approved books.
- `is_entity_member` / `is_entity_owner` / `entity_owner_id` — helpers used by
  RLS policies and `create_group`.

**Triggers added by migration 0002:**
- `ensure_entity_default_groups_trigger` (communities/clubs/organizations/
  schools INSERT) — creates the default groups + conversation + memberships.
- `sync_entity_member_to_groups` (member-table INSERT/DELETE) — joins/leaves
  all groups of the entity.
- `messages_pin_permission` (messages UPDATE of `is_pinned`) — admins only.
- `book_reads_bump_views` — bumps `club_books.views` on each read.

**Storage buckets:** `avatars` + `attachments` (public read, authenticated
upload/update via policies on `storage.objects`).

The `metadata` JSONB on `posts` carries type-specific fields:
`quote_author`, `source`, `options`, `votes`, `date`, `time`, `location`,
`is_online`, `datetime`, `thumbnail_url`, `duration`, `views`.

### Migrations

Migrations now live in `supabase/migrations/`. Run them in order in the
Supabase SQL editor (or `supabase db push`):

| File                                  | Adds                                              |
|---------------------------------------|---------------------------------------------------|
| `0001_messages_and_profile.sql`       | DMs (conversations/members/messages + RLS), `profiles.avatar_url` + `profiles.bio`, `get_or_create_dm` + `get_my_conversations` RPCs, `last_message_at` trigger, realtime publication |
| `0002_groups_communities_roles.sql`   | Groups for all entities + group chat infra, community core (Announcements + Chat default groups, owner-only group creation, library/Add/Write, drafts), Owner/Admin roles, read tracking (Hot 🔥), storage buckets (`avatars`/`attachments`), backfill for existing data |

**Important — realtime publication.** The app's `.stream()` subscriptions
require the table to be in the `supabase_realtime` publication. Migration 0001
adds the three DM tables to it automatically; migration 0002 adds
`groups`, `group_members`, `message_reactions`, `book_reads` and
`community_books`. (`club_books` was already expected to be published for the
Books library stream.)

#### Migration 0001 — full SQL

```sql
-- ============================================================================
-- BookNest — Migration 0001: Direct Messaging + Profile fields
-- ============================================================================
--   1. `profiles.avatar_url` and `profiles.bio`.
--   2. `conversations`, `conversation_members`, `messages` + RLS.
--   3. `get_or_create_dm(other_user uuid)` — idempotent find-or-create DM.
--   4. `get_my_conversations()` — DM list rows (partner, last message, unread).
--   5. Trigger bumping `conversations.last_message_at` on every message.
--   6. Realtime publication for the three new tables.
-- ============================================================================

alter table profiles add column if not exists avatar_url text;
alter table profiles add column if not exists bio text not null default '';

create table if not exists conversations (
  id              uuid primary key default gen_random_uuid(),
  type            text not null default 'direct' check (type in ('direct', 'group', 'channel')),
  title           text,
  avatar_url      text,
  created_by      uuid references profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz not null default now()
);

create table if not exists conversation_members (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  user_id         uuid not null references profiles(id) on delete cascade,
  role            text not null default 'member' check (role in ('owner', 'moderator', 'member')),
  last_read_at    timestamptz,
  joined_at       timestamptz not null default now(),
  unique (conversation_id, user_id)
);

create index if not exists conversation_members_user_idx
  on conversation_members (user_id);
create index if not exists conversation_members_conversation_idx
  on conversation_members (conversation_id);

create table if not exists messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_id       uuid not null references profiles(id) on delete cascade,
  type            text not null default 'text' check (type in ('text', 'image', 'file', 'system')),
  content         text not null default '',
  metadata        jsonb not null default '{}'::jsonb,
  reply_to        uuid references messages(id) on delete set null,
  edited_at       timestamptz,
  created_at      timestamptz not null default now()
);

create index if not exists messages_conversation_created_idx
  on messages (conversation_id, created_at);

-- Realtime streams filter on non-PK columns; full replica identity lets
-- DELETE events carry the whole old row so stream filters drop them.
alter table conversation_members replica identity full;
alter table messages replica identity full;

alter table conversations enable row level security;
alter table conversation_members enable row level security;
alter table messages enable row level security;

drop policy if exists "members can view their conversations" on conversations;
create policy "members can view their conversations"
  on conversations for select
  using (exists (
    select 1 from conversation_members cm
    where cm.conversation_id = id and cm.user_id = auth.uid()
  ));

drop policy if exists "users can start conversations" on conversations;
create policy "users can start conversations"
  on conversations for insert
  with check (auth.uid() = created_by);

drop policy if exists "members can update their conversations" on conversations;
create policy "members can update their conversations"
  on conversations for update
  using (exists (
    select 1 from conversation_members cm
    where cm.conversation_id = id and cm.user_id = auth.uid()
  ));

drop policy if exists "members can view memberships of their conversations" on conversation_members;
create policy "members can view memberships of their conversations"
  on conversation_members for select
  using (exists (
    select 1 from conversation_members me
    where me.conversation_id = conversation_id and me.user_id = auth.uid()
  ));

drop policy if exists "users can join as themselves" on conversation_members;
create policy "users can join as themselves"
  on conversation_members for insert
  with check (auth.uid() = user_id);

drop policy if exists "members can update their own membership" on conversation_members;
create policy "members can update their own membership"
  on conversation_members for update
  using (auth.uid() = user_id);

drop policy if exists "members can read messages" on messages;
create policy "members can read messages"
  on messages for select
  using (exists (
    select 1 from conversation_members cm
    where cm.conversation_id = messages.conversation_id
      and cm.user_id = auth.uid()
  ));

drop policy if exists "members can send messages" on messages;
create policy "members can send messages"
  on messages for insert
  with check (
    auth.uid() = sender_id
    and exists (
      select 1 from conversation_members cm
      where cm.conversation_id = messages.conversation_id
        and cm.user_id = auth.uid()
    )
  );

drop policy if exists "members can update their own messages" on messages;
create policy "members can update their own messages"
  on messages for update
  using (auth.uid() = sender_id);

-- get_or_create_dm(other_user uuid) -> uuid (SECURITY DEFINER)
create or replace function get_or_create_dm(other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  my_id uuid := auth.uid();
  conv  uuid;
begin
  if my_id is null then
    raise exception 'Not authenticated';
  end if;
  if other_user is null or other_user = my_id then
    raise exception 'Invalid conversation partner';
  end if;

  select cm1.conversation_id into conv
  from conversation_members cm1
  join conversation_members cm2 on cm2.conversation_id = cm1.conversation_id
  join conversations c on c.id = cm1.conversation_id
  where cm1.user_id = my_id
    and cm2.user_id = other_user
    and c.type = 'direct'
  limit 1;

  if conv is not null then
    return conv;
  end if;

  insert into conversations (type, created_by)
  values ('direct', my_id)
  returning id into conv;

  insert into conversation_members (conversation_id, user_id)
  values (conv, my_id), (conv, other_user);

  return conv;
end;
$$;

revoke all on function get_or_create_dm(uuid) from public;
grant execute on function get_or_create_dm(uuid) to authenticated;

-- get_my_conversations() — DM list data in one call (SECURITY DEFINER)
create or replace function get_my_conversations()
returns table (
  conversation_id         uuid,
  conversation_created_at timestamptz,
  last_message_at         timestamptz,
  last_message            text,
  last_message_type       text,
  last_sender_id          uuid,
  unread_count            bigint,
  partner_user_id         uuid,
  partner_username        text,
  partner_display_name    text,
  partner_avatar_url      text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    c.id,
    c.created_at,
    c.last_message_at,
    lm.content,
    lm.type,
    lm.sender_id,
    (
      select count(*)
      from messages m
      where m.conversation_id = c.id
        and m.sender_id <> auth.uid()
        and m.created_at > coalesce(
              (select cm.last_read_at
               from conversation_members cm
               where cm.conversation_id = c.id and cm.user_id = auth.uid()),
              '-infinity'::timestamptz
            )
    )::bigint,
    p.id,
    p.username,
    p.display_name,
    p.avatar_url
  from conversations c
  join conversation_members me
    on me.conversation_id = c.id and me.user_id = auth.uid()
  join conversation_members partner
    on partner.conversation_id = c.id and partner.user_id <> auth.uid()
  join profiles p on p.id = partner.user_id
  left join lateral (
    select m.content, m.type, m.sender_id
    from messages m
    where m.conversation_id = c.id
    order by m.created_at desc, m.id desc
    limit 1
  ) lm on true
  order by c.last_message_at desc;
$$;

revoke all on function get_my_conversations() from public;
grant execute on function get_my_conversations() to authenticated;

-- Keep conversations.last_message_at fresh
create or replace function touch_conversation_on_message()
returns trigger
language plpgsql
as $$
begin
  update conversations
     set last_message_at = new.created_at
   where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists messages_touch_conversation on messages;
create trigger messages_touch_conversation
  after insert on messages
  for each row execute function touch_conversation_on_message();

-- Realtime publication (idempotent)
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'conversations'
  ) then
    alter publication supabase_realtime add table conversations;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'conversation_members'
  ) then
    alter publication supabase_realtime add table conversation_members;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table messages;
  end if;
end $$;
```

---

## Theming

The **N.O Group scheme** is live app-wide (Phase 2 complete):

- **`BookNestColors`** — the palette: deep blue `#1E4FD6` (primary, `#3D6BFF`
  on dark), deep navy backgrounds (`#070B14` / `#0B1633` for Black theme;
  `#F4F6FB` / white for the White theme), and **cyan `#00D4FF`** used at
  ~0.1% for gradients/highlights. Amber `#FFC53D` is reserved for
  hot/trending accents.
- **`NOC`** — theme-aware semantic colors (`NOC.bg`, `NOC.surface`,
  `NOC.accent`, `NOC.text`, `NOC.hot`, …) that resolve from the
  `ThemeController` + platform brightness with no BuildContext needed. Every
  screen uses these, so the whole app re-skins between Black and White (or
  System) instantly. **No legacy hex values remain outside `theme.dart`.**
- **`BookNestTheme.darkTheme` / `.lightTheme`** — Material 3 `ThemeData` for
  the **Black** and **White** themes (deep-blue primary, glass-friendly
  surfaces, styled buttons/AppBar).
- **Glassmorphism** — `NOC.card` (elevated glass card decoration) + `NOC.blur`
  (BackdropFilter wrapper) are used across the nav bar, center FAB, floating
  action buttons, cards and buttons. `Glass` (older helper) is kept as a
  fallback.
- **`ThemeController`** (`config/theme_controller.dart`) — System / Light /
  Dark preference persisted via `shared_preferences`; `main.dart` wires it
  to `MaterialApp.themeMode` and the Profile tab exposes the switcher.

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

- **Per-message read receipts**, typing indicators, a "pinned messages" feed
  view, and group-avatar upload UI are roadmapped.
- **Club / Organization / School detail** screens show identity + Groups &
  Chat only; the richer experiences (threads, class channels, resources,
  exam countdowns) are roadmapped.
- **DM/group search** only matches username/display name; no message-content
  search (the search icon in the Messages app bar is a placeholder).
- **Bookmark / Like / Comment / Share** actions show confirmation toasts but do
  not yet persist to the backend (except the new message reactions).
- **Reels** still store a placeholder record ("video upload coming soon").
- Supabase free-tier file-size limits apply to HD uploads.
- `flutter_riverpod` and `cached_network_image` are present in `pubspec.yaml`
  but not yet used.

---

## Roadmap

- [x] Full Profile screen (avatar, bio, authored books, gems, drafts, sign out).
- [x] Real-time **DM** list + chat with message persistence.
- [x] **Group chat** for all entities (communities, clubs, organizations,
      schools) via the shared `groups`/`conversations` system.
- [x] Community core: default Announcements + Chat groups, owner-only group
      creation, community library (Add from public books + Write), drafts,
      Owner/Admin roles with per-group admin powers.
- [x] Profile screens for people / groups / communities; profile-picture
      upload to Supabase Storage.
- [x] Read tracking (Hot 🔥 algorithm foundation).
- [x] N.O Group theme foundation: Black/White themes + System/Light/Dark
      toggle.
- [x] **Phase 2:** app-wide N.O palette rollout + glassmorphism (nav bar,
      FABs, cards, buttons) across all screens; the old color scheme is fully
      removed.
- [x] **Attachments (paper clip):** HD photo/video upload in DMs + group
      chats, image viewer, DM preview labels.
- [x] Optional profile photo at registration; auth-loop fix (session-aware
      router + splash + login/register session gates).
- [x] In-app video playback (`video_player`) + document attachments
      (`file_picker`) in DMs + group chats.
- [x] App upgraded to **v2.0.0** (feature-complete messaging + community
      stack).
- [ ] Rich Book reader with chapters, bookmarks, and reading progress.
- [ ] Complete Club / Organization / School detail experiences (threads,
      class channels, resources, exam countdowns).
- [ ] Video upload + playback for Reels.
- [ ] Persisted likes/comments/bookmarks (book-level).
- [ ] Typing indicators, per-message read receipts, message search, pinned
      message feed.
- [ ] Adopt `flutter_riverpod` for cross-screen state and
      `cached_network_image` for cover/avatar images.

---

## Development Session Log

> Golden rule #1: every session appends detailed, long-form notes here so the
> next session can pick up without re-deriving context. Newest entry first.

---

### Session 2026-08-22 — In-app video playback, document attachments, app v2.0.0, branch pushed (Part 4)

**User asks:** "Add them" (the two remaining roadmap items — in-app video
playback + document attachments), "upgrade the app", and make the working
branch findable in the repo (it existed only locally until now).

**0. Error scan (rule #3).** Balance/string/import checks across all Dart
files pass; only the known theme.dart false positive ("uses NOC without theme
import" — it defines NOC).

**1. 🎬 In-app video playback (`video_player`).**
- New dependency `video_player: ^2.9.2`.
- New screen `lib/presentation/screens/dms/video_player_screen.dart`
  (`VideoPlayerScreen`): full-screen, streams the attachment URL via
  `VideoPlayerController.networkUrl`, autoplays, tap toggles controls,
  play/pause button, seek slider, elapsed/total time, error + loading states,
  controller disposed properly.
- Chat: video attachments now open **in the app** instead of the browser
  (`_openVideoPlayer`); the bubble shows "Video · tap to play".

**2. 📄 Document attachments (`file_picker`).**
- New dependency `file_picker: ^8.1.2` (`FilePicker.platform.pickFiles(type:
  FileType.any, withData: true)`).
- The paper-clip sheet now has **Photo / Video / Document**.
- `_pickAndSendAttachment({required String kind})` handles all three:
  - photo → `image_picker`, message type `image`
  - video → `image_picker`, message type `file`, `metadata.kind = 'video'`
  - document → `file_picker` (bytes via `withData`), message type `file`,
    `metadata.kind = 'document'`
  - MIME inferred from the file extension via `_mimeForName` (pdf/doc(x)/
    xls(x)/ppt(x)/txt/md/zip/images/videos/octet-stream fallback).
- Bubble rendering distinguishes video (`Icons.play_circle_outline`,
  "Video · tap to play") from document (`Icons.description_outlined`,
  "Document · tap to open"); documents open externally via `url_launcher`.
- Old messages (no `kind` in metadata) fall back to MIME sniffing, so
  previously sent videos keep working.

**3. ⬆️ App upgrade to v2.0.0.**
- `pubspec.yaml` version bumped `1.0.0+1` → **`2.0.0+2`** to mark the
  feature-complete messaging + community stack.
- All previous sessions' work (DMs, group chat, community core, roles, read
  tracking, drafts, N.O theme, attachments, auth-loop fix) is included.

**4. 🌿 Branch pushed + PR.**
- Everything committed to `arena/01a024d4-booknest` and pushed to
  `origin` (`https://github.com/NO-Group/BookNest.git`). The branch previously
  existed only in the sandbox — that is why it was not visible in the repo.
- A pull request was opened from `arena/01a024d4-booknest` → `main` so the
  work is reviewable and findable on GitHub.

**How to test.**
1. `flutter pub get` (new deps: `video_player`, `file_picker`), then
   `flutter run`.
2. Attachments: open any chat → paper clip → **Video** → send → tap the
   bubble → it plays in the in-app player (seek + play/pause). Paper clip →
   **Document** → pick a PDF → bubble shows the doc icon → tap → opens in the
   system app.
3. Check `attachments` bucket for the new uploads; DM list shows 📎 previews.

**What's next (candidates).** Per-message read receipts + typing indicators,
"pinned messages" feed view, group-avatar upload UI, rich Book reader,
`cached_network_image` adoption, `flutter_riverpod` wiring.

---

### Session 2026-08-21 — Phase 2: full N.O theme, attachments (HD), register photo, auth-loop fix (Part 3)

**Goal.** Finish Phase 2 (app-wide N.O Group theme + glassmorphism, paper-clip
attachments in HD), add an **optional profile photo at registration**, and fix
the **"logged in but bounced back to /login" loop**.

**0. Error scan (rule #3).** Manual + automated pass over every edited file
(balance/string/import checks). No pre-existing errors surfaced; the sweep's
own side effects were caught and fixed (see the theme section below).

**1. 🔒 The auth loop — root cause & fix.**
- **Root cause (verified in the supabase_flutter 2.16 source):**
  `Supabase.initialize()` does **not** await session recovery — it launches
  `recoverSession()` as a fire-and-forget `CancelableOperation`. So on cold
  start the app could decide "no session" (→ `/login`) before the persisted
  session was restored, and nothing ever re-checked. On top of that:
  - `_redirect`/`AuthGuard` used `auth.currentUser`, which can be null in the
    brief window between a session restore/refresh and the auth subscribers
    being notified → false "signed out" → bounce to `/login`.
  - The **register screen navigated to `/feed` whenever `res.user != null`** —
    but with email confirmation enabled there is **no session yet** → the user
    landed on the feed as a ghost and every protected tap bounced them to
    `/login` → the "stuck in a loop" feeling.
  - **`createProfile()` was never called anywhere** — new users had no
    `profiles` row (broke profile screens / DM search).
- **Fixes:**
  - `config/router.dart`: new `authRevision` `ValueNotifier` +
    `refreshListenable: authRevision` on `GoRouter`, and `_redirect` now uses
    `auth.currentSession != null` (session is the source of truth).
  - `main.dart`: subscribes to `auth.onAuthStateChange` and bumps `authRevision`
    on every event (sign-in, sign-out, restore, refresh, expiry) → the router
    re-evaluates redirects **immediately**, so a late session restore now
    auto-bounces `/login` → `/feed` instead of stranding the user.
  - `SplashScreen`: subscribes to `onAuthStateChange` and routes to `/feed` the
    moment a session appears (no false `/login` on slow restores).
  - `AuthGuard`: now checks `currentSession`.
  - `LoginScreen`: only navigates on `res.session != null`; calls
    `ensureProfileForCurrentUser()`.
  - `RegisterScreen`: only navigates on `res.session != null`; shows
    "check your email" otherwise; creates the profile on sign-up.
  - `SupabaseService.ensureProfileForCurrentUser()` — lazily creates the
    `profiles` row from auth metadata on login/signup (covers all legacy
    accounts too).

**2. 🖼️ Optional profile photo at registration.**
`RegisterScreen` now shows a circular "Add profile photo (optional)" picker
before sign-up. The picked image is held in memory and, once the account is
created (and a session exists), uploaded at **original HD quality** to the
`avatars` bucket as `avatars/{userId}.jpg` and written to
`profiles.avatar_url`. If email confirmation is required (no session yet), the
photo step is skipped and the user adds a photo later from the Profile tab.

**3. 📎 Attachments (paper clip) — photos & videos in HD.**
`ConversationChatScreen` (DMs + group chats) input bar now has a paper-clip
button → bottom sheet (Photo / Video):
- Picked via `image_picker` with **no compression/quality downscaling** → the
  original HD file is uploaded to the `attachments` Storage bucket
  (`attachments/{conversationId}/{timestamp}_{name}`).
- The message is inserted with `type: 'image'` (photos) or `'file'` (videos)
  and `metadata: {url, mime_type, size, name}` — no schema change needed
  (0002 already allows these types and created the bucket + policies).
- Photos render inline in the bubble; tapping opens a full-screen pinch-zoom
  viewer. Videos render as an attachment card; tapping opens the URL in the
  system browser (via `url_launcher`, new direct dependency). The DM list
  preview shows "📷 Photo" / "📎 Attachment".
- **Note:** in-app video playback (video_player) and document attachments are
  still roadmapped; Supabase free-tier file-size limits apply to uploads.

**4. 🎨 Phase 2 theme: full N.O Group rollout + glassmorphism.**
- `config/theme.dart` gained the **`NOC`** theme-aware color resolver
  (surfaces/accent/text/hot/danger + `NOC.card` elevated glass decoration +
  `NOC.blur` BackdropFilter helper) — resolves from `themeController` +
  platform brightness, no BuildContext needed.
- A careful transformation pass replaced **every** remaining legacy hex value
  across all `lib/presentation/**` screens with NOC tokens (backgrounds →
  `NOC.bg`, cards → `NOC.surfaceAlt`, borders → `NOC.border`, cyan/orange →
  `NOC.accent`/`NOC.hot`, text → `NOC.text`/`textMuted`/`textFaint`), with an
  automatic `const`-stripping pass (including `const Identifier(...)` forms)
  and `static const` → `static final` conversions so everything stays
  compile-safe. No old-scheme hex values remain outside `theme.dart` itself.
- White-on-accent spots were re-pointed to `NOC.onAccent` (FABs, active
  chips, gradient buttons, stylus painter, splash logo, RSVP/primary buttons).
- Nav bar + center FAB re-glassed: translucent `NOC.surfaceAlt` bar with
  `NOC.border` hairline + backdrop blur; center FAB is now a deep-blue →
  cyan glass gradient (the amber/orange is retired to "hot/trending" accents).
- Auth screens (login/register/splash) were hand-restyled: deep-blue → cyan
  gradient CTA buttons, glass fields, N.O background.
- New dependency: `url_launcher` (already in the dependency graph via
  supabase_flutter; now a direct dep). `image_picker`'s iOS permission strings
  were added to `ios/Runner/Info.plist` (display name also corrected from the
  old "Tether" to "BookNest").

**5. README** — this log, Features, Tech Stack, Known Limitations, Roadmap,
and test steps updated.

**How to test.**
1. `flutter pub get` (new direct dep `url_launcher`; `image_picker` was already
   declared last session), then `flutter run`.
2. **Auth loop:** log in → kill & relaunch the app → you should land straight
   on the feed (no /login bounce). Tap protected buttons (Write, /editor,
   Messages, Profile, group chat) — no bounce. Sign out → you're sent to
   /login and protected routes stay locked. Register with a fresh email
   (confirmation enabled) → you stay on a "check your email" message, then
   confirm + log in → profile row auto-created → works.
3. **Register photo:** sign up a new account and pick a photo → check the
   `avatars` bucket + Profile header.
4. **Attachments:** open any chat → paper clip → Photo/Video → send → image
   shows inline (tap to zoom), video opens externally; DM list shows the
   preview label.
5. **Themes:** Profile tab → Theme → System/Light/Dark — the whole app
   re-skins (old screens now theme-aware).

**What's next (candidates).** In-app video playback (`video_player`),
document attachments (`file_picker`), pinned-messages feed, per-message
receipts/typing indicators, group-avatar upload UI, richer club/org/school
details, `cached_network_image` adoption, `flutter_riverpod` wiring.

---

### Session 2026-08-21 — Group chat, community core, roles, read tracking, theme foundation (Part 2)

**User brief (abridged):** add group chat; community = Announcements group
(admin-only messaging) + a normal chat group + a library (plus button expands
vertically: **Add** public books from a searchable list with a **Hot 🔥**
section algorithmized from most-read books, or **Write** reusing the editor
with **Save draft** beside Publish — personal drafts in Profile, community
drafts in the community library); owner-only group creation; Owner vs per-group
Admin hierarchy (pin/delete, remove members, make admins, never touch owner);
admin group names shown next to members; profile pictures + profile screens for
people/groups/communities; N.O Group re-theme (Black/White themes, deep blue +
0.1% cyan, glassmorphism); paper-clip attachments in HD.

**Clarifications the user chose (asked before building, per their rule):**
1. **Phased**: foundations first (this session) — schema + storage + group
   chat + community core; theme overhaul + attachments are **Phase 2**.
2. **Theme**: System/Light/Dark toggle (follows system by default).
3. **Hot 🔥**: add real read tracking.
4. **Group chat scope**: all entity types (communities, clubs, organizations,
   schools) via one shared system.

**0. Error scan (rule #3).** No toolchain in the sandbox (only GitHub
reachable; Google storage/pub.dev blocked), so again: manual read-through of
every edited file + automated brace/string-balance + relative-import checks on
all `lib/**/*.dart` and the test. The import checker caught real mistakes
(4 files had one-level-short `../../` import paths — fixed), and a scope bug in
the Profile edit sheet (`setSheetState` used outside its closure — fixed by
moving the avatar-upload helper inside the sheet builder). All files balanced
and imports resolve at the end of the session.

**1. Migration `0002_groups_communities_roles.sql`** (full SQL in the Supabase
Backend section; ~600 lines). Highlights:
- `club_books`: +`community_id`, +`views`, moderation check now includes
  `'draft'`. RLS enabled with: approved books public; drafts/pending visible to
  author or community members; insert/update/delete by author only.
- `conversation_members.role` check extended with `'admin'`; `messages` +
  `is_pinned`.
- New tables: `groups` (entity_type/entity_id/name/group_type/conversation_id/
  is_default), `group_members` (owner/admin/member), `message_reactions`,
  `book_reads` (read log), `community_books` (library reposts).
- Unique pair constraints added to `community_members`, `club_members`,
  `organization_members`, `school_members` (needed for idempotent sync).
- Helpers `is_entity_member`, `is_entity_owner`, `entity_owner_id`
  (SECURITY DEFINER) drive the polymorphic RLS policies.
- **Default-group triggers** on communities/clubs/organizations/schools INSERT:
  communities get `"{name} Announcements"` (group_type announcement) +
  `"{name} Chat"`; others get just the Chat group. Each group gets its own
  conversation + owner membership.
- **Membership-sync triggers** on the four member tables (INSERT/DELETE):
  joining/leaving an entity adds/removes the user in every group + group
  conversation of that entity (group memberships are real rows, so "remove
  member from group" works as the user specified).
- **`create_group(e_type, e_id, group_name, g_type)`** RPC — owner-only,
  seeds members, returns the group id.
- **Announcement RLS**: messages INSERT requires conversation membership AND
  (not an announcement group OR sender is owner/admin of that group).
  DELETE allowed for sender or group owner/admin. UPDATE allowed for sender or
  group owner/admin, and the **`messages_pin_permission` trigger** raises an
  exception unless the updater is a group owner/admin — pinning is enforced
  server-side, not just in the UI.
- **Read tracking**: `record_book_read(book_id)` dedupes to one read per user
  per book per day; `book_reads_bump_views` trigger keeps `club_books.views`
  fresh; `get_hot_books(days, max_count)` = approved books ordered by 7-day
  reads, then views, then recency.
- **Storage**: public buckets `avatars` + `attachments` with public-read and
  authenticated-upload/update policies on `storage.objects`.
- **Backfill** DO-block: inserts missing owners into member tables and creates
  default groups for all pre-existing entities. Realtime publication extended
  with the five new tables.
- `get_my_conversations()` now filters `c.type = 'direct'` (groups get their
  own list; the old join would have duplicated rows).

**2. Theme foundation (Phase 1 of the re-theme).** `config/theme.dart` now
defines the N.O palette (deep blue `#1E4FD6`, deep navy `#070B14`/`#0B1633`,
cyan `#00D4FF` for ~0.1% accents), `BookNestTheme.darkTheme` + `.lightTheme`,
and `Glass` helpers (card + BackdropFilter blur). Legacy `BookNestColors`
names point at N.O values so old code compiles. New `config/theme_controller.dart`
(ChangeNotifier + global `themeController`, persisted via `shared_preferences`
— new dependency) and `main.dart` now serves both themes with
`ThemeMode` from the controller. The Profile tab has a System/Light/Dark
`SegmentedButton`. Old screens keep their hex colors until Phase 2.

**3. Group chat (all entities).** `dm_chat_screen.dart` now hosts
`ConversationChatScreen` (used by both `/dm/:id` and the new
`/group-chat/:conversationId`):
- Group mode loads the `groups` row via `conversations.select('*, groups!inner(*)')`,
  then `group_members` with `profiles` for sender names + my role.
- Sender names above received bubbles; hearts on every bubble
  (`message_reactions`, like/unlike toggle, counts shown); long-press → pin /
  unpin / delete sheet for admins/senders (server-enforced).
- Announcement groups hide the input bar for non-owner/admin members and show
  a banner instead.
- Reversed ListView + realtime stream identical to DMs; `last_read_at` ticking
  retained. Direct mode unchanged.

**4. Community core.** `CommunityDetailScreen` rewritten (Groups / Library /
Members tabs + join/leave + stats + verified badge):
- Groups tab: lists groups (badge: Announcements vs Chat), opens
  `/group-chat/:conversationId`; owner-only "New group" dialog (name + type)
  → `create_group` RPC.
- Library tab: `community_books → club_books` list with Approved/Pending/Draft
  chips; "+" FAB expands vertically (mirrors the Feed stylus) into **Add**
  (`CommunityAddBooksScreen`: search + Hot 🔥 section + multi-select + Done →
  batch `community_books` insert, already-added books greyed out) and **Write**
  (`/editor?communityId=…`). FAB only appears on the Library tab
  (TabController listener added).
- Members tab: `community_members` + profiles + per-user admin group names
  (`group_members` where role=admin, joined to `groups(name)`) shown as
  "Admin · <group>" chips.
- `EntityGroupsPanel` component gives club/org/school detail screens the same
  groups+chat section (owner can still create groups). All three detail screens
  upgraded from id-stubs to identity + panel. `CreateClub/Org/School` now insert
  the owner into the member table (was missing — owner membership + group
  seeding depends on it). `CreateCommunityScreen` no longer inserts the legacy
  `announcement_groups` row (the trigger does groups now).

**5. Drafts & editor.** `BookEditorScreen` gained a **Save** (draft) button
next to **Publish**, `communityId` context, and `bookId` support (loads an
existing book + first chapter to continue a draft; saving updates the row,
publishing flips status to pending, chapter upserted). Profile gained **My
Drafts** (status=draft, `community_id.is.null`) with Continue + Delete
(`club_books` delete policy added for authors).

**6. Read tracking wired.** `PublishDetailsScreen` fires `record_book_read`
on open; view counts shown in the reader header, book library cards, community
library, user profiles, and the Add-books picker.

**7. Profiles.** `UserProfileScreen` (`/user/:userId`) — public avatar/name/
bio/gems/books/posts + Message button (get_or_create_dm). `GroupProfileScreen`
(`/group/:groupId`) — group info, entity name, member list with roles,
promote/demote/remove for admins (owner protected in RLS), Open chat. Profile
tab avatar upload via `image_picker` → `avatars` bucket (original HD image;
URL override still available).

**8. Router.** New routes: `/group-chat/:conversationId`, `/group/:groupId`,
`/user/:userId`, `/community/:communityId/library/add`; `/editor` reads
`communityId`/`bookId` query params. Protected set grows: `/group`,
`/group-chat`, plus a regex guard for `/community/*/library*` (member-only)
while the community page itself stays public.

**9. Known risks / decisions for the next session.**
- The 0002 migration is **large and enables RLS on `club_books`** for the
  first time — run it on a staging copy first and sanity-check the Books
  library (approved-public policy) and author flows. The old
  `announcement_groups` table is now unused (kept for data safety; can be
  dropped later).
- `image_picker` + `shared_preferences` were added to `pubspec.yaml` —
  run `flutter pub get` before building.
- Phase 2 checklist: paper-clip attachments (bucket + policies are ready) with
  HD photo/video, app-wide glassmorphism + N.O palette rollout on the older
  screens, per-message receipts/typing, pinned-message feed, group avatar
  upload UI, richer club/org/school details.
- Realtime: `group_members`/`groups` are published but the chat streams
  `messages` only; the community detail screen re-fetches on tab switches /
  pull-to-refresh rather than streaming (fine at this scale).

---

### Session 2026-08-21 — Messages (DMs) + Profile screens shipped

**Goal.** Complete the last two primary bottom-nav screens — **Messages**
(Tab 4) and **Profile** (Tab 5) — which were plain "DMs"/"Profile" text stubs,
per the roadmap ("Full Profile screen…", "Real-time DM…"). The user's session
rules were added to the top of this README (see [Session Rules](#-session-rules-read-before-every-session)).

**0. Error scan before building (rule #3).**
- No Flutter/Dart toolchain exists in this sandbox (only GitHub is reachable;
  `storage.googleapis.com` / `pub.dev` / Flutter mirrors are blocked), so a
  full `flutter analyze` was impossible. Instead:
  - Read **every** file under `lib/` (all screens, router, theme, services,
    auth guard, shell, nav bar) and `test/widget_test.dart`.
  - Ran an automated brace/paren/string balance check across all Dart files —
    all balanced.
  - Verified the pinned package APIs against source: supabase_flutter 2.16.0 /
    supabase 2.14.0 / postgrest 2.8.0 / realtime_client 2.11.0 (cloned
    supabase-flutter monorepo). Key findings:
    - `SupabaseStreamBuilder` does **not** expose `.select()` — streams cannot
      embed relations → the DM list uses the `get_my_conversations()` RPC for
      joined data instead.
    - `.stream(primaryKey: …)` returns `SupabaseStreamFilterBuilder`
      (multiple `eq` filters now allowed); `rpc<T>(fn, params:)` exists on the
      client; `channel.onPostgresChanges(...)` returns a broadcast stream that
      must be set up before `channel.subscribe()`.
  - No pre-existing errors were found; the placeholders that remain
    (`CommunityDetailScreen`, `OrganizationDetailScreen`, `SchoolDetailScreen`,
    `ClubDetailScreen`, `ChatScreen`, `ReaderScreen`) are intentional.

**1. Supabase migration — `supabase/migrations/0001_messages_and_profile.sql`**
(also pasted into [Supabase Backend](#supabase-backend)). Adds:
- `profiles.avatar_url`, `profiles.bio` (Profile screen).
- `conversations` (type direct/group/channel, `last_message_at`),
  `conversation_members` (role, `last_read_at`, unique pair),
  `messages` (type text/image/file/system, `metadata` jsonb, `reply_to`).
- RLS: members-only select on all three; sender-scoped insert/update on
  messages; self-insert/self-update on memberships.
- `get_or_create_dm(other_user uuid)` (SECURITY DEFINER): idempotently finds
  or creates the direct conversation and returns its id — prevents duplicate
  DMs. Grants to `authenticated` only.
- `get_my_conversations()` (SECURITY DEFINER, STABLE): returns DM-list rows —
  conversation id/timestamps, last message content/type/sender, unread count
  (messages after `last_read_at`), and the partner profile — ordered by
  `last_message_at desc`.
- Trigger `messages_touch_conversation`: after INSERT on `messages`, bumps
  `conversations.last_message_at` (drives list ordering; the app never writes
  it directly).
- Idempotent `do $$` block adding the three tables to the `supabase_realtime`
  publication — **required** for `.stream()` to work.

**2. Flutter — new shared helpers.**
- `lib/core/utils/time_format.dart`: `formatRelativeTime` ("now", "5m", "3h",
  "yesterday", "5d", "Aug 3"), `formatMessageTimestamp` (day-aware "14:30" /
  "Aug 3, 14:30"), `formatFullDate` ("Aug 3, 2026").
- `lib/presentation/components/user_avatar.dart`: circular avatar that shows
  `avatar_url` via `Image.network` with an error fallback to initials on a
  dark tile (no new dependencies; cached_network_image adoption still
  roadmapped).

**3. `DMListScreen` rewritten** (`lib/presentation/screens/dms/dm_list_screen.dart`).
- Two live inputs: `.stream()` on `conversation_members` (eq `user_id`) for
  membership changes, and a realtime channel "dm-ticker" on `messages`
  (`PostgresChangeEvent.all`) that triggers a 400 ms-debounced re-fetch. The
  re-fetch calls `get_my_conversations()` and replaces the list.
- Rows: partner avatar/name, "You: …" prefixed preview when the last message
  is mine, relative timestamp, unread-count badge (bold when unread).
- Compose FAB → `_NewConversationSheet`: debounced profile search
  (`or('username.ilike.%q%,display_name.ilike.%q%')`, excluding self) →
  `get_or_create_dm` → `context.push('/dm/$id')`.
- Empty state with a "New message" CTA; `RefreshIndicator` for manual pulls.
- Disposes stream sub, channel, and debounce timer.

**4. `DMChatScreen` rewritten** (`lib/presentation/screens/dms/dm_chat_screen.dart`).
- Loads the conversation + partner via one query embedding
  `conversation_members(*, profiles(...))`.
- Realtime messages: `.stream(primaryKey: ['id']).eq('conversation_id', id)
  .order('created_at', ascending: true)` rendered in a **reversed** ListView
  (index math: `messages[len-1-index]`) so the newest bubble is at the bottom
  and the view stays pinned there by default — no scroll choreography.
- Sent = right-aligned dark-cyan (`0xFF0F3A47`) bubbles; received =
  left-aligned grey (`0xFF1F1F1F`) with border; day-aware timestamps under
  each bubble (see `formatMessageTimestamp`).
- Send = plain insert (`type: 'text'`); the trigger handles ordering; input is
  cleared only after a successful insert; errors surface via SnackBar.
- Read state: `_markRead()` bumps `conversation_members.last_read_at` on open
  and every 5 s while the screen is mounted (no extra stream subscription, so
  no double-subscription risk on the messages stream).
- AppBar shows the partner avatar + name and a placeholder overflow menu
  ("View profile", "Clear chat" → toast "coming soon").

**5. `ProfileScreen` rewritten** (`lib/presentation/screens/profile/profile_screen.dart`).
- Streams the user's `profiles` row (primaryKey `id`, eq `id`) so the header
  updates live after edits; fetches `club_books` (added_by = me, limit 50) and
  `posts` (created_by = me, limit 50) once.
- Header: avatar, display name, gem pill (`Icons.diamond` + count), `@username`,
  bio, "Joined …" date. Stats row: Books · Posts · Gems.
- My Books cards with Pending (orange) / Approved (cyan) chips; tap → reader
  (`/publish-details`). My Posts cards with type badge + preview.
- Edit-profile bottom sheet: display name, username (must be non-empty),
  bio, avatar URL → `profiles.update` → stream refreshes the header.
- Sign out: confirmation dialog → `auth.signOut()` → `context.go('/login')`.

**6. Router** (`lib/config/router.dart`).
- New fullscreen route `/dm/:conversationId` → `DMChatScreen` (covers the
  bottom nav, like `/editor`).
- `/dms`, `/dm` (prefix) and `/profile` added to `_protectedRoutes` — signed-out
  users hitting Messages or Profile are bounced to `/login`.

**7. README** — session rules at the top, Features rewritten for Messages +
Profile, navigation map updated (`/dm/:conversationId` added; `/dms`,
`/profile` now protected), project structure updated, Supabase Backend extended
with the new tables + full migration SQL, architecture notes, limitations,
roadmap check-offs, and this session log.

**How to test.**
1. Run `supabase/migrations/0001_messages_and_profile.sql` in the Supabase SQL
   editor (or `supabase db push`).
2. `flutter pub get && flutter run` (web is fastest for UI checks).
3. Sign up two accounts → Messages tab → compose → search the other user →
   send messages both ways → confirm the list reorders/previews update live
   and unread badges clear after opening the chat.
4. Profile tab → edit display name/bio/avatar URL → header updates instantly →
   publish a book (Books tab → Write) → it appears under My Books with a
   Pending chip → sign out → verify bounce to `/login`.

**What's next (candidates).** Club chat (`ChatScreen`) via the same
conversations schema with `type='group'`; rich Book reader; Community / Org /
School detail screens; avatar upload to Storage; per-message receipts + typing
indicators; message search; `flutter_riverpod` adoption.

---

## License & Credits

BookNest is built by **N.O Group**. See the repository for license details.

Built with ❤️ and a lot of Markdown on Flutter + Supabase.
