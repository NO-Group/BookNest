# Production health — 2026-10-21T19:38:43Z

## Secrets and variables present

- CLOUDFLARE_ACCOUNT_ID: secret=true variable=false
- CLOUDFLARE_API_TOKEN: secret=true variable=false
- R2_ACCESS_KEY_ID: secret=true variable=false
- R2_SECRET_ACCESS_KEY: secret=true variable=false
- R2_BUCKET: secret=true variable=false
- SUPABASE_ACCESS_TOKEN: secret=true variable=false
- SUPABASE_PROJECT_REF: secret=true variable=false

## Supabase

- project status: **ACTIVE_HEALTHY**
- region: eu-west-1
- edge functions: [{"slug":"booknest-api","status":"ACTIVE","version":68,"updated_at":1791353991915}]

## Live checks

- ping → curl=0 http=200 4.055869s body: {"ok":true,"data":{"databases":{"books":"booknest_books","social":"booknest_social","reviews":"booknest_reviews","chats":"booknest_chats","notifications":"booknest_notifications","users":"booknest_users","dictionary":"booknest_dictionary","feed":"booknest_feed
- books.list → curl=0 http=200 3.225427s body: {"ok":true,"data":{"books":[{"id":"bulk-child-of-storm|h-rider-henry-rider-1856-1925-haggard","title":"Child of Storm","author":"H. Rider (Henry Rider), 1856-1925 Haggard","description":"A beloved history classic by H. Rider (Henry Rider), 1856-1925 Haggard, a
- REST API → http 401
- Auth health → http 200 {"version":"v2.197.0","name":"GoTrue","description":"GoTrue is a user registration and authentication API"}

## Cloudflare

- account id set: yes · api token set: yes · r2 keys set: yes · bucket set: yes (booknest)
- user-token verify: {"success":false,"status":null}
- account-token verify: {"success":true,"status":"active"}
- R2 buckets via API token: {"success":true,"buckets":["booknest"],"errors":[]}
- Workers AI access: {"success":false,"errors":["Authentication error"]}
- R2 S3 keys: write=ok read=ok
