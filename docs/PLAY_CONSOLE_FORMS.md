# Play Console: App content answers for BookNest

These answers come from the app's code as of 2.35.0. Go to
Play Console → *Policy and programs → App content*. Answer exactly as below,
and update this file if a feature changes what the app collects.

- Privacy policy URL: `https://github.com/NO-Group/BookNest/blob/BookNest/docs/legal/PRIVACY.md`
- Account deletion URL: `https://github.com/NO-Group/BookNest/blob/BookNest/docs/legal/ACCOUNT_DELETION.md`

---

## 1. Foreground service permissions: nothing to declare

Since 2.35.0, the **Google Play build (.aab) has no foreground service.**
It is built with `BN_PLAY=true`, which removes the background-link service
and the `FOREGROUND_SERVICE_REMOTE_MESSAGING` permission. The
direct-download APK keeps it.

- The CI readiness report (`ops/play-check.md`, section *Play bundle
  permissions*) confirms this from the bundle's own manifest:
  "✅ No foreground-service type in the Play bundle".
- Play users get message alerts while the app is open or in recents
  (in-app watcher). They will get alerts after the app is closed once
  Firebase push is configured.
- If Play Console still shows the foreground-service declaration, upload
  the new .aab first. The form disappears when no active release uses the
  permission.

---

## 2. Data safety

**Overview questions**

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (HTTPS/TLS everywhere; calls use DTLS-SRTP) |
| Do you provide a way for users to request that their data is deleted? | **Yes**: in the app (Settings → Delete my account) and on the web (account deletion URL above) |

**Sharing:** answer **No** for every type. Supabase, MongoDB Atlas,
Cloudinary, Cloudflare, Paystack and (later) Firebase process data *on
BookNest's behalf* (service providers). Google does not count that as
sharing. There are no ads, no analytics SDKs and no data sales.

**Data types to tick** (for each: Collected = yes, Shared = no, Processed
ephemerally = no)

| Category → type | Required or optional | Purposes to tick |
|---|---|---|
| Personal info → **Name** (username, display name) | Required | App functionality, Account management |
| Personal info → **Email address** | Optional (if used to sign in) | Account management, App functionality |
| Personal info → **Phone number** | Optional (if used to sign in) | Account management, App functionality |
| Personal info → **User IDs** | Required | App functionality, Account management |
| Personal info → **Other info** (country, gender, age range, languages) | Optional | App functionality, Personalization |
| Financial info → **Purchase history** (product, amount, Paystack reference) | Optional (only buyers) | App functionality, Account management |
| Messages → **Other in-app messages** (group chats; 1:1 chats are sealed end-to-end, but tick it anyway since group chats are not) | Optional | App functionality |
| Photos and videos → **Photos** (profile photo, photos in posts and chats) | Optional | App functionality |
| Photos and videos → **Videos** (videos sent in chats) | Optional | App functionality |
| Audio → **Voice or sound recordings** (voice notes) | Optional | App functionality |
| Files and docs → **Files and docs** (files sent in chats) | Optional | App functionality |
| App activity → **App interactions** (books opened, likes, bookmarks, reading progress, streaks) | Required | App functionality, Personalization |
| App activity → **Other user-generated content** (books, chapters, posts, comments, reviews) | Optional | App functionality |
| Device or other IDs → **Device or other IDs** (notification token; tick once Firebase push is live) | Optional | App functionality |

**Do not tick:**
- Location (no location permission; country is typed by the user, see Other info).
- Contacts, Calendar, Health, Web browsing.
- Crash logs or Diagnostics (no crash or analytics SDK is included).
- Audio for calls: voice and video calls are encrypted end to end between
  the two phones. When the Cloudflare relay is used, it forwards packets
  it cannot decrypt, and nothing is recorded.

---

## 3. Other App content items

| Item | Answer |
|---|---|
| Ads | **No**, the app contains no ads |
| App access | Give reviewers a test account (email + password) that is already signed up |
| Content rating | Questionnaire category *Social / Communication*. Answer **Yes** to "users can interact or exchange content" and to "shares user-generated content"; **No** to violence, sexual content, gambling and drugs |
| Target audience | **13+** (not designed for children). Do not opt into the Families program |
| News app | No |
| Health apps | No |
| Financial features | None of the listed financial products (Paystack is checkout for gems and plans only) |
| Government app | No |
| Data safety | Section 2 above |
| Account deletion | URL above; in-app path: Settings → Delete my account |

### Camera and microphone

These need no separate declaration. They are covered by Data safety
(photos, videos, voice recordings), and the app asks only when you take a
photo, record a voice note or join a call.
