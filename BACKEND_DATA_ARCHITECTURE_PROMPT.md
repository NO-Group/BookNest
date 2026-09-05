# BookNest — Backend Architecture v2 (Multi-Cloud Blueprint)

> Status: **implemented, pending deployment.** The Flutter app is already wired
> to this architecture. Run `backend/README.md` to go live. Supabase tables that
> bridge the transition are in `backend/supabase_min_schema.sql`.
> The Mongo document contract: `docs/MONGO_SCHEMA.md`.

## 1. Executive overview

BookNest is a zero-cost, high-performance social reading / writing / STEM
ecosystem designed to scale toward 1,000,000 active users without a codebase
rewrite. Heavy assets are decoupled from the primary database to eliminate
egress and bandwidth bottlenecks.

## 2. Four-way service separation — "Supabase leads, it doesn't lift"

| Service | Owns | Never stores |
|---|---|---|
| **Supabase** | Authentication (JWT sessions), the `profiles` row (1:1 with each auth user — usernames, avatar **URL**, gems), lightweight URL strings, and this **edge-function orchestration layer** | Manuscripts, media, like/follow counts, chat bodies, notifications |
| **MongoDB Atlas** | Books + chapters (manuscripts), posts, likes, saves, views, reviews, comments, follows + counts, conversations, messages, notifications — all via the `booknest-api` edge function (`npm:mongodb`) | Binary media, secrets |
| **Cloudinary** | Book covers, avatars, profile covers, inline feed/chat images — resized & compressed on the fly, URLs cached on device by `cached_network_image` | Heavy files, documents |
| **Cloudflare R2** | Voice notes, chat videos, document attachments ≤ 300 MB (`.txt .pdf .epub .docx`) via pre-signed URLs from edge functions | Anything needing per-request transformation |

**Rule enforced in code:** Supabase rows never hold content heavier than a URL
string. If it counts, scrolls, or streams — it's MongoDB behind the edge
function. If it's an image — Cloudinary. If it's heavy media — R2.

## 3. Data flows

### A. Manuscript publishing
```
BookEditorScreen (Markdown)
  → books.publish → booknest-api edge function (Supabase JWT verified)
  → MongoDB: chapters[] docs + books metadata doc (counters zeroed)
  → library feeds list from books (indexes on createdAt / genre / author)
```

### B. Images (avatars, covers, feed posts)
```
Flutter picks file → CloudinaryService.uploadImage (unsigned preset "BookNest")
  → Cloudinary returns optimized secure_url
  → URL stored in the profile/book/post document
```

### C. Heavy files (voice notes, videos, ≤300MB documents) — when R2 lands
```
App asks booknest-api for a pre-signed multipart URL (R2 keys are edge secrets)
  → app streams straight into R2 → public URL registered on the chat/post doc
```

### D. Social actions (like / save / view / review / follow)
```
Optimistic UI update in Flutter (instant icon + counter flip)
  → fire-and-forget to booknest-api
  → unique compound index insert/deleting + atomic $inc on denormalized counters
  → failure = silent no-op (UI stays; syncs on next successful call)
```

## 4. Caching (three layers)

1. **Device** — `cached_network_image` pins every Cloudinary avatar/cover after
   first view; no repeat HTTP cost while scrolling feeds.
2. **Edge** — R2 + Cloudinary responses ride Cloudflare's global CDN; documents
   and audio hit the nearest data center.
3. **Function** — read-heavy responses (featured books, announcements) can be
   memoized in module-level function memory, shielding Atlas M0 read limits.

## 5. Scale path to 1M users

- **MongoDB:** free M0 (512 MB) → paid tiers with **zero schema changes**
  (collections + indexes here are production-shaped from day one).
- **R2:** zero egress fees; storage-only pricing — media growth never spikes
  the bill; Supabase bandwidth stays near-zero because media bypasses it.
- **Supabase:** only auth + tiny profile rows + function orchestration — stays
  on the free tier far longer than a monolith design would.

## 6. Pitfalls (enforced by `supabase/functions/booknest-api/index.ts`)

1. ✗ No arrays of user IDs inside book documents → `book_likes`, `book_views`,
   `follows`, … collections with **unique compound indexes**.
2. ✗ No `countDocuments()` per scroll → all counts are `$inc`-maintained
   denormalized fields (`likeCount`, `followers`, …).
3. ✓ Optimistic UI in Flutter with silent rollback semantics — hearts flip
   instantly; network failures never block the reader.

## 7. Credential placement (locked by code review)

**In-app (`lib/config/app_config.dart`) — public-by-design only:**
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `CLOUDINARY_CLOUD_NAME`,
`CLOUDINARY_UPLOAD_PRESET`, `R2_PUBLIC_DOMAIN_URL`.

**Edge Function secrets (`backend/setup_secrets.sh`) — everything else:**
`MONGO_URI`, `MONGO_DB_NAME`, `SUPABASE_SERVICE_ROLE_KEY`, `R2_ACCOUNT_ID`,
`R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET_NAME`,
`R2_PUBLIC_DOMAIN_URL`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`.

Secrets live in `backend/secrets.local.env` (git-ignored). Rotate any
credential that has ever been pasted into a chat.

## 8. Cutover plan (transitional Supabase tables → MongoDB)

| Phase | Reads served by | Status |
|---|---|---|
| 1 (now) | feed/groups/library → Supabase tables; likes/saves/reviews/shares/views → edge API (MongoDB) | ✅ wired |
| 2 | library + book pages read `books.list/get/chapter` from edge API; editor publishes via `books.publish` | deploy + flip |
| 3 | feed + groups migrate to Mongo collections; drop transitional Supabase tables | after v1.1 |
| 4 | R2 signed uploads for heavy media | when R2 creds exist |

V1.1 checklist: deploy edge function → smoke tests → create Supabase tables →
log in → like/save/review/share with a second account → counters + chats land
in MongoDB (Atlas browser to verify).
