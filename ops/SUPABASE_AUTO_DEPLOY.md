# One-click server deploys (no terminal, ever)

The app talks to a **Supabase Edge Function** (`booknest-api`). Every upgrade
that touches `supabase/functions/booknest-api/index.ts` needs that file
deployed to Supabase — until now that meant copying and pasting it in the
dashboard. This workflow makes it a single button.

## One-time setup (about 3 minutes, dashboard clicks only)

1. **Create the access token**
   Supabase dashboard → click your avatar (bottom-left) → **Account** →
   **Access Tokens** → **Generate new token** → name it `booknest-ci` →
   copy the value (starts `sbp_…`).

2. **Find your project ref**
   Supabase dashboard → your project → ⚙ **Project Settings** → **General** →
   **Reference ID** (a short string like `abcdefghijklmnop`).

3. **Add both as GitHub secrets**
   GitHub repo → **Settings** → **Secrets and variables** → **Actions** →
   **New repository secret**, twice:
   - Name: `SUPABASE_ACCESS_TOKEN` · Secret: the `sbp_…` value from step 1
   - Name: `SUPABASE_PROJECT_REF` · Secret: the Reference ID from step 2

## Deploying from now on

GitHub repo → **Actions** → **Supabase Edge Deploy** → **Run workflow** →
**Run workflow**. Wait ~30 seconds for the green run. Done — the server now
matches the repo exactly.

If the run fails with "Missing secrets", the secrets aren't set (or are set
on the wrong repo). Fix them and run again.

## What it runs

`.github/workflows/supabase-deploy.yml` installs the Supabase CLI and runs
`supabase functions deploy booknest-api --use-api` against your project —
the same result as a dashboard paste, but exact, repeatable and one click.
`supabase/config.toml` pins the function name and keeps JWT verification on
(the app always calls with the signed-in reader's token).
