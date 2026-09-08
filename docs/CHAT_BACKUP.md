# Chat Storage & Backup — the BookNest WhatsApp Recipe

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
