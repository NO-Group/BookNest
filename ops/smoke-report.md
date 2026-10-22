# Production smoke test — 2026-10-22 09:29 UTC

Two throw-away accounts exercise the live backend exactly like the app does, then delete themselves.

- ✅ **Sign-up and sign-in** — two accounts created and signed in
- ✅ **Server answers** — server 2.27.3, database ready, 1.08s, region eu-west-1
- ✅ **Library loads** — 20 books in 1.41s
- ✅ **Book chapter opens (text from Cloudflare R2)** — “Pierrette” ch.1: 295,091 chars in 1.76s
- ✅ **Start a chat** — HTTP 200
- ✅ **Send messages** — 2/2 stored (MongoDB writes work)
- ✅ **Other person receives them** — 2 messages read by the recipient in 1.34s
- ✅ **Chat list shows the conversation** — 1 conversation(s)
- ✅ **Reply** — HTTP 200
- ✅ **Call relay offered to the app (TURN)** — relay=cloudflare, 6 TURN entries: turn 3478 tcp, turn 3478 udp, turn 443 udp, turn 80 tcp, turns 443 tcp, turns 5349 tcp
- ✅ **TURN relay carries traffic (UDP 3478)** — lost 0 packets (0.000000%)
- ✅ **TURN relay carries traffic (TCP 3478)** — lost 0 packets (0.000000%)
- ✅ **TURN relay carries traffic (TLS 443)** — lost 0 packets (0.000000%)
- ✅ **Delete account (Settings → Delete my account)** — 2/2 removed by the in-app flow

**14/14 checks passed.**
