# Chat Storage & Backup

> **Updated in 2.38.0.** Text and media are now backed up to different places.

## The model (2.38+)

```
┌──────────────────────────┐
│  On the phone (always)   │  Every conversation = its own encrypted file
│  chat_vault/*.bnchat     │  (AES-256-GCM, key in the device keystore)
└──────┬────────────┬──────┘
       │ TEXT       │ MEDIA (photos, videos, voice notes, files)
       ▼            ▼
┌──────────────┐  ┌───────────────────────────────────────────┐
│ BookNest     │  │ The reader's OWN Google Drive (hidden app │
│ MongoDB      │  │ folder, their storage). Incremental: an   │
│ chat_backups │  │ index file lists what is already there.   │
│ 1 doc/reader │  └───────────────────────────────────────────┘
│ sealed blob  │
└──────────────┘
```

- **Text → MongoDB.** The app takes the text history (media keep only their
  link), gzips it, seals it with the reader's passphrase (PBKDF2-HMAC-SHA256
  120k → AES-256-GCM) and uploads it (`backup.put`). BookNest stores
  ciphertext only, one document per reader in `chats.chat_backups`, replaced
  each time. Cap: 3 MB per reader (text is ~50–300 KB). Backups stop growing
  if the chats database passes 350 MB. Restore works on any phone or PC
  (`backup.get`) with the passphrase. The sealed backup also carries this
  phone's end-to-end identity key, so a restored phone can still open sealed
  messages from the last 30 days.
- **Media → the reader's Google Drive.** Settings → Chat backup → "Back up
  media to my Google account" (+ "Include videos"). Uploads only new files,
  streamed from disk (resumable uploads, up to 200 MB per file).
- **Cloudinary keeps chat media for 30 days only.** The daily workflow
  `chat-media-sweep.yml` deletes `booknest/chat/` and `booknest/files/`
  assets older than 30 days (never avatars, covers or book images). Needs
  GitHub secrets `CLOUDINARY_API_KEY` + `CLOUDINARY_API_SECRET`. Report:
  `ops/chat-media-sweep.md`.
- **Older media comes back from Drive.** When a chat photo, video, voice note
  or file is gone from Cloudinary, the app fetches the reader's Drive copy
  silently (bubbles and the viewer).
- **Server messages** are still purged after 30 days (unchanged).
- Schedules (daily/weekly/monthly) run quietly when the chat list opens:
  text to BookNest (only with the passphrase already on the device), and new
  media to Drive (only if switched on and Google is already connected).
- Account deletion removes the sealed text backup too.

## Platforms

| | Text backup (BookNest) | Media backup (Google Drive) |
|---|---|---|
| Android | ✅ | ✅ |
| iPhone | ✅ | ✅ once secret `GOOGLE_IOS_CLIENT_ID` exists |
| PC | ✅ | — (no Google sign-in on desktop) |

## Google console (media backup)

1. Google Cloud Console → enable **Google Drive API**.
2. OAuth consent screen → scope `https://www.googleapis.com/auth/drive.appdata`.
3. Credentials → OAuth client ID → **Android**: package `com.n_o_group.booknest`
   plus the SHA-1 of the signing key.
4. iPhone: OAuth client ID → **iOS**: bundle id `com.n-o-group.booknest` →
   copy the client id into GitHub secret **`GOOGLE_IOS_CLIENT_ID`**.

## Files

- `lib/services/chat_backup_service.dart` — sealed text backup (server), restore.
- `lib/services/media_backup_service.dart` — Drive client, media backup, recovery.
- `lib/services/dm_crypto.dart` — identity keys (restored keys kept as "previous").
- `lib/presentation/screens/settings/chat_backup_screen.dart` — the screen.
- Server: `backup.status / put / get / delete` in `supabase/functions/booknest-api/index.ts`.
- `tools/ops/chat_media_sweep.py`, `.github/workflows/chat-media-sweep.yml`.

---

