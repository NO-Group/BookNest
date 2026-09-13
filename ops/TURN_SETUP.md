# TURN relay — calls that connect everywhere (dashboard only)

STUN alone can't punch through symmetric corporate NATs. TURN fixes that:
the media relays through Cloudflare (or any coTURN host) when a direct
path is impossible. BookNest already ships the whole mechanism — the
edge mints short-lived TURN credentials on demand (`calls.ice`), and the
app requests fresh ones before every call. Two secrets switch it on.

## One-time setup (about 4 minutes, no terminal)

1. **Get a TURN service**
   - **Cloudflare**: dashboard → **Calls** → **TURN** → accept the terms →
     copy the **Auth token** (secret). Standard URLs are:
     `turn:standard.turn.cloudflare.com:3478?transport=udp`,
     `turn:standard.turn.cloudflare.com:3478?transport=tcp`,
     `turns:standard.turn.cloudflare.com:5349?transport=tcp`
   - Any coTURN host works too — any `turn:` / `turns:` URLs plus its
     `static-auth-secret`.

2. **Deploy the current edge first**
   The `calls.ice` action needs the v2.24 edge — do the usual
   banner-guided update if you haven't yet.

3. **Add the two secrets** (Supabase dashboard → Project Settings →
   **Edge Functions** → **Secrets**):
   - `TURN_URL` — the URLs, comma-separated, exactly as above
     (one string, no spaces).
   - `TURN_SECRET` — the auth token / static-auth secret.

That's it. The next call picks the relay up automatically; credentials
expire after 6 hours and are re-minted per call. With no secrets set,
calls run STUN-only exactly as before — nothing breaks.
