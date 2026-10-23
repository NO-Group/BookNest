# BookNest for iPhone & iPad

| | |
|---|---|
| Bundle id | **`com.n-o-group.booknest`**: Apple forbids `_` in bundle ids, so the Android id `com.n_o_group.booknest` cannot be used on iOS. The bundle id can never change after launch. |
| Minimum iOS | 14.0 |
| Build | `.github/workflows/ios-release.yml` (macOS runner) → GitHub Release **`ios-<version>-<run>`** with `BookNest.ipa` |
| Distribution | Direct download from the BookNest website (no App Store) |
| Payments | Paystack, the same as Android (owner's decision) |

## How people install it (no App Store)
iPhones only run apps that are signed. The published **`BookNest.ipa` is
unsigned**: the person installing it signs it with a sideloading tool
(AltStore, Sideloadly, eSign, TrollStore…).
- With a free Apple ID, sideloaded apps expire after 7 days and must be
  refreshed (the tool does this). You can have up to 3 such apps.
- If you later get an Apple Developer account ($99/year), add the signing
  secrets below and CI also publishes `BookNest-signed.ipa`. That build
  installs on the devices registered in your provisioning profile (ad hoc,
  up to 100 iPhones per year).
- In the EU, Apple allows web distribution only for registered developers
  who meet Apple's conditions.

## What works on iPhone
Everything in the app: library, reader, writing studio, feed, clubs, chats
(including end-to-end sealed DMs, photos, videos, voice notes, the universal
document viewer), calls, Paystack, profile and cover photos, the text chat
backup, the dictionary and dictation.

**Not on iPhone:**
- **Background push notifications.** Apple delivers push only to apps signed
  with a paid developer account (APNs). Sideloaded apps get in-app
  notifications while BookNest is open.
- **Home-screen widgets and app shortcuts** (these are Android-only).
- **Google Drive media backup** until secret `GOOGLE_IOS_CLIENT_ID` exists
  (see docs/CHAT_BACKUP.md).

## Permissions (Info.plist)
- Camera, microphone, photos, save-to-photos and speech recognition, each
  with its own explanation.
- Background audio (calls and voice notes).
- `booknest://` deep links.
- `ITSAppUsesNonExemptEncryption = false`: only standard encryption is used.

## GitHub secrets (all optional)
| Secret | What |
|---|---|
| `GOOGLE_IOS_CLIENT_ID` | iOS OAuth client id (Google Cloud → Credentials → iOS, bundle `com.n-o-group.booknest`). Turns on Drive media backup. |
| `IOS_P12_BASE64` / `IOS_P12_PASSWORD` | Apple signing certificate (.p12, base64) and its password |
| `IOS_PROFILE_BASE64` | Matching provisioning profile for `com.n-o-group.booknest` (base64) |
