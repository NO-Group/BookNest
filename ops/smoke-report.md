# Production smoke test — 2026-10-23 09:00 UTC

Two throw-away accounts exercise the live backend exactly like the app does, then delete themselves.

- ✅ **Sign-up and sign-in** — two accounts created and signed in
- ✅ **Server answers** — server 2.29.0, database ready, 1.16s, region eu-west-1
- ✅ **Library loads** — 20 books in 1.08s
- ✅ **Book chapter opens (text from Cloudflare R2)** — “1492” ch.1: 11,248 chars in 1.64s
- ✅ **Start a chat** — HTTP 200
- ✅ **Send messages** — 2/2 stored (MongoDB writes work)
- ✅ **Other person receives them** — 2 messages read by the recipient in 1.35s
- ✅ **Chat list shows the conversation** — 1 conversation(s)
- ✅ **Reply** — HTTP 200
- ✅ **Answers are compressed (gzip)** — books.list 46.5 KB → 4.8 KB on the wire (gzip)
  - chapter text: 11.4 KB → 5.2 KB on the wire
- ✅ **Unchanged chat costs a few bytes (rev check)** — full page 542 B, unchanged answer 78 B
- ✅ **Call relay offered to the app (TURN)** — relay=cloudflare, 6 TURN entries: turn 3478 tcp, turn 3478 udp, turn 443 udp, turn 80 tcp, turns 443 tcp, turns 5349 tcp
- ✅ **TURN relay carries traffic (UDP 3478)** — lost 0 packets (0.000000%)
- ✅ **TURN relay carries traffic (TCP 3478)** — lost 0 packets (0.000000%)
- ✅ **TURN relay carries traffic (TLS 443)** — lost 0 packets (0.000000%)
- ✅ **Push notifications ready on the server (Firebase)** — HTTP 200, configured=True, google sign-in=True, project=booknest-12-33-oct22-2026
- ❌ **Chat file opens: smoke.pdf** — download HTTP 401 — enable "Allow delivery of PDF and ZIP files" in Cloudinary Settings → Security
- ✅ **Chat file opens: smoke.docx** — v1792746061/booknest/files/smoke/smoke_msbxrd.docx → 474 bytes
- ✅ **Delete account (Settings → Delete my account)** — 2/2 removed by the in-app flow

**18/19 checks passed.**
