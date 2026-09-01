# One-time setup: enable the release-APK build

GitHub forbids app credentials from creating workflow files, so this
file lives outside `.github/workflows/`. Add it through the web UI ONCE
(using your own GitHub login — file uploads via the website are fine):

1. Copy the contents of `android-release.yml` (this folder).
2. On github.com → NO-Group/BookNest → **Add file → Create new file**.
3. Name it exactly: `.github/workflows/android-release.yml`
4. Paste → **Commit changes** (commit to `arena/01a03a7f-booknest` or
   `main`).
5. **Actions tab → Android Release APK → Run workflow** → pick the
   branch → **Run workflow**.
6. After ~10–15 min open the run → **Artifacts** → download
   **BookNest-release-apk** → sideload the APK.

After that the build also runs automatically on every push to `main`
(e.g. when PR #4 merges). Rename the artifact era by editing the
`name:` field if you ever want versioned names.
