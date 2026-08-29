// ============================================================================
// BookNest gateway API — supabase/functions/booknest-api
// ============================================================================
// ARCHITECTURE (see docs/MONGO_SCHEMA.md + BACKEND_DATA_ARCHITECTURE_PROMPT.md):
//   Supabase  → authentication ONLY + this orchestration layer. It "leads".
//   MongoDB   → the heavy lifting: books, chapters, likes, saves, views,
//               reviews, follows, chats, notifications, counters.
//   Cloudinary→ images (covers/avatars/feed/chat) — stored as URL strings here.
//   Cloudflare R2 → heavy media (voice notes, videos, ≤300MB docs) — URLs only.
//
// SECRETS (set via backend/setup_secrets.sh — never in Flutter, never in Git):
//   MONGO_URI, MONGO_DB_NAME, SUPABASE_SERVICE_ROLE_KEY, R2_*, CLOUDINARY_API_*
//   SUPABASE_URL + SUPABASE_ANON_KEY are injected automatically per runtime.
//
// PITFALLS HONORED (per blueprint):
//   ✗ No arrays of user IDs inside book documents → like/save/view/review
//     identities live in their own collections behind unique compound indexes.
//   ✗ No countDocuments() in scroll/list paths → all counters are denormalized
//     and maintained with atomic $inc at write time.
//   ✓ Unique indexes make every action idempotent and race-safe
//     (double-taps can never double-count).
// ============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { MongoClient, ObjectId } from 'npm:mongodb@6.7.0';

const MONGO_URI = Deno.env.get('MONGO_URI') ?? '';
const MONGO_DB_NAME = Deno.env.get('MONGO_DB_NAME') ?? 'booknest';

const CORS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}
const ok = (data: unknown) => json({ ok: true, data });
const fail = (error: string, status = 400) => json({ ok: false, error }, status);

// ---------------------------------------------------------------------------
// MongoDB connection (cached across invocations — one client per cold start)
// ---------------------------------------------------------------------------
// One database per data domain inside the Atlas cluster — likes never mix
// with chats, books never mix with reviews. A single shared client, a cached
// handle per database.
export const DB_NAMES = {
  books: 'booknest_books', // books metadata + chapters (manuscripts)
  social: 'booknest_social', // likes, saves, views, follows, follower counts
  reviews: 'booknest_reviews', // reviews + comments
  chats: 'booknest_chats', // conversations + messages
  notifications: 'booknest_notifications',
  users: 'booknest_users', // reader preferences
  moderation: 'booknest_moderation', // reports
} as const;

type Domain = keyof typeof DB_NAMES;

let mongoClientPromise: Promise<import('npm:mongodb@6.7.0').MongoClient> | null = null;
const dbCache = new Map<Domain, Promise<import('npm:mongodb@6.7.0').Db>>();

function mongoClient(): Promise<import('npm:mongodb@6.7.0').MongoClient> {
  if (!mongoClientPromise) {
    if (!MONGO_URI) {
      return Promise.reject(
        new Error('MONGO_URI secret is not set — see backend/DEPLOY_FROM_DASHBOARD.md'),
      );
    }
    const client = new MongoClient(MONGO_URI, {
      appName: 'booknest-edge',
      serverSelectionTimeoutMS: 8000,
    });
    mongoClientPromise = client.connect();
  }
  return mongoClientPromise;
}

function dbFor(domain: Domain): Promise<import('npm:mongodb@6.7.0').Db> {
  let cached = dbCache.get(domain);
  if (!cached) {
    cached = mongoClient().then((client) => {
      const database = client.db(DB_NAMES[domain]);
      void ensureIndexes(database, domain);
      return database;
    });
    dbCache.set(domain, cached);
  }
  return cached;
}

