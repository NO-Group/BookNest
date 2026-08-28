# GitHub Actions workflows — one-time setup via the web editor

GitHub blocks assistant-driven pushes of `.github/workflows/*` files, so
these two ready-made workflows live here. To activate them (2 minutes,
browser only):

1. On GitHub open this repo → **Add file → Create new file**.
2. For each file below, type the exact path, paste the contents, commit:

   | Create this path | Copy contents from |
   |---|---|
   | `.github/workflows/flutter-ci.yml` | `flutter-ci.yml` (this folder) |
   | `.github/workflows/deploy-edge.yml` | `deploy-edge.yml` (this folder) |

3. What each does:
   - **flutter-ci.yml** — on every push: installs Flutter, runs `pub get`,
     `analyze`, and the tests. A green ✅ next to a commit = code is healthy.
   - **deploy-edge.yml** — stays asleep until you add a
     `SUPABASE_ACCESS_TOKEN` secret (Supabase → Account → Access Tokens →
     GitHub → Settings → Secrets and variables → Actions). Once present,
     any push that changes `supabase/functions/**` auto-deploys the
     booknest-api function. Without the token it never runs or fails.
