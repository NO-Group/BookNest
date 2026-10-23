# Production smoke test — 2026-10-23 07:58 UTC

Two throw-away accounts exercise the live backend exactly like the app does, then delete themselves.

- ✅ **Sign-up and sign-in** — two accounts created and signed in
- ✅ **Server answers** — server 2.29.0, database ready, 1.27s, region eu-west-1
- ✅ **Library loads** — 20 books in 1.01s
- ✅ **Book chapter opens (text from Cloudflare R2)** — “New Grub Street” ch.1: 21,644 chars in 1.19s
- ✅ **Start a chat** — HTTP 200
- ✅ **Send messages** — 2/2 stored (MongoDB writes work)
- ✅ **Other person receives them** — 2 messages read by the recipient in 1.16s
- ✅ **Chat list shows the conversation** — 1 conversation(s)
- ✅ **Reply** — HTTP 200
- ✅ **Answers are compressed (gzip)** — books.list 46.5 KB → 4.8 KB on the wire (gzip)
  - chapter text: 22.4 KB → 9.8 KB on the wire
- ✅ **Unchanged chat costs a few bytes (rev check)** — full page 546 B, unchanged answer 78 B
- ✅ **Call relay offered to the app (TURN)** — relay=cloudflare, 6 TURN entries: turn 3478 tcp, turn 3478 udp, turn 443 udp, turn 80 tcp, turns 443 tcp, turns 5349 tcp
- ✅ **TURN relay carries traffic (UDP 3478)** — lost 0 packets (0.000000%)
- ✅ **TURN relay carries traffic (TCP 3478)** — lost 0 packets (0.000000%)
- ✅ **TURN relay carries traffic (TLS 443)** — lost 2 packets (2.500000%)
- ✅ **Push notifications ready on the server (Firebase)** — HTTP 200, configured=True, google sign-in=True, project=booknest-12-33-oct22-2026
- ✅ **Delete account (Settings → Delete my account)** — 2/2 removed by the in-app flow

**17/17 checks passed.**