// Idempotent per-database index bootstrap (safe to repeat on cold starts).
async function ensureIndexes(
  database: import('npm:mongodb@6.7.0').Db,
  domain: Domain,
): Promise<void> {
  try {
    switch (domain) {
      case 'books':
        await Promise.all([
          database.collection('books').createIndex({ createdAt: -1 }),
          database.collection('books').createIndex({ authorId: 1 }),
          database.collection('books').createIndex({ genre: 1, createdAt: -1 }),
          database.collection('chapters').createIndex(
            { bookId: 1, chapterNumber: 1 },
            { unique: true },
          ),
        ]);
        break;
      case 'social':
        await Promise.all([
          database.collection('book_likes').createIndex({ bookId: 1, userId: 1 }, { unique: true }),
          database.collection('book_bookmarks').createIndex({ bookId: 1, userId: 1 }, { unique: true }),
          database.collection('book_bookmarks').createIndex({ userId: 1, createdAt: -1 }),
          database.collection('book_views').createIndex({ bookId: 1, userId: 1, day: 1 }, { unique: true }),
          database.collection('follows').createIndex({ followerId: 1, followeeId: 1 }, { unique: true }),
          database.collection('user_stats').createIndex({ userId: 1 }, { unique: true }),
        ]);
        break;
      case 'reviews':
        await Promise.all([
          database.collection('reviews').createIndex({ bookId: 1, userId: 1 }, { unique: true }),
          database.collection('reviews').createIndex({ bookId: 1, createdAt: -1 }),
          database.collection('comments').createIndex({ bookId: 1, createdAt: -1 }),
        ]);
        break;
      case 'chats':
        await Promise.all([
          database.collection('conversations').createIndex({ memberKey: 1 }, { unique: true }),
          database.collection('conversations').createIndex({ memberIds: 1, updatedAt: -1 }),
          database.collection('messages').createIndex({ conversationId: 1, _id: -1 }),
        ]);
        break;
      case 'notifications':
        await database.collection('notifications')
          .createIndex({ userId: 1, createdAt: -1 });
        break;
      case 'users':
        await database.collection('user_prefs').createIndex({ userId: 1 }, { unique: true });
        break;
      case 'moderation':
        await database.collection('reports').createIndex({ status: 1, createdAt: -1 });
        break;
    }
  } catch (error) {
    console.error(`index bootstrap failed for ${domain}:`, error);
  }
}

// ---------------------------------------------------------------------------
// Auth — verify the caller's Supabase JWT and resolve their user id.
// (deployed with verify_jwt = false so anonymous READS work; every WRITE
//  still requires a valid user below — enforced right here.)
// ---------------------------------------------------------------------------
async function currentUserId(req: Request): Promise<string | null> {
  const token = (req.headers.get('Authorization') ?? '')
    .replace(/^Bearer\s+/i, '')
    .trim();
  if (!token) return null;
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
    );
    const { data, error } = await supabase.auth.getUser(token);
    if (error || !data.user) return null;
    return data.user.id;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------
