# Chat media sweep — 2026-10-23 11:51 UTC

Runs on the server with its own Cloudinary and R2 keys. Chat **photos** leave Cloudinary after **30 days**; chat **files, voice notes and videos** leave the private R2 relay after **3 days**. Readers keep them on their devices and in their own Google Drive.

_Dry run — nothing deleted._
## Cloudflare R2 relay (3 days)
- lifecycle rule: set now
- files scanned: 0, expired: 0, deleted: 0
- live relay size: 0.0 MB

## Cloudinary (chat folders only, 30 days)
- `image booknest/chat/`: scanned 3, older than 30 days 3, deleted 0
- `image booknest/files/`: scanned 1, older than 30 days 0, deleted 0
- `video booknest/files/`: scanned 1, older than 30 days 1, deleted 0
- `raw booknest/files/`: scanned 7, older than 30 days 0, deleted 0
