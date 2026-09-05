# Changelog

## 1.8.0+10 — 2026-09-05

- **BookNest Wrapped** — your whole reading story on one beautiful page:
  time inside books, day streak and best streak, gems earned, books
  finished, chapters opened, words explored, stories shared, communities
  joined and chapters you published. Find it at the top of Streaks.
- **Finish-line magic**: reach the last chapter and the reader grows a
  golden "Finish the book" button — tap it for confetti, a trophy, and a
  one-time **+5 gem** finish bonus, counted forever in your Wrapped.

## 1.7.0+9 — 2026-09-05

- **The BookNest Reader is here** — the big one. Every published book can
  now be read inside the app, full screen and distraction-free:
  - Typography that bends to you: text size from 14 to 22 pt, and
    Snug / Comfy / Airy line spacing.
  - Tap anywhere to fade the chrome away; the chapter, your percent read
    and a cyan hairline of progress stay quietly in view.
  - A chapters drawer to jump around, with the current chapter marked.
  - **Resume anywhere**: your exact spot — chapter and scroll position —
    is saved to your account as you read, so My Library's new
    "Continue reading" shelf and the book page's Continue button put you
    back in the story instantly.
  - **Reading feeds your streak**: daily reading earns +2 gems and grows
    your streak, celebrated right in the reader.
  - All of it on the watermark canvas — a whisper of open books under
    every page.

## 1.6.0+8 — 2026-09-05

- **Chat, rebuilt**: 1:1 and all-new club group chats now sit on a custom
  BookNest watermark canvas — soft open-book and quill glyphs under glass
  bubbles, day separators, delivery ticks, photo messages (stored in the
  chat folder on Cloudinary) and the same composer everywhere. Group
  chats are members-only and open from any club's page.
- **Likes, fixed**: the feed now reads real like counts and your own
  like state straight from the data store — tap once and it sticks.
- **Your groups, visible**: creating a club/community/organization/school
  returns you to a list that refreshes instantly (pull-to-refresh too),
  and creators always see their own groups — private ones included.
- **Reels removed**: BookNest is stories and pictures — the reel
  composer, cards and routes are gone completely.
- Every event now comes from the app's own data store.

## 1.5.0+7 — 2026-09-05

- **The architecture is complete**: feed posts, clubs, communities,
  organizations, schools, books and chapters now all live on the app's
  own data store. Supabase keeps exactly two jobs — your sign-in and
  your profile identity. Your existing posts, books and groups carried
  over automatically, ids intact (likes and reviews untouched).
- **Permissions, asked properly**: a single friendly screen requests
  notifications and photo access once — with a plain-English reason for
  each — and stays available in Settings → App permissions.
- Connection status now tests the real data chain end to end.
- Version numbering catches up to the shipped feature set.

## 1.3.1+5 — 2026-09-03

- **Connection status now tells the full truth**: the services check no
  longer stops at "awake" — it verifies the data layer behind wallet,
  Jenny, likes and trends, and says plainly when one more setting is
  needed project-side.
- Version shown in Settings now comes from the app's single config
  source, so it can never go stale again.

## 1.3.0+4 — 2026-09-01

- **Word Nest is here**: a full dictionary built into the app — meanings,
  examples, and kindred words for the vocabulary readers meet. Works
  completely offline.
- Word of the day, refreshed automatically; recent searches remembered on
  your device.
- **Trending words** shows what the community is looking up this week when
  you are online.
- Lucky dip: shake up a random word whenever curiosity strikes.
- Find the dictionary from global search, or deep-link straight into a word.
- The feed now refreshes with a pull, and likes give a little haptic tick.

## 1.2.0+3 — 2026-09-01

- **Permanent app identity**: every build now ships with the same release
  signature, so installs update in place — no more "app not installed"
  conflicts and no data loss between versions.
- **Feed likes go live**: likes are saved to your account, counts are real
  and sync everywhere you sign in.
- Like counters now animate as they change.
- Android 13+ themed (monochrome) app icon for wallpaper-tinted launchers.
