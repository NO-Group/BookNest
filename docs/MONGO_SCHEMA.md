# MongoDB Atlas Schema — 7 dedicated databases in the `Books` cluster

BookNest stores **everything except authentication** in MongoDB (Supabase
leads, MongoDB does the heavy lifting). **Every data domain gets its own
database** inside the cluster, so likes can never mix with chats and book
metadata can never mix with reviews:

| Database | Collections | What lives there |
|---|---|---|
| `booknest_books` | `books`, `chapters` | Book metadata + chapter manuscripts |
| `booknest_social` | `book_likes`, `book_bookmarks`, `book_views`, `follows`, `user_stats` | Every reader action + counters |
| `booknest_reviews` | `reviews`, `comments` | Ratings, written reviews, discussion |
| `booknest_chats` | `conversations`, `messages` | Direct messages + book shares |
| `booknest_notifications` | `notifications` | Per-user notification feed |
| `booknest_users` | `user_prefs` | Favorite genres / personalization |
| `booknest_moderation` | `reports` | User reports for moderators |

The edge function routes every collection through `dbFor('<domain>')` —
there is no code path that can write a chat into the books database.
Manuscripts are the only large text payloads; media lives on Cloudinary/R2
and is referenced by URL strings.

Index bootstrap runs automatically at edge-function cold start (idempotent).

## Collections

### `books` — one doc per book (metadata + denormalized counters)
```jsonc
{
  "_id": ObjectId,
  "title": "The Ink Fortress",
  "authorId": "<supabase auth uid>",        // owner
  "authorName": "Ada Obi",                  // denormalized for fast lists
  "description": "…",
  "genre": "Fantasy",                       // one of the 22 BookNest genres | null
  "coverUrl": "https://res.cloudinary.com/…/booknest/covers/….jpg", // null → gradient placeholder
  "contentFormat": "markdown",
  "moderationStatus": "approved",           // v1.1 auto-approves; queue comes later
  "chaptersCount": 3,
  "likeCount": 0, "bookmarkCount": 0, "viewCount": 0,
  "reviewCount": 0, "ratingSum": 0,         // average = ratingSum / reviewCount
  "createdAt": Date, "updatedAt": Date
}
```
Indexes: `{createdAt:-1}`, `{authorId:1}`, `{genre:1, createdAt:-1}`

### `chapters` — one doc per chapter (keeps docs small; no 16MB risk)
```jsonc
{ "_id": ObjectId, "bookId": "<books._id>", "chapterNumber": 1,
  "title": "Chapter 1", "content": "## Markdown…", }
```
Indexes: `{bookId:1, chapterNumber:1} unique`

### Identity collections — the blueprint's "never store arrays of user IDs"
| Collection | Doc | Unique index |
|---|---|---|
| `book_likes` | `{bookId, userId, createdAt}` | `{bookId, userId}` |
| `book_bookmarks` | `{bookId, userId, createdAt}` | `{bookId, userId}` + `{userId, createdAt}` |
| `book_views` | `{bookId, userId, day:"YYYY-MM-DD", createdAt}` | `{bookId, userId, day}` → 1 view/user/day |
| `reviews` | `{bookId, userId, userName, rating 1–5, body, likeCount, createdAt, updatedAt}` | `{bookId, userId}` → one editable review per user |
| `comments` | `{bookId, reviewId?, userId, body, likeCount, createdAt}` | — |
| `follows` | `{followerId, followeeId, createdAt}` | `{followerId, followeeId}` |

### Counters — `user_stats` (never `countDocuments()` on scroll)
```jsonc
{ "userId": "<uid>", "followers": 12, "following": 34, "posts": 5 }
```
Maintained atomically with `$inc` (and `$setOnInsert` seeds) inside the same
request as the follow/unfollow — indexes make toggles idempotent.

### Chats
```jsonc
// conversations — fixed-size memberIds (2 for direct), unique reuse key
{ "_id": ObjectId, "type": "direct", "memberKey": "uidA|uidB", // sorted join
  "memberIds": ["uidA","uidB"], "lastMessage": {…}, "createdAt": Date, "updatedAt": Date }

// messages — media is ALWAYS a URL (Cloudinary/R2), type text|book_share|image|file|voice
{ "_id": ObjectId, "conversationId": "…", "senderId": "…", "type": "book_share",
  "text": "The Ink Fortress", "bookId": "…", "bookTitle": "The Ink Fortress",
  "mediaUrl": null, "createdAt": Date }
```
Indexes: `conversations {memberKey} unique`, `messages {conversationId, _id:-1}`
(ObjectId pagination — monotonic, no skip/limit scans).

### `notifications`
```jsonc
{ "_id": ObjectId, "userId": "…", "type": "dm", "actorId": "…",
  "conversationId": "…", "bookId": "…", "text": "📖 The Ink Fortress",
  "read": false, "createdAt": Date }
```
Index: `{userId:1, createdAt:-1}`

## Invariants enforced by the edge function
1. Every **write** requires a valid Supabase JWT; **reads** are public.
2. Toggles are race-safe: unique-index insert → `$inc` counter only when the
   identity row was actually created/deleted. Double-taps can't double-count.
3. Reviews recompute `ratingSum` incrementally on create **and** edit
   (delta = new − old) — no aggregation jobs, no `countDocuments`.
4. Chapter content capped at 500KB/chapter, 300 chapters/book.
5. Cursor pagination everywhere (`createdAt`/`_id`), limits ≤ 50/100.

## v1.2 additions

| Database | Collection | Purpose |
|---|---|---|
| booknest_users | gem_ledger | One document per gem movement (`userId, delta, reason, day, createdAt`); the `daily` reason + unique UTC day enforces one claim per day |
| booknest_chats | jenny_messages | Ask-Jenny conversation turns (`userId, role user|assistant, content, createdAt`); last 10 turns are replayed as model context |

Balance source of truth stays `profiles.gems` (Supabase); the ledger is the
audit trail. New edge actions: `wallet.summary`, `wallet.claim`, `jenny.chat`
(Jenny needs the optional `JENNY_API_KEY` / `JENNY_API_URL` / `JENNY_MODEL`
edge secrets — without a key she answers honestly that she is not connected).

## v1.3 additions (events agenda · reading streaks · club moderation)

| Database | Collection | Purpose |
|---|---|---|
| booknest_social | event_rsvps | One doc per RSVP (`userId, postId, createdAt`); toggle = insert/delete; per-event counts via aggregation |
| booknest_social | reading_logs | One doc per logged day (`userId, day 'YYYY-MM-DD', minutes, createdAt`); streaks are computed from distinct `day` values; the first log of each UTC day awards +2 gems (ledger entry `reason: reading_streak`) |
| (existing) | gem_ledger | New reasons: `reading_streak` (+2/day), `book_publish` (+10 on moderation approval) |

New edge actions: `events.list`, `events.rsvp`, `streak.get`, `streak.log`,
`moderation.queue`, `moderation.decide` (owner-verified server-side; no new
SQL — events reuse the `posts` table, moderation reuses `club_books`
moderation_status).
