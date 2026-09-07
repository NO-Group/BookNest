# BookNest Launch Readiness Audit — v2.5.0+17 (2026-09-07)

Every aspect of the app was scrutinized against the bar both app stores
apply: legal requirements, UGC policy, privacy, safety, copy quality,
build hygiene and in-app polish. Result per area:

## Store-rejection blockers — all cleared this release

| # | Requirement (source) | Status before | What shipped |
|---|---|---|---|
| 1 | Account deletion (Apple 5.1.1(v), Play account policy) | ❌ absent | **Settings → Delete my account** — typed double-confirm, server-side cascade (profile row + auth user + books, chapters, likes, saves, views, follows, posts, post likes/views/reshares/comments, reviews, messages, conversations, gem ledger, blocks, reports), honest failure copy, local cache + prefs wiped, real sign-out |
| 2 | UGC reporting (Play UGC policy, Apple 1.2) | ❌ absent | **Report sheet** on posts (flag on every card), messages (chat toolkit), books (book page), profiles (⋯ menu) — 10 moderation reasons + free text, stored with reporter id in a dedicated `booknest_moderation` database |
| 3 | Blocking abusive users (Apple 1.2) | ❌ absent | **Server-enforced blocks**: `dm.block/unblock/blocklist`; blocked readers cannot DM, their club messages are filtered out of your inbox, unblock from their profile |
| 4 | iOS purpose strings (App Review crash/reject) | ❌ missing | `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSPhotoLibraryUsageDescription`, notifications — real, user-facing copy |
| 5 | Terms of Service (expected by both) | ❌ absent | Readable, real ToS screen at `/terms`; linked from sign-up ("By creating an account…"), Settings and About |
| 6 | Legal links at account creation | ❌ absent | Terms + Privacy links on the register screen |

## Verified already-strong (no change needed)

- **Secrets hygiene** — app ships only public-by-design keys; service
  secrets live exclusively in the edge function (audited `app_config.dart`).
- **Permissions** — Android manifest declares exactly what the app uses
  (INTERNET, notifications, camera, mic, media read) and no more.
- **Production copy** — no TODO/placeholder/lorem strings in user-visible
  copy; every error message is honest and actionable (audit-enforced).
- **No debug prints** in shipped code paths.
- **Onboarding** collects country, gender, age, languages + fluency —
  editable in Settings (feeds store age-rating answers).
- **Offline/truthful states** — every network failure degrades to an
  honest message; the voice feature refuses to fake success without real
  cloud config.
- **Performance** — 60-second read-through cache, custom loader, debounced
  typing (no jank), pull-to-refresh always fresh.
- **Stale copy** — About screen footer refreshed ("Next stop: v1.2…"
  removed; legal links added).

## Deliberately clean (checked, safe)

- No IAP needed: gems cannot be purchased — keeps the listing out of
  payment-review complexity.
- No tracking SDKs, ads, or third-party analytics: the privacy labels stay
  minimal and truthful.
- No external browser hand-offs for media: everything opens in-app.

## Known non-blockers (watchlist)

1. **Edge function re-paste required** — this release added
   `account.delete`, `moderation.report`, `dm.block`, `dm.unblock`,
   `dm.blocklist` to `supabase/functions/booknest-api/index.ts`. Until it
   is pasted in the Supabase dashboard, reports/blocks/deletion answer
   "could not complete" honestly and everything else works.
2. **Reports review tooling** — reports accumulate in MongoDB
   (`booknest_moderation.reports`); reviewing them for now means a query.
   A mini moderation dashboard is the natural next request.
3. **Crash reporting** — none integrated. Optional; adding Sentry/Crashlytics
   later means updating the data-safety answers.
4. **Support email / privacy URL** — consoles require them; see
   `docs/STORE_LISTING.md` → "Console requirements".

## Build facts

- Version `2.5.0+17` in `pubspec.yaml` and `app_config.dart` (single
  source, shown in Settings/About).
- CI builds the signed release APK (`BookNest-release-apk` artifact),
  applicationId `com.n_o_group.booknest`.
- App icon: `assets/logo/booknest_logo_new_transparent_dark_theme.png`
  (unchanged, fully transparent, per the standing rule).
