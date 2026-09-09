# v2.8 — Production Push (FCM), Expanded Moderator Powers, E2EE

## 1. FCM — the only dashboard steps in this document (no terminal)

The app ships FCM-ready: it builds green today and activates the moment
you complete these clicks.

**A. Firebase project**
1. console.firebase.google.com → Add project → name it BookNest.
2. Project settings → **Your apps → Android** → register with package
   name **`com.nogroup.booknest`** (the app's real applicationId — copy
   it exactly).
3. Download **`google-services.json`** and add it to the repo at
   `android/app/google-services.json` (GitHub → Add file → upload; put
   it in `android/app/`). That single file flips the build to push mode —
   the Gradle wiring is already conditional on it.

**B. Service account (for our server to send)**
4. Firebase → Project settings → Service accounts → **Generate new
   private key** → you get a JSON file.
5. Supabase dashboard → Edge Functions → booknest-api → **Secrets** → add:
   - `FIREBASE_SERVICE_ACCOUNT` = the ENTIRE JSON file contents (paste it
     as one line; the function parses it).
   - `FIREBASE_PROJECT_ID` = the Firebase project id (top of Project
     settings, looks like `booknest-xxxxx`).

That's all. Tokens register themselves on app start; DMs and club
messages push automatically; invalid tokens clean themselves up.

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
