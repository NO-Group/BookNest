# BookNest — Your checklist

Only what still needs **you**. Everything else (server deploys, builds,
smoke tests, releases) runs automatically from GitHub Actions. Live reports:
`ops/smoke-report.md`, `ops/analyze-report.md`, `ops/google-setup.md`,
`ops/play-check.md`.

## 1 · Merge the release PR

PR #61 → `BookNest`. The server is already live from the branch; merging
makes the default branch match it, and lets the scheduled jobs (storage
sweeps, health checks) run, because GitHub only runs cron workflows from
the default branch.

## 2 · Google sign-in and Drive backup on Android (one-time, ~5 min)

1. Firebase console → project **booknest-12-33-oct22-2026** → Project
   settings → Your apps → Android `com.n_o_group.booknest` → **Add
   fingerprint**:
   - SHA-1 `5F:64:B4:39:E7:F5:9C:78:0C:CA:16:28:5A:D6:F8:7E:57:F9:51:EB`
   - SHA-256 `67:E0:00:83:FB:28:0F:2A:30:77:9D:D0:A3:14:CE:74:44:B7:6F:0D:02:66:E6:EC:08:B7:39:45:25:A8:B2:93`
2. Download the new `google-services.json` and replace
   `android/app/google-services.json`, or send it to the agent.
3. Google Cloud console (same project) → APIs & Services → enable **Google
   Drive API** → OAuth consent screen: add the scope
   `.../auth/drive.appdata`.

`ops/google-setup.md` turns ✅ once this is done.

## 3 · Optional GitHub secrets (NO-Group/BookNest → Settings → Secrets)

| Secret | What it unlocks |
|---|---|
| `GOOGLE_IOS_CLIENT_ID` | Google sign-in / Drive backup on iPhone |
| `GOOGLE_DESKTOP_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_SECRET` | Google sign-in / Drive backup on PC |
| `KEYSTORE_BASE64`, `KEYSTORE_PROPERTIES_BASE64` | Move the Android signing key out of the repo (only if you rotate it; the committed key is in use today) |

## 4 · Google Play

Store listing and forms: `docs/STORE_LISTING.md`, `docs/PLAY_CONSOLE_FORMS.md`.
Privacy policy URL:
https://github.com/NO-Group/BookNest/blob/BookNest/docs/legal/PRIVACY.md
Upload `booknest-play.aab` from the latest `app-…` release.

## 5 · Schools: getting started with CBT

1. Create the school → **Classes** (optional, for class-only exams).
2. **CBT & exams → Question bank** → write questions, or paste a sheet:
   `subject, topic, year, question, A, B, C, D, answer, explanation, marks`.
3. **Set exam** → pick a start time, duration and window → Publish.
   Questions unlock at the start time. Leaving the exam submits it.
4. **⋮ → Results & marking** → mark theory answers → release results.
