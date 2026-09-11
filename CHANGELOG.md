# Changelog

## 2.16.0+28 — 2026-09-11 · Department chats, events & the community strike

- **Department chat rooms**: every organization department now has its
  own **members-only chat** — join the department, tap the 💬 icon, and
  talk to that team alone. Fully enforced at the edge: no unit membership,
  no messages.
- **Events with RSVPs** (organizations **and** communities): owners and
  deputies schedule happenings — title, details, date & time (or "to be
  announced"). Members respond **Going** or **Interested** with live
  counts, live countdowns ("In 2 d 4h" → "Happening now"), and hosts can
  remove events with their RSVPs.
- **Community channels**: communities get named, members-only topic chat
  rooms (#poetry, #launches, #help…) — created by owners/deputies, open to
  every member from the community page, in the same polished chat.
- **House rules**: a numbered rules panel for communities — owners and
  deputies write them (one per line, up to 12), every member sees them.
- Everything rides on the same hardened chat stack: sub-room membership
  is now enforced across send, read, react, delete and read receipts.

## 2.15.0+27 — 2026-09-11 · The organization impact round

- **Organizations, rebuilt for real structure**:
  - **Departments** — owners and deputies create internal teams
    (Editorial, Outreach, Design…), members join and leave freely, and a
    **lead** can be appointed to each department from the roster. Live
    member counts, join checks, and management (change lead, remove) from
    the organization page.
  - **Verified badge** — the overall moderator can now verify an
    organization; the cyan tick shows on the org page and everywhere it
    appears on Discover.
  - **Organizations spotlight** — a dedicated rail on Discover: every
    organization on BookNest, member counts, verified ticks, one tap in.
- **Reading, your way, one tap away**: a new layout button in the reading
  chrome flips instantly between **scrolling** and **swiping pages** (the
  comfort-sheet switch is still there) — both modes keep your typography,
  progress and page position.
- **Calls everywhere you meet a reader**: voice and video call buttons on
  every **profile page** (next to the menu), alongside the ones already in
  every chat header.
- **Chat watermark, visible**: the book-and-quill watermark now shows
  properly on the **dark theme** and its opacity is raised a touch on both
  themes — quiet, but unmistakably there.

## 2.14.0+26 — 2026-09-11 · The pro reader, calls, brainstorm & the school

- **The Reader, rebuilt to pro standard**: true **paginated mode** —
  chapters flow into real swipeable pages measured against your exact
  type settings (toggle: Scroll ⇄ Pages). A **Book serif** typeface
  option, **page warmth** (candlelight dim), **bookmarks** synced to your
  account with jump-and-remove from the contents sheet, immersive system
  bars when the chrome hides, keep-screen-awake while reading, per-chapter
  **reading-time estimates**, and a page-turn page indicator.
- **Brainstorm** 💡: BookNest's idea boards — float an idea, everyone
  builds on it in true threads (one-level nesting, reply badges, expand/
  collapse, 💡 boosts). Lives on Discover.
- **Schools, levelled up into a real LMS**: **Classes** (create, join,
  teacher + roster counts), **Assignments** (per class, due-date
  countdowns, optional anchor book, done-toggles with live completion
  counts, teacher-only creation), and **Exam countdowns** (scheduled by
  the school, live to-the-minute timers) — alongside the existing reading
  list and top-readers board.
- **Voice & video calls**: call any reader straight from a chat — pure
  peer-to-peer WebRTC (video calls with camera flip/mute, voice calls),
  ringing through BookNest's own realtime channels. No third-party call
  service, no minutes bill. Works on open networks (hotspots, home wifi,
  mobile data).
- **Profile layout setting**: Settings → Profile Layout — switch your
  profile between the **Classic** card flow and the new **Studio** hero
  band (gradient banner with overlapping avatar). Your choice sticks.

## 2.13.0+25 — 2026-09-11 · Threads, kind superpowers, buttery loading

- **Thread comments**: post conversations are now true threads — replies
  nest under their thread root with "View replies" expansion and a
  "replying to" badge, and replying keeps context in the composer. The
  server flattens threads one level deep so nothing ever becomes a maze.
- **Organizations, fully built**: real organization pages — profile with
  mission, join/leave, announcements with pinning, a named member
  directory with roles, deputy assignment, and the members-only chat
  (replaces the old placeholder screen).
- **Schools, fully built**: everything an organization gets plus a
  curated **reading list** (managers add books from the catalogue;
  members tap straight in) and a **Top readers** leaderboard computed on
  the server from real reading activity over 30 days — medals included.
- **Communities, fully built**: the same complete experience for
  community pages (also replaces a placeholder).
- **Clubs — Book of the Month**: owners pick the club read from the
  catalogue; every member sees the cover and a Read-now button. Also
  fixed a long-standing bug where club owners' powers (moderation desk,
  owner badge) could fail to resolve.
- **Ultra-smooth loading**: shimmering skeleton kits that mirror the exact
  geometry of the content they become now greet the feed, library,
  discover shelves, DM list, contact pickers and comment threads — no
  more spinners mid-page, no layout jumps, 60fps sweeps.
- The Page-Flip Runner loader stays **unwired** by request — the component
  ships but nothing uses it yet.

## 2.12.0+24 — 2026-09-11 · The Page-Flip Runner

- **New signature loader asset**: an ice-white runner striding across an
  open isometric book — pages flip on bent arcs underfoot, kinetic
  ocean-blue sparks fire on every footfall, sky-blue speed trails stretch
  with velocity, and `progress` (0–100) accelerates the stride from a jog
  into a lean-into-it sprint.
- Firing `isComplete` interrupts with a finish-line jump: launch, mid-air
  tuck, dissolve into a glowing ocean-blue particle burst.
- Ships three synchronized artifacts: the executable motion prototype
  (tools/page_flip_runner_proto.py), the rendered preview loop
  (docs/assets/page_flip_runner.gif), and the production Flutter
  component (PageFlipLoader) — plus the full Rive authoring spec for the
  native .riv build (docs/PAGE_FLIP_RUNNER_SPEC.md).

## 2.11.0+23 — 2026-09-10 · The background link (no Google, still)

- **Stay connected — with nobody but BookNest**: an optional slim
  foreground service keeps messages arriving even after other apps close
  BookNest or the phone restarts. No Firebase, no OneSignal, no third
  party — the link runs straight to our own servers on a revocable,
  30-day pass that never touches your login session.
- Found in Settings → **Connection → Stay connected (no Google
  services)**, with honest battery wording and a hint for phones
  (Tecno/Infinix/Samsung) that need "Auto-start" allowed.
- While the app is open the app banners messages as before; when it's
  swiped away, the persistent "BookNest is connected" notification takes
  over and carries the news.
- Edge update: `link.pass` / `link.revoke` / `link.names` + pass support
  on the message-queue reads (covered by the usual index.ts re-paste).

## 2.10.0+22 — 2026-09-10 · Notifications without anyone's permission

- **Zero-external notifications**: while BookNest is running — in hand or
  in recents — new direct and club messages surface as native banners via
  a light 30-second sweep of the delivery queue. No Firebase, no
  OneSignal, no third party, nothing to configure, ever.
- Banners carry the sender's name (or the club's), a clean preview, and
  replace per conversation instead of stacking; the conversation you're
  actually looking at never buzzes.
