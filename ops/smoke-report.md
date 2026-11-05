# Production smoke test — 2026-11-01 15:15 UTC

Two throw-away accounts exercise the live backend exactly like the app does, then delete themselves.

- ✅ **Sign-up and sign-in** — two accounts created and signed in
- ✅ **Server answers** — server 2.34.0, database ready, 1.27s, region eu-west-1
- ✅ **Library loads** — 20 books in 1.02s
- ✅ **Book chapter opens (text from Cloudflare R2)** — “1492” ch.1: 11,248 chars in 1.22s
- ✅ **Start a chat** — HTTP 200
- ✅ **Send messages** — 2/2 stored (MongoDB writes work)
- ✅ **Other person receives them** — 2 messages read by the recipient in 1.26s
- ✅ **Chat list shows the conversation** — 1 conversation(s)
- ✅ **Reply** — HTTP 200
- ✅ **Answers are compressed (gzip)** — books.list 46.5 KB → 4.8 KB on the wire (gzip)
  - chapter text: 11.4 KB → 5.2 KB on the wire
- ✅ **Unchanged chat costs a few bytes (rev check)** — full page 535 B, unchanged answer 78 B
- ✅ **Call relay offered to the app (TURN)** — relay=cloudflare, 6 TURN entries: turn 3478 tcp, turn 3478 udp, turn 443 udp, turn 80 tcp, turns 443 tcp, turns 5349 tcp
- ✅ **TURN relay carries traffic (UDP 3478)** — lost 0 packets (0.000000%)
- ✅ **TURN relay carries traffic (TCP 3478)** — lost 0 packets (0.000000%)
- ✅ **TURN relay carries traffic (TLS 443)** — lost 1 packets (1.250000%)
- ✅ **Push notifications ready on the server (Firebase)** — HTTP 200, configured=True, google sign-in=True, project=booknest-12-33-oct22-2026
- ✅ **Text chat backup: save, restore, delete** — put HTTP 200 , restore identical=True, deleted=True
- ✅ **Profile cover photo saves and others see it** — save HTTP 200, visible to another reader=True 
- ✅ **Chat file sends and opens (R2 relay, 3 days): smoke.pdf** — upload HTTP 200, download 193 bytes (application/pdf), r2.cloudflarestorage, expires 2026-11-04
- ✅ **Chat file sends and opens (R2 relay, 3 days): smoke.docx** — upload HTTP 200, download 474 bytes (application/vnd.openxmlformats-officedocument.wordprocessingml.document), r2.cloudflarestorage, expires 2026-11-04
- ✅ **Viewing another reader's profile shows theirs** — country shown: GH (theirs is GH, mine NG)
- ✅ **Club: every feature works (17/17)** — join, get, add book to reading list, reading list shows the book, remove book, pick of the month, post announcement, read announcements, create channel, list channels, schedule event, RSVP, list events, create department, list departments, set rules, delete group (owner)
- ✅ **Community: every feature works (17/17)** — join, get, add book to reading list, reading list shows the book, remove book, pick of the month, post announcement, read announcements, create channel, list channels, schedule event, RSVP, list events, create department, list departments, set rules, delete group (owner)
- ✅ **Organization: every feature works (17/17)** — join, get, add book to reading list, reading list shows the book, remove book, pick of the month, post announcement, read announcements, create channel, list channels, schedule event, RSVP, list events, create department, list departments, set rules, delete group (owner)
- ✅ **School CBT exams: every step works (22/22)** — teacher adds questions to the bank, student cannot add questions, student sees practice subjects, practice gives questions with answers, practice history, questions locked before the start time, student sees both exams, no questions in the list, enter live exam: 3 questions, no answers sent, autosave, submit: server marks 1/7 (theory pending), no second attempt, leaving and coming back auto-submits, teacher sees the auto-submission, teacher marks theory: 5/7, students cannot open the results sheet, release results, student sees final score, question analysis: 2+2 answered right by 1 of 1, student notified: new exam + results out, duplicate exam = unpublished draft with the same 3 questions, students cannot open a draft, written exam date: add and remove
- ✅ **School: every feature works (22/22)** — join, get, add book to reading list, reading list shows the book, remove book, pick of the month, post announcement, read announcements, create channel, list channels, schedule event, RSVP, list events, create department, list departments, set rules, create class, list classes, assignment with a book, schedule exam, leaderboard, delete group (owner)
- ✅ **Delete account (Settings → Delete my account)** — 2/2 removed by the in-app flow

**27/27 checks passed.**
