# Production smoke test — 2026-10-23 11:55 UTC

Two throw-away accounts exercise the live backend exactly like the app does, then delete themselves.

- ✅ **Sign-up and sign-in** — two accounts created and signed in
- ✅ **Server answers** — server 2.31.0, database ready, 2.30s, region eu-west-1
- ✅ **Library loads** — 20 books in 1.17s
- ✅ **Book chapter opens (text from Cloudflare R2)** — “Little Masterpieces of Autobiography: Ac” ch.1: 246,024 chars in 1.59s
- ✅ **Start a chat** — HTTP 200
- ✅ **Send messages** — 2/2 stored (MongoDB writes work)
- ✅ **Other person receives them** — 2 messages read by the recipient in 1.24s
- ✅ **Chat list shows the conversation** — 1 conversation(s)
- ✅ **Reply** — HTTP 200
- ✅ **Answers are compressed (gzip)** — books.list 46.5 KB → 4.8 KB on the wire (gzip)
  - chapter text: 245.6 KB → 99.2 KB on the wire
- ✅ **Unchanged chat costs a few bytes (rev check)** — full page 548 B, unchanged answer 78 B
- ✅ **Call relay offered to the app (TURN)** — relay=cloudflare, 6 TURN entries: turn 3478 tcp, turn 3478 udp, turn 443 udp, turn 80 tcp, turns 443 tcp, turns 5349 tcp
- ✅ **TURN relay carries traffic (UDP 3478)** — lost 0 packets (0.000000%)
- ✅ **TURN relay carries traffic (TCP 3478)** — lost 0 packets (0.000000%)
- ✅ **TURN relay carries traffic (TLS 443)** — lost 0 packets (0.000000%)
- ✅ **Push notifications ready on the server (Firebase)** — HTTP 200, configured=True, google sign-in=True, project=booknest-12-33-oct22-2026
- ✅ **Text chat backup: save, restore, delete** — put HTTP 200 , restore identical=True, deleted=True
- ✅ **Profile cover photo saves and others see it** — save HTTP 200, visible to another reader=True 
- ✅ **Chat file sends and opens (R2 relay, 3 days): smoke.pdf** — upload HTTP 200, download 193 bytes (application/pdf), r2.cloudflarestorage, expires 2026-10-26
- ✅ **Chat file sends and opens (R2 relay, 3 days): smoke.docx** — upload HTTP 200, download 474 bytes (application/vnd.openxmlformats-officedocument.wordprocessingml.document), r2.cloudflarestorage, expires 2026-10-26
- ✅ **Delete account (Settings → Delete my account)** — 2/2 removed by the in-app flow

**21/21 checks passed.**
