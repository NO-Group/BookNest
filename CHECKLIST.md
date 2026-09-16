# BookNest — Your Checklist (from the chat-backup release to publishing)

Everything the code side has shipped (v2.6 → v2.25) is built, green, and
waiting. What follows is **every action only you can do**, in order,
dashboard-click level. Tick them top to bottom — each has a "proof" so
you know it worked.

---

## 1 · Install the current app (5 min)

- [ ] Open **github.com/NO-Group/BookNest** → **Actions** tab.
- [ ] Tap the **newest green run** (its title starts with the highest
      version, e.g. "v2.25…").
- [ ] Scroll to **Artifacts** → download **BookNest-release-apk**.
- [ ] Open the file on the phone → **Install**.
      - If Play Protect interrupts: **More details → Install anyway**.
- [ ] Open BookNest → **Settings → About** → the Version line must show
      **2.25.0+42** or higher.

**Proof:** the version line matches the run you installed.

---

## 2 · Update the server — ONE paste (5 min) ← the big one

The app now carries a guided kit for this, but here is the plain path:

- [ ] On GitHub (same branch, `arena/01a03a7f-booknest`) open
      **`supabase/functions/booknest-api/index.ts`** → **Raw** button →
      select **all** → copy.
- [ ] **supabase.com** dashboard → your project → **Edge Functions** →
      **booknest-api** → **Edit**.
- [ ] Click in the code box → **Ctrl/Cmd+A** → **paste** (replaces the
      old file) → **Deploy** → wait for the confirmation.
- [ ] Back in the app → **Settings → About** → the red banner (if it was
      there) should now be **gone** (or tap **Re-test**).

**Proof:** no red banner in About or Moderation + the file
`backend-probe.txt` (repo root, updates on every CI run) shows a ping
carrying the current `server` stamp and a books list with **6 seeded
classics**.

**Why it matters:** this single paste activates — reports, message
deletes, reactions, the books shelf (auto-seeded with 6 real classics),
the moderator users-list fallback, the in-app deploy-kit handshakes, and
Random Chat matching.

---

## 3 · Never paste again — one-click deploys (3 min, one-time)

- [ ] Supabase dashboard → avatar (bottom-left) → **Account** →
      **Access Tokens** → **Generate new token** (`booknest-ci`) → copy.
- [ ] Project **Settings → General → Reference ID** → copy.
- [ ] GitHub repo → **Settings → Secrets and variables → Actions** →
      **New repository secret**:
      - `SUPABASE_ACCESS_TOKEN` = the token
      - `SUPABASE_PROJECT_REF` = the Reference ID
- [ ] **Actions → Supabase Edge Deploy → Run workflow** → Run.
- [ ] Full guide: **`ops/SUPABASE_AUTO_DEPLOY.md`**.

**Proof:** that workflow run goes green — from now on, server updates
are that one click.

---

## 4 · Calls that connect everywhere — TURN (4 min, one-time, optional but recommended)

- [ ] First do steps 2–3 (TURN rides the updated server).
- [ ] Cloudflare dashboard → **Calls → TURN** → enable → copy the
      **Auth token**.
- [ ] Supabase → Project **Settings → Edge Functions → Secrets** → add:
      - `TURN_URL` =
        `turn:standard.turn.cloudflare.com:3478?transport=udp,turn:standard.turn.cloudflare.com:3478?transport=tcp,turns:standard.turn.cloudflare.com:5349?transport=tcp`
      - `TURN_SECRET` = the auth token
- [ ] Full guide: **`ops/TURN_SETUP.md`**.

**Proof:** calls connect even on stubborn networks (hotel/corporate).

---

## 5 · Test the flagship list (10 min)

- [ ] **Feed**: like a post — count moves instantly. Long post cards
      never overflow; long names shrink to "…".
- [ ] **Chats**: send text, photo, **voice note** (play, scrub, 2×),
      emoji; long-press → reply, react, delete (for me / everyone).
- [ ] **Random chat**: Messages screen → **shuffle icon** → search →
      matched into a normal chat (test with a second account).
- [ ] **Calls**: voice + video between two accounts — timer ticks,
      speaker/earpiece, mute, camera flip. Accept/decline with ringtone.
- [ ] **Books**: shelf shows the 6 classics; open one and read.
- [ ] **Profile**: any reader's page — left-aligned header, stat
      counters, **Follow / Message** pills, Books/About tabs.
- [ ] **Emotes**: keyboard → Emotes/Animated tabs — real Twemoji art
      with the glow-and-motion effects.
- [ ] **Reports**: long-press any message / profile menu → Report →
      it lands in the Moderation console.
- [ ] **Moderator console**: Readers tab fills.

---

## 6 · Move the signing identity into secrets (publish-critical, when ready)

The signing key currently lives in the repo — fine while the repo is
private, but it must move before publishing. The pipeline already
prefers secrets when present (nothing breaks until you rotate):

- [ ] Tell me "rotate the keystore" — I'll generate a fresh identity and
      give you two base64 blobs to paste as GitHub secrets:
      `KEYSTORE_BASE64` and `KEYSTORE_PROPERTIES_BASE64`.
- [ ] I then remove the committed key files; CI keeps signing installs
      so everyone's app keeps updating.

**Proof:** newest green run's log shows "Signing with secret-provided
identity."

---

## 7 · Publish runway — already cleared

- [x] No developer-speak anywhere in the UI (vendor names, "paste",
      "deploy", "server setting" instructions — all rewritten or
      removed for readers; the only technical banner left is the
      owner-only update notice that disappears once step 2 is done).
- [x] Emote artwork properly credited (Settings → About + NOTICE file).
- [x] Store basics: production-signed APK from CI, version bump every
      release, no secrets in the app.

**You're publish-ready when steps 1–2 are ticked.**