- Club room listings now include each room's last message (edge update —
  covered by the usual index.ts re-paste).
- Sealed messages preview as "🔒 Encrypted message" here too, honestly.

## 2.9.0+21 — 2026-09-09 · Genres the moderator owns

- **Genres are no longer hardcoded**: both taxonomies — the 22 book
  shelves and the club genres — now live on the server, curated by the
  overall moderator from a new **Genres** tab in the moderation console.
- Adding a genre puts it in every picker and shelf on every device;
  removing one retires it from the pickers while books already on the
  shelf keep their label (browsing an old shelf still works).
- Every screen — onboarding, library, book studio, book management,
  club creation — reads the same live lists, with the classic defaults
  as an offline fallback so the app never shows an empty picker.

## 2.8.0+20 — 2026-09-07 · Production: push, power, and sealed words

- **Push notifications are live-ready (FCM)**: direct messages and club
  messages reach your phone when BookNest is closed — sent from our own
  servers with a service account, never with keys inside the app.
- **Your words are sealed**: one-to-one messages are now end-to-end
  encrypted on the sending device — fresh one-time keys per message, so
  not even BookNest can read them, and a stolen key can't unseal the
  past. (Clubs and attachments remain unsealed — stated plainly.)
- **The moderator's arsenal**: suspend/reinstate readers, adjust gems
  with a full ledger entry, delete any book with its chapters, spotlight
  books for Discover, a live pulse dashboard (readers, books, posts,
  messages today, open reports, suspensions), and a complete audit log
  of every moderation action.
