# Deploy BookNest's backend — from the Supabase dashboard only 🖱

**No terminal, no CLI, no bash.** Everything below is done in your browser.
Time: ~10 minutes. You have already done the SQL ✅ and Cloudinary ✅ — this is
the last piece.

---

## Step 1 — Create the edge function (browser code editor)

1. Open **supabase.com/dashboard** → your project (`ekgbbbbjwgfixqarlnil`).
2. In the left sidebar click **Edge Functions**.
3. Click **Create a new function**.
4. If it offers a choice, pick the **browser/editor** option (NOT "via CLI").
5. Name it exactly:
   ```
   booknest-api
   ```
   (The Flutter app calls this name — spelling must match.)
6. The editor shows a starter file. **Select all, delete it**, and paste the
   entire contents of this repo's file:
   [`supabase/functions/booknest-api/index.ts`](../supabase/functions/booknest-api/index.ts)
   → open it on GitHub, click the copy button, paste into the dashboard editor.
7. Click **Deploy**. Wait until it says the function is active.

> Why `npm:mongodb` inside Supabase? Edge Functions run on Deno — the
> `npm:` import is official and supported, and it's how Supabase reaches
> MongoDB for us.

## Step 2 — Add the function secrets (dashboard table)

> ℹ️ **Why Supabase rejected `SUPABASE_…` keys:** that's correct behaviour!
> Keys starting with `SUPABASE_` are **reserved and auto-injected** into every
> edge function (`SUPABASE_URL`, `SUPABASE_ANON_KEY`,
> `SUPABASE_SERVICE_ROLE_KEY` already exist inside your function). You never
> add them manually. The only secrets BookNest needs from you are the five
> below.

1. Still in **Edge Functions**, open the **Secrets** tab
   (project sidebar: **Edge Functions → Secrets**).
2. Add these keys one row at a time. The **values are the credentials you
   already saved** — never paste service secrets into the app or Git:

   | Key | Value | Notes |
   |---|---|---|
   | `MONGO_URI` | your full `mongodb+srv://…` string | Atlas → Connect → Drivers |
   | `MONGO_DB_NAME` | `booknest` | |
   | `CLOUDINARY_API_KEY` | your Cloudinary API key | Console → Settings → Access Keys |
   | `CLOUDINARY_API_SECRET` | your Cloudinary API secret | same page |
   | `R2_*` (5 keys) | *(leave for later)* | when your R2 bucket exists |

## Step 3 — Allow MongoDB to accept Supabase (one setting)

1. Go to **MongoDB Atlas** → your `Books` project → **Network Access**.
2. Click **Add IP Address** → **Allow access from anywhere** (`0.0.0.0/0`) → Confirm.
3. Supabase Edge Functions run on rotating shared IPs — this is required.
   Your Mongo password + the function's own auth checks are the real locks.

## Step 4 — Verify WITHOUT a terminal ✅

Open the **BookNest app** (run it on your phone/PC as usual) and:

1. Log in, then open the **Profile tab**.
2. Look at the chip at the bottom:
   - 🟦 **"BookNest cloud connected ✓"** → deployed and talking to MongoDB. Done!
   - ⚪ "Cloud not connected yet · tap to retry" → tap it; if it stays grey,
     open **Edge Functions → booknest-api → Logs** in the dashboard and check
     the last invocation's error (usually a mistyped secret name from Step 2).

That chip calls the function's `ping` action — if it's cyan, likes, saves,
reviews, views, and book-sharing are now persisting to MongoDB automatically.
No app update was needed; the app was already wired for this.

## Step 5 — Prove it end-to-end (2 accounts, 5 minutes)

1. Open any book → tap **Like**, **Save**, post a **review**.
2. Tap **Share** → pick the other account → send.
3. Log in as the other account → **Messages** tab → the chat with the
   📖 book card should be there.
4. Optional: **Atlas → Browse Collections** → database `booknest` → you'll
   see `book_likes`, `reviews`, `conversations`, `messages`, `notifications`
   filling up — Supabase stays tiny, MongoDB does the lifting, exactly per
   the blueprint.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Chip stays grey, function log says `MONGO_URI secret is not set` | Step 2 — secret name typo'd or missing; names are case-sensitive |
| Log shows Mongo `timeout` / `ETIMEDOUT` | Step 3 — Atlas Network Access not `0.0.0.0/0` |
| Log shows `User is not authorized` | Mongo password wrong in `MONGO_URI`, or Atlas DB user disabled |
| Function 404 in logs | Step 1 — function must be named exactly `booknest-api` |
| Chip green but counters don't move on a friend's phone | Counters sync per account — log in as the other account to see its own state |

## Optional (later): auto-deploy on git push

If you ever edit `index.ts` again, you can skip the dashboard editor:
add a `SUPABASE_ACCESS_TOKEN` (Supabase → Account → Access Tokens) to this
repo's **GitHub → Settings → Secrets and variables → Actions**, and the
included GitHub Action (`.github/workflows/deploy-edge.yml`) deploys on every
push that touches `supabase/functions/`. Until then it stays asleep.
