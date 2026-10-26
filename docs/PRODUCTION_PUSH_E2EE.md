# v2.8 — Production Push (FCM), Expanded Moderator Powers, E2EE

## 1. FCM — the only dashboard steps in this document (no terminal)

The app ships FCM-ready: it builds green today and activates the moment
you complete these clicks.

> Updated in 2.36.0 — push is wired through GitHub secrets, nothing is
> uploaded to the repo (it is public).

**A. Firebase project + Android app**
1. console.firebase.google.com → Add project → name it BookNest.
2. Project settings → **Your apps → Android** → package name
   **`com.n_o_group.booknest`** (the app's applicationId — copy it exactly).
3. Download **`google-services.json`** → GitHub → Settings → Secrets →
   Actions → secret **`GOOGLE_SERVICES_JSON`** = the whole file.
   The Android build writes it into `android/app/` only when it contains
   the `com.n_o_group.booknest` app; `ops/play-check.md` → "Push" shows
   whether it was built in.

**B. Service account (for our server to send)**
4. Project settings → Service accounts → **Generate new private key**.
5. GitHub secret **`FIREBASE_SERVICE_ACCOUNT`** = the whole JSON file.
   The Supabase deploy copies it (plus the project id read from it) into
   the server secrets, signs in to Google with it and does a test send;
   the result lands in `ops/push-setup.md` (no secrets in it). If it says
   FCM refused the key, enable **Firebase Cloud Messaging API** in Google
   Cloud for the project.

**How it behaves.** Messages are data-only, high priority. With BookNest
closed or in the background, Android shows one banner per conversation
(channel "Messages"); tapping it opens that chat. While BookNest is on
screen no banner is shown. Sign-out and account deletion remove this
phone's token. The production smoke test checks `push.status`.

**iOS later:** add the iOS app in Firebase, drop
`GoogleService-Info.plist` into `ios/Runner/`, enable Push + upload the
APNs key — say the word and I'll wire the iOS side.

## 2. The overall moderator — the full arsenal (all server-enforced)

For **n.ogroup@yahoo.com** only (the edge checks the signed-in email):

| Power | Action | Notes |
|---|---|---|
| Reports queue | view / resolve / dismiss | as before |
| Delete content | posts, messages, reviews, comments (+cascades) | as before |
| **Suspend readers** | `admin.ban` / `admin.unban` | Suspended readers cannot post, message, review or publish — reading stays open |
| **Adjust gems** | `admin.gems` (+/−) | full ledger entry, floored at 0 |
| **Delete any book** | `admin.deleteBook` | book + all chapters |
| **Feature / unfeature** | `admin.feature` | spotlight flag on the book (ready for Discover) |
| **Pulse dashboard** | `admin.stats` | readers, books, posts, messages/24h, open reports, active suspensions |
| **Audit log** | every action recorded | viewable in the console's Pulse tab |

Console = 3 tabs: **Reports** (per-kind actions: delete, feature,
suspend, handle, dismiss), **Readers** (search by @username → suspend /
reinstate / adjust gems), **Pulse** (live counts + your action log).

## 3. E2EE — yes, it was possible at zero cost, so it's in

- Every device generates a **P-256 identity keypair** on first use; the
  private key lives in the phone's secure storage and **never leaves it**.
- Each 1:1 **text** message is sealed with a **fresh one-time key**
  (ECDH + HKDF-SHA256 → AES-256-GCM). The server stores only the sealed
  envelope + the one-time public key — it cannot read the message, and
  because one-time keys are destroyed after use, a stolen identity key
  cannot unseal **old** messages.
- Chat list previews stay human without exposure: the sender's app sends
  a "🔒 Encrypted message" preview token alongside the sealed text.
- **Honest scope**: 1:1 text. Club chats and media attachments are not
  sealed (group sealing is a fundamentally heavier protocol); the Privacy
  screen says exactly this.
- Cost: zero — pure Dart (pointycastle, already in the app), keys in the
  existing key directory (`keys.publish` / `keys.fetch`), no third party.

## 4. Re-paste + deploy checklist (dashboard clicks)

1. Edge function: paste `supabase/functions/booknest-api/index.ts`
   (adds bans, gems, feature, stats, audit, push register, key
   directory, FCM sender, preview passthrough).
2. Edge secrets: `FIREBASE_SERVICE_ACCOUNT`, `FIREBASE_PROJECT_ID`.
3. Repo: add `android/app/google-services.json`.
4. Re-run CI → new APK → ship.
