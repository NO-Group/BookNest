# MongoDB Atlas Schema — `booknest` database

BookNest stores **everything except authentication** here (Supabase leads,
MongoDB does the heavy lifting). Manuscripts are the only large text payloads;
media lives on Cloudinary/R2 and is referenced by URL strings.

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