## Before 2.38 (for reference)


From v2.6.0+18, messaging uses the WhatsApp storage model end to end.
This is the architecture, the reader-facing behavior, and the one-time
Google console setup only you can do.

## The model

```
┌──────────────────────────┐
│  On the phone (always)   │  Every conversation = its own encrypted file
│  chat_vault/*.bnchat     │  AES-256-GCM · key born on the device, kept in
│  (never leaves unsealed) │  Android Keystore (flutter_secure_storage)
└────────────┬─────────────┘
             │ "Back up now" / daily · weekly · monthly
             ▼
┌──────────────────────────┐
│  Google Drive app folder │  booknest-chat-backup.bnbk
│  (hidden, reader's own   │  Sealed with the reader's PASSPHRASE
│  Google account)         │  PBKDF2-HMAC-SHA256 (120k) → AES-256-GCM
└──────────────────────────┘  Nobody without the passphrase can open it —
                              including BookNest.

┌──────────────────────────┐
│  BookNest servers        │  Messages live ONLY for the 30-day sync
│  (tiny now)              │  window, then they are purged for good.
│                          │  Each chat keeps a one-line last-message
│                          │  preview so the chat list stays alive.
└──────────────────────────┘
```

## What this saves you

Message documents were the bulk of MongoDB storage and they grew
forever. Now the server deletes them automatically at 30 days (sweep
runs hourly, throttled, driven by `_id` time — no extra index, no cron
needed). At WhatsApp-scale this turns a database that grows without
bound into a rolling 30-day window. Conversations (the roster) stay —
they are one small doc per chat with a preview line.

## Reader-facing behavior (exactly WhatsApp's flow)

- **Chats open instantly** — the local vault renders history before the
  network answers.
- **Settings → Chat backup** — WhatsApp's screen: last backup time +
  size, "Back up now", Daily/Weekly/Monthly/Never, restore, delete
  backup.
- **First backup asks for a passphrase** — created once, cached in
  secure storage on the device. Losing the passphrase = losing the
  backup (same as WhatsApp's end-to-end encrypted backups — the copy on
  Drive is mathematically useless without it).
- **New phone / reinstall** — chats list shows a banner "Restore your
  chats?" when a backup exists in the Google account; passphrase →
  history returns. "Restore from a backup file" works everywhere.
- **Non-Android** — the same encrypted `.bnbk` file is handed over via
  the share sheet (reader keeps it in iCloud/Drive/Files) and imported
  through the file picker. No fake success anywhere: if Google sign-in
  is not configured, the screen says exactly that.
- **Scheduled backups** run silently on the Chats screen when due — but
  never without the cached passphrase (no silent prompts).
- **Account deletion** wipes the local vault and passphrase cache too.

## What only you can do (Google console, dashboard clicks)

Google Drive backups use `google_sign_in` + the Drive `appdata` scope.
For release builds to sign in:

1. **Google Cloud Console** → APIs & Services → enable **Google Drive API**.
2. **OAuth consent screen** — External, add the app name, support email,
   and the scope `https://www.googleapis.com/auth/drive.appdata`.
3. **Credentials → Create OAuth client ID → Android** —
   package name `com.n_o_group.booknest`, plus the **SHA-1 and SHA-256**
   of your release keystore (the CI keystore's fingerprints —
   `keytool -list -v -keystore <your.jks>`).
4. That's all — no API key ships in the app; the client ID is resolved
   by package + signature on Android.

Until this exists, the app stays honest: the backup screen reports that
Google sign-in isn't available and offers the encrypted-file export
path, which needs nothing.

## Files

- `lib/services/chat_store.dart` — the encrypted vault.
- `lib/services/chat_backup_service.dart` — KDF, envelopes, Drive sync,
  scheduling.
- `lib/presentation/screens/settings/chat_backup_screen.dart` — the UI.
- Edge: `sweepOldMessages()` in
  `supabase/functions/booknest-api/index.ts` (30-day retention).
