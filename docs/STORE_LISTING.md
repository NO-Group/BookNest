# BookNest — App Store Listing Package (v2.5.0+17)

Everything below is ready to paste into the Google Play Console and App
Store Connect. Copy is final — no placeholders.

---

## Identity (both stores)

| Field | Value |
|---|---|
| App name | BookNest |
| Bundle / package | `com.n_o_group.booknest` |
| Version | 2.5.0 (+17) |
| Subtitle (iOS, ≤30 chars) | Write. Read. Belong. |
| Tagline | The Digital Library Ecosystem |
| Developer | N.O Group |

## Category

- **Play:** Books & Reference
- **iOS:** Books · Reference (secondary)

## Short description (Play, 80 chars)

> Write books, build clubs, and read your next obsession — all in one nest.

## Promotional text (iOS, ≤170 chars)

> Write real books with a true word processor, publish with a Book ID that
> can't be stolen, remix your favourites, and talk books in clubs built for
> readers.

## Full description (Play, ≤4000)

> **BookNest is the reading-and-writing home bookworms build together.**
>
> ✍️ **A true manuscript studio** — bold, headings, colours, pictures,
> dividers, find & replace: everything a real word processor needs, and
> what you see is exactly what readers get. Save drafts, edit published
> books any time, and switch between chapters, parts, acts, episodes or
> volumes.
>
> 📚 **Book IDs & series** — every book carries a unique, unstealable Book
> ID. Publish again with the same ID and title and BookNest automatically
> makes it the next part of your series. Readers see Part 2, Sequel and
> Remix marks right on the book page.
>
> ♻️ **Remix & sequel, done right** — start from any published book with
> every chapter carried into your draft. The remix or sequel mark and the
> original author's credit travel with the work, always.
>
> 🌙 **A reader worth staying up for** — four reading papers (Night,
> Paper, Sepia, Ink), text size and spacing that remember themselves,
> progress that follows you across devices, and a finish bonus in gems.
>
> 💬 **Clubs & chats that feel alive** — photos, video with sound, voice
> messages, files, swipe-to-reply, reactions that land instantly, and
> BookNest's own animated emotes drawn stroke by stroke. Triple-tap any
> message to translate it. Videos play inside the app, in our own player.
>
> 📰 **A feed for book people** — quotes, news, polls, events and
> articles, with real view counts, comments and one-tap reshares.
>
> 📖 **Word Nest** — a full dictionary inside the app: meanings, examples,
> word of the day and trending lookups. Works offline.
>
> 💎 **Gems that mean something** — earn them daily, for publishing and
> for finishing books. Spend 20 to boost your book to the top of Discover
> for three days. The full ledger is always visible in your wallet.
>
> 📸 **A camera of our own** — photo and video modes, zoom, lens flip and
> twelve designed filters, all inside BookNest.
>
> 🛡️ **Safety built in** — report any post, message, book or profile;
> block readers for real; delete your whole account (and every trace of
> it) from Settings any time.
>
> 22 genres from Romance to STEM. Onboarding in your language. BookNest —
> made with 💙 for readers everywhere.

## Keywords (iOS, ≤100 chars)

`books,reading,writing,novels,stories,book club,library,reader,writer,ebooks,book community`

(98 chars.)

## Screenshot shot-list (6–8, in this order)

1. **Feed** — a post card with view/comment/reshare counts and the BookNest
   loader visible in the previous frame.
2. **Manuscript studio** — mid-sentence with the toolbar visible (Proof the
   "true word processor" claim).
3. **Book page** — a book with the *Part 2* badge, Boost button and
   remix/sequel buttons.
4. **Reader** — Sepia theme, comfortable type, progress hairline.
5. **Club chat** — an emote bubble animating, a swipe-to-reply quote, a
   video bubble with the scrubber.
6. **Word Nest** — word of the day.
7. **Wallet** — gems balance, claim button, ledger.
8. **Camera** — filter strip with the video mode switch.

Feature graphic text (Play, 1024×500): the BookNest logo + "Write. Read.
Belong."

## Content rating answers (Play)

- UGC: **yes** (posts, chat, books, reviews).
- Sharing/location of others: **no**. Personal info sharing: **no**.
- In-app purchases: **no** (gems are earned, never sold).
- Expected outcome: **Teen / PEGI 12+** (chat + UGC). Answer the
  questionnaire honestly; the report/block/moderation presence is the
  mitigating answer to every UGC severity question.

## Data safety (Play)

| Question | Answer |
|---|---|
| Data collected | Account info (username, display name, phone for recovery, country, gender, age, languages); user content (books, posts, messages, photos, voice, video); activity (views, likes, reading progress, streaks) |
| Shared with third parties | No — media hosts (Cloudinary/Cloudflare) act as storage processors only |
| Encrypted in transit | Yes |
| Deletion mechanism | **In-app**: Settings → Delete my account (full cascade) + per-content deletes |
| Data-safety form purpose | App functionality, account management, personalization |

## Apple privacy "nutrition labels"

- **Data linked to you:** contact info (phone), user content, identifiers.
- **Data not linked:** usage/activity aggregates (views, trending).
- **Tracking:** none, across all companies.

## Console requirements you must fill in as the owner

- **Support email** (monitored inbox) and, for Play, a contact website or
  the About page URL.
- **Privacy policy URL**: host the in-app "Privacy & safety" text at a
  public URL (a GitHub Page is enough) — Play requires an absolute URL,
  Apple accepts either.
- **Account deletion URL** (Play, new requirement): point it at the same
  site with a short page explaining Settings → Delete my account — or use
  the web link to your support email requesting deletion.
- **Screenshots**: produce from a device/emulator at 1080×1920+ (Play) and
  6.7" 1290×2796 (iOS), per the shot-list above.
- **Upload the signed AAB/APK** from the CI artifact `BookNest-release-apk`
  (Play also accepts the APK while testing; production prefers AAB — ask
  CI to add `flutter build appbundle` when you are ready).
