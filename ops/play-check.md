# Google Play readiness — 2026-10-23 17:45 UTC

Build tools: `37.0.0` · APK 117M · AAB 97M

## App

| item | value | Play |
|---|---|---|
| package | `com.n_o_group.booknest` | |
| version | 2.39.1 (73) | |
| minSdk | 24 | |
| targetSdk | 36 | ✅ needs ≥ 35 |
| push (Firebase config) | built in | ✅ |

## Permissions

- `android.permission.ACCESS_NETWORK_STATE`
- `android.permission.BLUETOOTH`
- `android.permission.CAMERA` · Data safety form
- `android.permission.FOREGROUND_SERVICE`
- `android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING` ⚠️ declare this foreground-service type in Play Console (App content)
- `android.permission.INTERNET`
- `android.permission.MODIFY_AUDIO_SETTINGS`
- `android.permission.POST_NOTIFICATIONS`
- `android.permission.READ_EXTERNAL_STORAGE`
- `android.permission.RECEIVE_BOOT_COMPLETED`
- `android.permission.RECORD_AUDIO` · Data safety form
- `android.permission.VIBRATE`
- `android.permission.WAKE_LOCK`
- `android.permission.WRITE_EXTERNAL_STORAGE`
- `com.google.android.c2dm.permission.RECEIVE`
- `com.n_o_group.booknest.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`

## 16 KB page size (native libraries)

✅ All 14 64-bit libraries are 16 KB aligned.

✅ APK zip alignment OK for 16 KB pages.

## App Bundle

- `app-release.aab` contains 21 native library entries; upload it in Play Console → Test and release.

### Play bundle permissions

- `android.permission.ACCESS_NETWORK_STATE`
- `android.permission.BLUETOOTH`
- `android.permission.CAMERA`
- `android.permission.FOREGROUND_SERVICE`
- `android.permission.INTERNET`
- `android.permission.MODIFY_AUDIO_SETTINGS`
- `android.permission.POST_NOTIFICATIONS`
- `android.permission.READ_EXTERNAL_STORAGE`
- `android.permission.RECEIVE_BOOT_COMPLETED`
- `android.permission.RECORD_AUDIO`
- `android.permission.VIBRATE`
- `android.permission.WAKE_LOCK`
- `android.permission.WRITE_EXTERNAL_STORAGE`
- `com.google.android.c2dm.permission.RECEIVE`
- `com.n_o_group.booknest.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`

✅ No foreground-service type in the Play bundle — no Play Console foreground-service declaration needed.

## Push

- push: google-services.json for `com.n_o_group.booknest` (project `booknest-12-33-oct22-2026`) ✅