- Suspended readers can read but not write — the app tells them plainly.

## 2.7.0+19 — 2026-09-07 · The sweep + the powers

- **Every delete now deletes for real**: deleting your own post (new!)
  removes its comments, likes, views and reshares server-side too — and
  account deletion now catches feed posts correctly. Verified end to end:
  chapters, messages, announcements, reviews, posts, blocks, everything.
- **Link previews work again**: previews are fetched by BookNest's
  servers (websites block direct phone requests), with a clean tappable
  link chip whenever a site offers nothing — never a stuck spinner.
  Views, likes, comments and reshares now sit under every post type.
- **The overall moderator**: n.ogroup@yahoo.com carries the shield — a
  full moderation console (reports queue, content deletion, resolve and
  dismiss), visible only to that account, enforced server-side.
- **Author mode**: Facebook-style profile switch — flip between Reader
  and Author. Author mode brings the writing tools front and centre and
  marks your public profile with the Author badge. Nothing is lost
  switching back and forth.
- **Chat themes**: twelve designed wallpapers (Midnight, Cyan Mist,
  Paper, Sepia, Slate, Forest, Ocean, Plum, Rose, Ink, Meadow + Classic)
  with a dim slider, per-chat or apply-to-all — a palette button in every
  chat.
- **Emotes, redesigned feature by feature**: open filled smiles with a
  tongue peek, the classic :3 cat mouth, curled tongues, rosy cheeks on
  every face, twinkling star eyes, outlined heart eyes.
- About footer shows the real version everywhere.

## 2.6.0+18 — 2026-09-07 · The WhatsApp recipe for messaging

- **Chats now live encrypted on your phone**: every conversation is its
  own AES-256-GCM vault file, keyed on the device in secure storage —
  chats open instantly and your history never depends on our servers.
- **Backup to your Google account**: the whole vault is sealed with your
  own passphrase (without it the backup is unreadable to anyone,
  including BookNest) and stored in a hidden folder in your Google
  Drive. Back up on demand or Daily / Weekly / Monthly.
- **Restore, WhatsApp-style**: reinstall or move phones and the chats
  screen asks "Restore your chats?" — your passphrase brings every
  message back. Everywhere else, the same encrypted backup travels as a
  file you keep.
- **Servers stay tiny**: messages live on BookNest's servers only for a
  30-day sync window, then they're purged for good — each chat keeps
  just a one-line preview. This is the storage recipe WhatsApp uses.
- Account deletion now wipes the local chat vault and backup keys too.

## 2.5.0+17 — 2026-09-07 · Launch readiness

- **Delete your account for real**: Settings now carries the full account
  deletion flow — double-confirmed, server-enforced, and it removes your
  profile, books, drafts, posts, reviews, messages, gems and reading
  history everywhere, then signs you out. Required by the app stores and,
  frankly, just right.
- **Report anything**: a designed report sheet lives on posts, messages,
  books and profiles — ten clear reasons plus free text, delivered
  confidentially to the moderation team.
- **Block readers**: blocking is server-enforced — no more messages, and
  blocked readers' club messages stay hidden. Unblock any time from their
  profile.
