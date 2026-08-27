# BookNest backend data reminder

Use this as a planning prompt when building the BookNest backend:

> I am building BookNest, a Flutter social reading application. Design a production-ready backend data architecture that uses Supabase/Postgres for social and relational data, while keeping media on dedicated media infrastructure such as Cloudinary.
>
> Supabase must be the source of truth for: profiles, books and metadata, book views and reading progress, likes/reactions, bookmarks, ratings, written reviews, comments/replies, follows, notifications, direct-message metadata, share events, moderation records, and aggregate counters. Cloudinary (or equivalent) must hold uploaded book covers, avatars, images, video, and other media files; Supabase should store only secure media URLs, public IDs, dimensions, content type, and ownership metadata.
>
> Create a normalized Postgres schema and SQL migrations for the following core tables: `profiles`, `club_books`, `book_chapters`, `book_likes`, `book_bookmarks`, `book_views`, `book_reviews`, `book_review_votes`, `book_comments`, `book_shares`, `conversations`, `conversation_members`, `messages`, and `notifications`. Include useful indexes, created/updated timestamps, foreign keys, unique constraints that prevent duplicate user actions, soft-delete/moderation fields where appropriate, and database functions/triggers for safe aggregate counts and rating averages.
>
> For a book share, a user must select a BookNest contact, create or use a direct conversation, and send a message containing a structured book reference (`book_id`) rather than copying plain text. The recipient must be able to open the shared book detail page from that message.
>
> Write Supabase Row Level Security policies for every table. Users may only create/update/delete their own likes, bookmarks, views, reviews, comments, shares, and messages; they may read approved/public books and eligible reviews/comments; private conversations are visible only to their members. Prevent users from spoofing user IDs, forging aggregate counts, or reading other users’ private data.
>
> Explain which actions should use normal client writes, database RPC functions, Edge Functions, Realtime subscriptions, queues/background jobs, and Cloudinary signed uploads. Include Flutter integration examples for optimistic likes/bookmarks, review submission, recording one view per user/session policy, sending a structured shared-book message, pagination, error handling, and rollback. Keep secrets server-side and never put Cloudinary API secrets or Supabase service-role keys in the Flutter client.