function escapeRegex(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
const todayUtc = () => new Date().toISOString().slice(0, 10); // YYYY-MM-DD
const isHexId = (v: unknown): boolean =>
  typeof v === 'string' && /^[a-f\d]{24}$/i.test(v);
const isDupKey = (e: unknown): boolean =>
  e instanceof Error && e.message.includes('E11000');

function bookView(b: Record<string, unknown>) {
  const reviewCount = Number(b.reviewCount ?? 0);
  const ratingSum = Number(b.ratingSum ?? 0);
  return {
    id: String(b._id),
    title: b.title ?? 'Untitled',
    author: b.authorName ?? 'Unknown',
    description: b.description ?? '',
    genre: b.genre ?? null,
    cover_url: b.coverUrl ?? null,
    content_format: b.contentFormat ?? 'markdown',
    moderation_status: b.moderationStatus ?? 'pending',
    like_count: Math.max(0, Number(b.likeCount ?? 0)),
    bookmark_count: Math.max(0, Number(b.bookmarkCount ?? 0)),
    view_count: Math.max(0, Number(b.viewCount ?? 0)),
    review_count: reviewCount,
    average_rating:
      reviewCount > 0 ? Math.round((ratingSum / reviewCount) * 10) / 10 : 0,
    created_at: b.createdAt ?? null,
  };
}

function conversationView(c: Record<string, unknown>, me: string) {
  const members = Array.isArray(c.memberIds) ? (c.memberIds as string[]) : [];
  return {
    id: String(c._id),
    type: c.type ?? 'direct',
    peerId: members.find((m) => m !== me) ?? me,
    lastMessage: c.lastMessage ?? null,
    updatedAt: c.updatedAt ?? null,
  };
}

async function userStats(userId: string) {
  const d = await dbFor('social');
  const doc = await d.collection('user_stats').findOne({ userId });
  return {
    followers: Math.max(0, Number(doc?.followers ?? 0)),
    following: Math.max(0, Number(doc?.following ?? 0)),
    posts: Math.max(0, Number(doc?.posts ?? 0)),
  };
}

/** Finds or creates the 1:1 conversation between two users (reused forever). */
async function ensureDirect(a: string, b: string): Promise<Record<string, unknown>> {
  const d = await dbFor('chats');
  const memberKey = [a, b].sort().join('|');
  const found = await d.collection('conversations').findOne({ memberKey });
  if (found) return conversationView(found, a);
  const now = new Date();
  const doc = {
    type: 'direct',
    memberKey,
    memberIds: [a, b],
    createdAt: now,
    updatedAt: now,
    lastMessage: null,
  };
  try {
    const inserted = await d.collection('conversations').insertOne({ ...doc });
    return conversationView({ ...doc, _id: inserted.insertedId }, a);
  } catch (error) {
    if (isDupKey(error)) {
      const raced = await d.collection('conversations').findOne({ memberKey });
      if (raced) return conversationView(raced, a);
    }
    throw error;
  }
}

// ---------------------------------------------------------------------------
// Main handler
// ---------------------------------------------------------------------------
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

  if (req.method === 'GET') {
    return ok({
      service: 'booknest-api',
      actions: [
        'ping',
        'books.list', 'books.get', 'books.chapter', 'books.publish',
        'books.like', 'books.bookmark', 'books.view',
        'reviews.create', 'reviews.list',
        'social.follow',
        'dm.ensure', 'dm.send', 'dm.list', 'dm.messages',
        'notifications.list', 'notifications.read',
      ],
    });
  }
  if (req.method !== 'POST') return fail('Use POST', 405);

  let body: { action?: string; payload?: Record<string, unknown> };
  try {
    body = await req.json();
  } catch {
    return fail('Invalid JSON body');
  }
  const action = body.action ?? '';
  const p = body.payload ?? {};

  try {
    switch (action) {
      // ── health ───────────────────────────────────────────────────────────
      case 'ping': {
        const d = await dbFor('books');
        return ok({
          db: d.databaseName,
          databases: DB_NAMES,
          time: new Date().toISOString(),
        });
      }

      // ── books: browse ────────────────────────────────────────────────────
      case 'books.list': {
        const d = await dbFor('books');
        const limit = Math.min(Number(p.limit ?? 20) || 20, 50);
        const query: Record<string, unknown> = {};
        if (p.mine === true) {
          const uid = await currentUserId(req);
          if (!uid) return fail('Sign in required', 401);
          query.authorId = uid;
        } else {
          // v1.1 auto-approves everything; flip to a moderation queue later.
          query.moderationStatus = p.moderationStatus ?? 'approved';
        }
        if (typeof p.genre === 'string' && p.genre.trim()) query.genre = p.genre.trim();
        const search = typeof p.search === 'string' ? p.search.trim() : '';
        if (search) {
          const rx = { $regex: escapeRegex(search), $options: 'i' };
          query.$or = [{ title: rx }, { authorName: rx }];
        }
        if (typeof p.before === 'string' && p.before) {
          const before = new Date(p.before);
          if (!isNaN(before.getTime())) query.createdAt = { $lt: before };
        }
        const rows = await d.collection('books')
          .find(query).sort({ createdAt: -1 }).limit(limit + 1).toArray();
        const hasMore = rows.length > limit;
        return ok({
          books: rows.slice(0, limit).map(bookView),
          nextCursor: hasMore ? rows[limit - 1].createdAt : null,
        });
      }

      case 'books.get': {
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const d = await dbFor('books');
        const book = await d.collection('books')
          .findOne({ _id: new ObjectId(p.bookId as string) });
        if (!book) return fail('Book not found', 404);
        const chapters = await d.collection('chapters')
          .find({ bookId: String(book._id) })
          .project({ _id: 0, chapterNumber: 1, title: 1 })
          .sort({ chapterNumber: 1 })
          .toArray();
        return ok({ book: bookView(book as Record<string, unknown>), chapters });
      }

      case 'books.chapter': {
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const chapterNumber = Number(p.chapterNumber ?? 1) || 1;
        const d = await dbFor('books');
        const chapter = await d.collection('chapters')
          .findOne({ bookId: p.bookId as string, chapterNumber });
        if (!chapter) return fail('Chapter not found', 404);
        return ok({
          chapterNumber: chapter.chapterNumber,
          title: chapter.title,
          content: chapter.content ?? '',
        });
      }

      // ── books: publish (author writes manuscript → MongoDB) ─────────────
      case 'books.publish': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        const title = String(p.title ?? '').trim();
        if (title.length < 2 || title.length > 200) {
          return fail('Title must be 2–200 characters');
        }
        const rawChapters = Array.isArray(p.chapters) ? p.chapters : [];
        if (rawChapters.length === 0) return fail('At least one chapter is required');
        if (rawChapters.length > 300) return fail('Too many chapters (max 300)');
        const chapters = rawChapters.map((raw, index) => {
          const c = (raw ?? {}) as Record<string, unknown>;
          return {
            chapterNumber: Number(c.chapterNumber ?? index + 1) || index + 1,
            title: String(c.title ?? `Chapter ${index + 1}`).slice(0, 200),
            content: String(c.content ?? '').slice(0, 500_000), // guard 16MB docs
          };
        });
        const d = await dbFor('books');
        const now = new Date();
        const book = {
          title,
          authorId: uid,
          authorName: String(p.authorName ?? 'BookNest author').slice(0, 80),
          description: String(p.description ?? '').slice(0, 5000),
          genre: typeof p.genre === 'string' && p.genre.trim() ? p.genre.trim() : null,
          coverUrl: typeof p.coverUrl === 'string' && p.coverUrl.startsWith('http')
            ? p.coverUrl
            : null,
          contentFormat: 'markdown',
          // v1.1: auto-approved so authors see their work instantly. When
          // moderation tooling ships, default this back to 'pending'.
          moderationStatus: 'approved',
          chaptersCount: chapters.length,
          likeCount: 0,
          bookmarkCount: 0,
          viewCount: 0,
          reviewCount: 0,
          ratingSum: 0,
          createdAt: now,
          updatedAt: now,
        };
        const inserted = await d.collection('books').insertOne({ ...book });
        const bookId = inserted.insertedId.toHexString();
        await d.collection('chapters').insertMany(
          chapters.map((c) => ({ ...c, bookId })),
        );
        return ok({ id: bookId, book: bookView({ ...book, _id: inserted.insertedId }) });
      }

      // ── books: like / bookmark / view (atomic, idempotent) ───────────────
      case 'books.like':
      case 'books.bookmark': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const active = action === 'books.like' ? p.liked === true : p.saved === true;
        const collection = action === 'books.like' ? 'book_likes' : 'book_bookmarks';
        const counter = action === 'books.like' ? 'likeCount' : 'bookmarkCount';
        const bookId = p.bookId as string;
        const d = await dbFor('books');
        const filter = { bookId, userId: uid };
        if (active) {
          try {
            await (await dbFor('social')).collection(collection).insertOne({ ...filter, createdAt: new Date() });
          } catch (error) {
            if (!isDupKey(error)) throw error; // already liked/saved → no-op
          }
        } else {
          const removed = await (await dbFor('social')).collection(collection).deleteOne(filter);
          if (removed.deletedCount === 0) {
            const book = await d.collection('books')
              .findOne({ _id: new ObjectId(bookId) }, { projection: { [counter]: 1 } });
            return ok({
              [action === 'books.like' ? 'liked' : 'saved']: false,
              [counter]: Math.max(0, Number(book?.[counter] ?? 0)),
            });
          }
        }
        const updated = await d.collection('books').findOneAndUpdate(
          { _id: new ObjectId(bookId) },
          { $inc: { [counter]: active ? 1 : -1 } },
          { returnDocument: 'after', projection: { [counter]: 1 } },
        );
        const value = Math.max(0, Number(updated?.[counter] ?? 0));
        if (value === 0) {
          await d.collection('books')
            .updateOne({ _id: new ObjectId(bookId) }, { $set: { [counter]: 0 } });
        }
        return ok({
          [action === 'books.like' ? 'liked' : 'saved']: active,
          [counter]: value,
        });
      }

      case 'books.view': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const bookId = p.bookId as string;
        const d = await dbFor('books');
        // Unique (bookId, userId, day) index → one view per user per day.
        let counted = true;
        try {
          await (await dbFor('social')).collection('book_views').insertOne({
            bookId,
            userId: uid,
            day: todayUtc(),
            createdAt: new Date(),
          });
        } catch (error) {
          if (!isDupKey(error)) throw error;
          counted = false;
        }
        let viewCount = 0;
        if (counted) {
          const updated = await d.collection('books').findOneAndUpdate(
            { _id: new ObjectId(bookId) },
            { $inc: { viewCount: 1 } },
            { returnDocument: 'after', projection: { viewCount: 1 } },
          );
          viewCount = Number(updated?.viewCount ?? 1);
        } else {
          const book = await d.collection('books')
            .findOne({ _id: new ObjectId(bookId) }, { projection: { viewCount: 1 } });
          viewCount = Number(book?.viewCount ?? 0);
        }
        return ok({ counted, viewCount });
      }

      // ── reviews (one editable review per user per book) ──────────────────
      case 'reviews.create': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const bookId = p.bookId as string;
        const rating = Math.round(Number(p.rating ?? 0));
        if (rating < 1 || rating > 5) return fail('Rating must be between 1 and 5');
        const bodyText = String(p.body ?? '').trim().slice(0, 4000);
        const d = await dbFor('reviews');
        const now = new Date();
        const userName = String(p.displayName ?? 'Reader').slice(0, 80);
        const existing = await d.collection('reviews')
          .findOne({ bookId, userId: uid });
        let ratingDelta = rating;
        if (existing) {
          ratingDelta = rating - Number(existing.rating ?? 0);
          await d.collection('reviews').updateOne(
            { _id: existing._id },
            { $set: { rating, body: bodyText, userName, updatedAt: now } },
          );
        } else {
          await d.collection('reviews').insertOne({
            bookId,
            userId: uid,
            userName,
            rating,
            body: bodyText,
            likeCount: 0,
            createdAt: now,
            updatedAt: now,
          });
          await (await dbFor('books')).collection('books')
            .updateOne({ _id: new ObjectId(bookId) }, { $inc: { reviewCount: 1 } });
        }
        if (ratingDelta !== 0) {
          await (await dbFor('books')).collection('books')
            .updateOne({ _id: new ObjectId(bookId) }, { $inc: { ratingSum: ratingDelta } });
        }
        return ok({ saved: true, edited: existing != null });
      }

      case 'reviews.list': {
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const limit = Math.min(Number(p.limit ?? 20) || 20, 50);
        const query: Record<string, unknown> = { bookId: p.bookId as string };
        if (typeof p.before === 'string' && p.before) {
          const before = new Date(p.before);
          if (!isNaN(before.getTime())) query.createdAt = { $lt: before };
        }
        const rows = await (await dbFor('reviews')).collection('reviews')
          .find(query).sort({ createdAt: -1 }).limit(limit + 1).toArray();
        const hasMore = rows.length > limit;
        return ok({
          reviews: rows.slice(0, limit).map((r) => ({
            id: String(r._id),
            userId: r.userId,
            userName: r.userName ?? 'Reader',
            rating: Number(r.rating ?? 0),
            body: r.body ?? '',
            likeCount: Math.max(0, Number(r.likeCount ?? 0)),
            createdAt: r.createdAt,
          })),
          nextCursor: hasMore ? rows[limit - 1].createdAt : null,
        });
      }

      // ── social graph ─────────────────────────────────────────────────────
      case 'social.follow': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        const target = typeof p.userId === 'string' ? p.userId : '';
        if (!target || target === uid) return fail('A valid userId is required');
        const following = p.following === true;
        const d = await dbFor('social');
        let changed = false;
        if (following) {
          try {
            await d.collection('follows').insertOne({
              followerId: uid,
              followeeId: target,
              createdAt: new Date(),
            });
            changed = true;
          } catch (error) {
            if (!isDupKey(error)) throw error;
          }
        } else {
          const removed = await d.collection('follows')
            .deleteOne({ followerId: uid, followeeId: target });
          changed = removed.deletedCount > 0;
        }
        if (changed) {
          await Promise.all([
            d.collection('user_stats').updateOne(
              { userId: uid },
              { $inc: { following: following ? 1 : -1 }, $setOnInsert: { followers: 0, posts: 0 } },
              { upsert: true },
            ),
            d.collection('user_stats').updateOne(
              { userId: target },
              { $inc: { followers: following ? 1 : -1 }, $setOnInsert: { following: 0, posts: 0 } },
              { upsert: true },
            ),
          ]);
        }
        return ok({ following, ...(await userStats(target)) });
      }

      // ── direct messages (share flow + chat) ──────────────────────────────
      case 'dm.ensure': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        const peer = typeof p.peerId === 'string' ? p.peerId : '';
        if (!peer || peer === uid) return fail('A valid peerId is required');
        return ok({ conversation: await ensureDirect(uid, peer) });
      }

      case 'dm.send': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        const d = await dbFor('chats');
        const type = ['text', 'book_share', 'image', 'file', 'voice']
          .includes(String(p.type)) ? String(p.type) : 'text';
        const text = String(p.text ?? '').trim().slice(0, 4000);
        if (type === 'text' && !text) return fail('Message text is empty');
        const bookId = typeof p.bookId === 'string' ? p.bookId.slice(0, 64) : null;
        const bookTitle = typeof p.bookTitle === 'string' ? p.bookTitle.slice(0, 200) : null;
        const mediaUrl = typeof p.mediaUrl === 'string' && p.mediaUrl.startsWith('http')
          ? p.mediaUrl
          : null; // Cloudinary/R2 URLs only — never raw media in the database.

        let conversationId = typeof p.conversationId === 'string' ? p.conversationId : '';
        if (!isHexId(conversationId)) {
          const peer = typeof p.peerId === 'string' ? p.peerId : '';
          if (!peer || peer === uid) return fail('conversationId or peerId is required');
          conversationId = String((await ensureDirect(uid, peer)).id);
        }
        const conversation = await d.collection('conversations')
          .findOne({ _id: new ObjectId(conversationId) });
        if (!conversation || !(conversation.memberIds as string[]).includes(uid)) {
          return fail('Conversation not found', 404);
        }

        const now = new Date();
        const message = {
          conversationId,
          senderId: uid,
          type,
          text,
          bookId,
          bookTitle,
          mediaUrl,
          createdAt: now,
        };
        const inserted = await d.collection('messages').insertOne({ ...message });
        const preview = type === 'book_share'
          ? `📖 ${bookTitle ?? 'Shared a book'}`
          : type === 'text'
            ? text
            : 'Sent an attachment';
        await d.collection('conversations').updateOne(
          { _id: conversation._id },
          { $set: { updatedAt: now, lastMessage: { text: preview.slice(0, 140), senderId: uid, type, createdAt: now } } },
        );
        const peer = (conversation.memberIds as string[]).find((m) => m !== uid);
        if (peer) {
          await (await dbFor('notifications')).collection('notifications').insertOne({
            userId: peer,
            type: 'dm',
            actorId: uid,
            conversationId,
            bookId,
            text: preview.slice(0, 140),
            read: false,
            createdAt: now,
          });
        }
        return ok({
          conversationId,
          messageId: String(inserted.insertedId),
          message: { id: String(inserted.insertedId), ...message },
        });
      }

      case 'dm.list': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        const rows = await (await dbFor('chats')).collection('conversations')
          .find({ memberIds: uid })
          .sort({ updatedAt: -1 })
          .limit(50)
          .toArray();
        return ok({ conversations: rows.map((c) => conversationView(c as Record<string, unknown>, uid)) });
      }

      case 'dm.messages': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        const conversationId = typeof p.conversationId === 'string' ? p.conversationId : '';
        if (!isHexId(conversationId)) return fail('A valid conversationId is required');
        const d = await dbFor('chats');
        const conversation = await d.collection('conversations')
          .findOne({ _id: new ObjectId(conversationId) });
        if (!conversation || !(conversation.memberIds as string[]).includes(uid)) {
          return fail('Conversation not found', 404);
        }
        const limit = Math.min(Number(p.limit ?? 50) || 50, 100);
        const query: Record<string, unknown> = { conversationId };
        if (typeof p.before === 'string' && isHexId(p.before)) {
          query._id = { $lt: new ObjectId(p.before as string) };
        }
        const rows = await d.collection('messages')
          .find(query).sort({ _id: -1 }).limit(limit + 1).toArray();
        const hasMore = rows.length > limit;
        return ok({
          messages: rows.slice(0, limit).reverse().map((m) => ({
            id: String(m._id),
            senderId: m.senderId,
            type: m.type,
            text: m.text ?? '',
            bookId: m.bookId ?? null,
            bookTitle: m.bookTitle ?? null,
            mediaUrl: m.mediaUrl ?? null,
            createdAt: m.createdAt,
          })),
          nextCursor: hasMore ? String(rows[limit - 1]._id) : null,
        });
      }

      // ── notifications ────────────────────────────────────────────────────
      case 'notifications.list': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        const limit = Math.min(Number(p.limit ?? 30) || 30, 50);
        const rows = await (await dbFor('notifications')).collection('notifications')
          .find({ userId: uid }).sort({ createdAt: -1 }).limit(limit).toArray();
        return ok({
          notifications: rows.map((n) => ({
            id: String(n._id),
            type: n.type,
            actorId: n.actorId ?? null,
            conversationId: n.conversationId ?? null,
            bookId: n.bookId ?? null,
            text: n.text ?? '',
            read: n.read === true,
            createdAt: n.createdAt,
          })),
        });
      }

      case 'notifications.read': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        const d = await dbFor('notifications');
        if (p.all === true) {
          await d.collection('notifications')
            .updateMany({ userId: uid, read: { $ne: true } }, { $set: { read: true } });
          return ok({ read: 'all' });
        }
        if (!isHexId(p.notificationId)) return fail('notificationId or all:true required');
        await d.collection('notifications').updateOne(
          { _id: new ObjectId(p.notificationId as string), userId: uid },
          { $set: { read: true } },
        );
        return ok({ read: p.notificationId });
      }

      // ── users & social graph reads ───────────────────────────────────────
      case 'users.get': {
        const target = typeof p.userId === 'string' ? p.userId : '';
        if (!target) return fail('A valid userId is required');
        return ok({ userId: target, ...(await userStats(target)) });
      }

      case 'social.list': {
        const target = typeof p.userId === 'string' ? p.userId : '';
        if (!target) return fail('A valid userId is required');
        const type = p.type === 'following' ? 'following' : 'followers';
        const d = await dbFor('social');
        const query = type === 'followers'
          ? { followeeId: target }
          : { followerId: target };
        const rows = await d.collection('follows')
          .find(query).sort({ createdAt: -1 }).limit(200).toArray();
        const userIds = rows.map((r) =>
          type === 'followers' ? r.followerId : r.followeeId);
        return ok({ type, userIds });
      }

      case 'users.preferences': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        const genres = Array.isArray(p.genres)
          ? p.genres.filter((g) => typeof g === 'string').slice(0, 22)
          : [];
        await (await dbFor('users')).collection('user_prefs').updateOne(
          { userId: uid },
          { $set: { genres, updatedAt: new Date() }, $setOnInsert: { userId: uid } },
          { upsert: true },
        );
        return ok({ saved: genres.length });
      }

      // ── author tools: book & chapter management ──────────────────────────
      case 'books.update': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const d = await dbFor('books');
        const book = await d.collection('books')
          .findOne({ _id: new ObjectId(p.bookId as string) }, { projection: { authorId: 1 } });
        if (!book) return fail('Book not found', 404);
        if (book.authorId !== uid) return fail('Only the author can edit this book', 403);
        const updates: Record<string, unknown> = { updatedAt: new Date() };
        if (typeof p.title === 'string' && p.title.trim().length >= 2) {
          updates.title = p.title.trim().slice(0, 200);
        }
        if (typeof p.description === 'string') {
          updates.description = p.description.slice(0, 5000);
        }
        if (typeof p.genre === 'string' && p.genre.trim()) updates.genre = p.genre.trim();
        if (typeof p.coverUrl === 'string' && p.coverUrl.startsWith('http')) {
          updates.coverUrl = p.coverUrl;
        }
        await d.collection('books')
          .updateOne({ _id: book._id }, { $set: updates });
        return ok({ updated: true });
      }

      case 'books.stats': {
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const d = await dbFor('books');
        const book = await d.collection('books')
          .findOne({ _id: new ObjectId(p.bookId as string) });
        if (!book) return fail('Book not found', 404);
        const view = bookView(book as Record<string, unknown>);
        const recent = await d.collection('reviews')
          .find({ bookId: p.bookId as string })
          .sort({ createdAt: -1 }).limit(5).toArray();
        return ok({ stats: view, recentReviews: recent.map((r) => ({
          id: String(r._id),
          userName: r.userName ?? 'Reader',
          rating: Number(r.rating ?? 0),
          body: r.body ?? '',
          createdAt: r.createdAt,
        })) });
      }

      case 'books.bookmarked': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        const d = await dbFor('social');
        const marks = await d.collection('book_bookmarks')
          .find({ userId: uid }).sort({ createdAt: -1 }).limit(100).toArray();
        const ids = marks.map((m) => m.bookId).filter(isHexId);
        if (ids.length === 0) return ok({ books: [] });
        const books = await (await dbFor('books')).collection('books')
          .find({ _id: { $in: ids.map((id) => new ObjectId(id)) } })
          .toArray();
        const byId = new Map(books.map((b) => [String(b._id), b]));
        const ordered = marks
          .map((m) => byId.get(m.bookId))
          .filter((b) => b != null)
          .map((b) => bookView(b as Record<string, unknown>));
        return ok({ books: ordered });
      }

      case 'chapters.save': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const bookId = p.bookId as string;
        const chapterNumber = Math.round(Number(p.chapterNumber ?? 1)) || 1;
        const title = String(p.title ?? `Chapter ${chapterNumber}`).slice(0, 200);
        const content = String(p.content ?? '').slice(0, 500_000);
        const d = await dbFor('books');
        const book = await d.collection('books')
          .findOne({ _id: new ObjectId(bookId) }, { projection: { authorId: 1 } });
        if (!book) return fail('Book not found', 404);
        if (book.authorId !== uid) return fail('Only the author can edit chapters', 403);
        await d.collection('chapters').updateOne(
          { bookId, chapterNumber },
          { $set: { title, content, updatedAt: new Date() }, $setOnInsert: { bookId, chapterNumber, createdAt: new Date() } },
          { upsert: true },
        );
        const total = await d.collection('chapters').countDocuments({ bookId });
        await d.collection('books')
          .updateOne({ _id: book._id }, { $set: { chaptersCount: total, updatedAt: new Date() } });
        return ok({ saved: true, chaptersCount: total });
      }

      case 'chapters.delete': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const bookId = p.bookId as string;
        const chapterNumber = Math.round(Number(p.chapterNumber ?? 0));
        const d = await dbFor('books');
        const book = await d.collection('books')
          .findOne({ _id: new ObjectId(bookId) }, { projection: { authorId: 1 } });
        if (!book) return fail('Book not found', 404);
        if (book.authorId !== uid) return fail('Only the author can edit chapters', 403);
        const removed = await d.collection('chapters')
          .deleteOne({ bookId, chapterNumber });
        return ok({ deleted: removed.deletedCount > 0 });
      }

      // ── reviews: delete own ──────────────────────────────────────────────
      case 'reviews.delete': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const bookId = p.bookId as string;
        const d = await dbFor('reviews');
        const existing = await d.collection('reviews').findOne({ bookId, userId: uid });
        if (!existing) return ok({ deleted: false });
        await d.collection('reviews').deleteOne({ _id: existing._id });
        await (await dbFor('books')).collection('books').updateOne(
          { _id: new ObjectId(bookId) },
          { $inc: { reviewCount: -1, ratingSum: -Number(existing.rating ?? 0) } },
        );
        return ok({ deleted: true });
      }

      // ── comments (book discussions) ──────────────────────────────────────
      case 'comments.create': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const body = String(p.body ?? '').trim().slice(0, 2000);
        if (!body) return fail('Comment text is empty');
        const d = await dbFor('reviews');
        const now = new Date();
        const doc = {
          bookId: p.bookId as string,
          userId: uid,
          userName: String(p.displayName ?? 'Reader').slice(0, 80),
          body,
          createdAt: now,
        };
        const inserted = await d.collection('comments').insertOne({ ...doc });
        return ok({ comment: { id: String(inserted.insertedId), ...doc } });
      }

      case 'comments.list': {
        if (!isHexId(p.bookId)) return fail('A valid bookId is required');
        const limit = Math.min(Number(p.limit ?? 30) || 30, 50);
        const rows = await (await dbFor('reviews')).collection('comments')
          .find({ bookId: p.bookId as string })
          .sort({ createdAt: -1 }).limit(limit).toArray();
        return ok({
          comments: rows.map((c) => ({
            id: String(c._id),
            userId: c.userId,
            userName: c.userName ?? 'Reader',
            body: c.body ?? '',
            createdAt: c.createdAt,
          })),
        });
      }

      // ── moderation: user reports ─────────────────────────────────────────
      case 'moderation.report': {
        const uid = await currentUserId(req);
        if (!uid) return fail('Sign in required', 401);
        const targetType = ['book', 'user', 'comment', 'review', 'post']
          .includes(String(p.targetType)) ? String(p.targetType) : null;
        const reason = String(p.reason ?? '').trim().slice(0, 80);
        if (!targetType || !reason) return fail('targetType and reason are required');
        await (await dbFor('moderation')).collection('reports').insertOne({
          targetType,
          targetId: String(p.targetId ?? '').slice(0, 128),
          reporterId: uid,
          reason,
          details: String(p.details ?? '').slice(0, 1000),
          status: 'open',
          createdAt: new Date(),
        });
        return ok({ reported: true });
      }

      default:
        return fail(`Unknown action: ${action}`, 404);
    }
  } catch (error) {
    console.error(`action ${action} failed:`, error);
    return fail(error instanceof Error ? error.message : 'Server error', 500);
  }
});
