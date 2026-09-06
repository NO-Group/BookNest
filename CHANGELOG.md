# Changelog

## 2.2.0+14 — 2026-09-06

- **Blue ticks are real now.** The double tick turns cyan only when
  the other side has actually read your message — messages you send
  show a single grey tick until then, and a clock while sending.
  Chats mark everything read while they are open, live.
- **The message toolkit** — long-press any message:
  - React with the BookNest emote set (tap again to un-react)
  - Double-tap a message for an instant heart with a burst
  - Forward to any DM or group chat, marked "Forwarded"
  - Message info: sent time, read status, read-by names, reactions
  - Delete for me, or Delete for everyone (tombstone for the chat)
- **BookNest Emotes + our own keyboard.** 48 hand-drawn emotes in the
  BookNest visual language — 36 static and 12 that animate right in
  the chat (bouncing heart, heartbeat, spinning star, glowing moon,
  flying quill, tears, dreams…). The new in-app keyboard (Snapchat
  style) slides up over the system keyboard: Emotes / Animated /
  Recent tabs, tap once to send. Emotes travel as their own message
  type and play live on both sides.
- Backend delta shipped: reactions, deletes, read receipts, forwarded
  and emote messages, and the club-room list (chats.list) across
  dm.* and chat.* actions.

## 2.1.0+13 — 2026-09-06

- **Every piece of media now opens inside BookNest — never in another
  app.** Tap any photo, PDF, audio clip or document in a chat and it
  opens in the new in-app media viewer:
  - Photos: pinch-zoom, double-tap magnify, and swipe through every
    photo in the conversation as one album
  - PDFs: real pages rendered in-app with pinch-zoom and a page counter
  - Audio: a full player — play/pause, seek, and playback speed
  - Text documents: readable monospace preview
  - Everything else: a clean document card with type, size and state
    — downloaded and stored inside BookNest
- **The camera is now BookNest's own.** Chats shoot with the in-app
  viewfinder (flash, lens zoom, front/back flip) and land straight in
  the studio with the designed filter and lens presets. The phone's
  camera app is no longer used anywhere.
- **The BookNest file picker.** A designed, in-app picker replaces the
  raw system sheet: recent files front and center, on-device Downloads
  & Documents browsing where Android allows it, and a clearly labelled
  Android browser fallback only where the OS demands it. Everything is
  previewed before it is attached, and picked files are remembered.
- File messages now carry their real name and size end to end
  (edge function updated: `chat.send` and `dm.send`).

## 2.0.0+12 — 2026-09-06

- **The Manuscript Studio is now a true word processor — Google
  Docs–grade, zero markdown.** Select text, press Bold: it's bold. No
  more `**`, `#`, `-` or `<>` anywhere in your books.
  - Styles dropdown (title, headings, quote…), font family and size
  - Bold, italic, underline, strikethrough, sub/superscript, small
  - Text color and highlight color pickers, inline code
  - Left/center/right/justify alignment and line height
  - Bulleted, numbered and check lists, indent, code blocks
  - Links, clear formatting, undo & redo, find & replace
  - Insert pictures and dividers directly into the page
- Chapters are stored as rich documents; the Reader renders them
  beautifully in both themes with your text-size and line-spacing
  choices respected. Legacy chapters still read perfectly and stay
  editable — they open as plain text ready to be styled.
- The standalone chapter editor (add/edit a chapter on an existing
  book) got the same word processor.

## 1.9.0+11 — 2026-09-05

- **The Manuscript Studio** — writing a book is now a word-processor
  experience: a details view (title, pen name, description, all 22
  genres, Cloudinary cover art AND a wide banner picture), and a write
  view with real chapters (add/remove), a full formatting toolbar,
  undo & redo, live word count and reading time. Publishing uploads
  every chapter in order and can resume if the network drops.
- **Book profiles are fully real**: the actual cover art and banner,
  the real average rating and ratings count, and genuine community
  reviews from the data store — no more stand-in numbers or seeded
  reviews. Posting a review refreshes instantly.
- **Feed**: long posts collapse behind "Read more", and any link in a
  post gets a live preview card (picture, headline, source) below it.
- **Chat**: paperclip attachments for any file format (up to 25 MB,
  stored in Cloudinary), a camera button with a built-in editor —
  seven filters plus brightness and contrast — and tapping a person's
  name opens their profile.
- **Discover** cards now show each group's real cover picture.
- **Every club/community/organization/school is born complete**: its
  own announcement forum (owners post; members read; a pinned welcome
  waits on arrival) and its own members-only group chat.
- The create-book button sits above the navigation bar where it
  belongs.

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