- **Terms of Service**: readable, real terms now live in the app, linked
  at sign-up, in Settings and in About.
- **iOS permission strings**: the camera, microphone and photo library now
  introduce themselves properly on iPhones.
- **About, freshened**: legal links and a launch-day footer.

## 2.4.0+16 — 2026-09-07

- **The studio never freezes again**: typing is butter-smooth — word counts
  tick on their own beat instead of redrawing the whole editor per letter.
- **Book IDs**: every book gets a unique, unstealable ID. Publish the same
  ID with the same title and BookNest turns it into the next part of a
  series automatically — with series marks on the book page.
- **Drafts**: save a work-in-progress any time; drafts show on your writer
  dashboard and publish when you are ready. Published books can go back to
  draft too.
- **Edit published books**: open any of your books from the dashboard and
  polish details or units — changes go live when you press Save.
- **Remix and sequel**: start from any published book — every chapter is
  carried into your draft, the remix/sequel mark and original credit
  travel with it, and +10 gems land in your wallet.
- **The camera, upgraded**: photo and video modes (with sound), more
  lenses via flip, the zoom slider, and twelve designed filters — all
  inside BookNest, never the phone's camera app.
- **Videos play in chat**: our own player — tap to play, scrubber, mute,
  fullscreen theater. Record with sound straight from the attachment sheet.
- **Swipe to reply**: drag any bubble toward the center and the reply
  arrow answers; quotes show above the message and above the input.
- **Reactions land instantly** (and roll back honestly if the network
  says no).
- **Emotes, reborn**: every BookNest emote is alive now — soft idle bob,
  blinks, glossy sphere shading, ground shadows. The keyboard animates
  them all.
- **Posts**: view counts, comment threads in a sheet, and one-tap
  reshares — right on the card.
- **Gems are real**: the wallet shows the full earning and spending
  ledger, and 20 gems boost your book to the top of Discover for three
  days.
- **The BookNest loader**: an opening-book spinner now waits on the feed,
  shelves and chats — no more generic spinners.
- **Super-fast screens**: feeds, shelves and inboxes answer from a
  60-second cache that any write refreshes; pull-to-refresh always
  reaches the network.
- **Premium reader**: four reading papers (Night, Paper, Sepia, Ink),
  text size and spacing that remember themselves, and unit words that
  follow the author's own vocabulary.

## 2.3.0+15 — 2026-09-06

- **The keyboard grows up (SwiftKey model).** A toolbar with translator
  and voice typing; four pages — Emotes, Animated, System emojis, and
  Recent. 24 emotes now animate (12 brand-new: Wow!, Big brain,
  Casting stories, Wiggly worm…), 12 fresh custom emotes join the pack
  (72 total), and **system emojis are built in** — a full Unicode
  library (smileys, hearts, animals, food, activities) sendable as
  normal messages.
- **Translator on the keyboard.** Flip the translate toggle, pick a
  language, type — outgoing messages send in that language.
- **Voice typing.** The mic writes your words straight into the
  message box, in your preferred language.
- **Triple-tap any message to translate it** into your preferred
  language — a clean sheet shows the translation with the detected
  original. Double-tap is still the heart.
- **Reader profile in the auth flow.** New readers choose their
  country, gender and every language they speak — each with a fluency
  level (basic → native). The strongest language becomes the preferred
  language automatically, and everything is editable in Settings →
  Language & keyboard.
- **Flags and badges on profile pictures.** Your country flag sits on
  top of the circle and your gender badge below (one up, one down) —
  tap the flag for the country name, tap the picture for the
  full-screen view.
- **Voice messages — recorded, previewed, and R2-ready.** Hold to
  record up to two minutes, preview, rerecord. Sending unlocks the
  moment Cloudflare R2 credentials are connected (voice goes to R2 by
  our media law — never into a database).
- The BookNest keyboard can now be **switched off in Settings**.
- Backend delta: users.profile get/save, translate.text, media.status.

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
