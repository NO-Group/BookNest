# Production health — 2026-10-21T20:04:28Z

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
- edge functions: [{"slug":"booknest-api","status":"ACTIVE","version":78,"updated_at":1792612999729}]

## Live checks

- ping → curl=0 http=200 4.407293s body: {"ok":true,"data":{"databases":{"books":"booknest_books","social":"booknest_social","reviews":"booknest_reviews","chats":"booknest_chats","notifications":"booknest_notifications","users":"booknest_users","dictionary":"booknest_dictionary","feed":"booknest_feed
- books.list → curl=0 http=200 3.205496s body: {"ok":true,"data":{"books":[{"id":"bulk-child-of-storm|h-rider-henry-rider-1856-1925-haggard","title":"Child of Storm","author":"H. Rider (Henry Rider), 1856-1925 Haggard","description":"A beloved history classic by H. Rider (Henry Rider), 1856-1925 Haggard, a
- latency series (tls+connect / first byte / total, server timing):
  - ping #1: 0.049095s / 3.451084s / 3.451178s · {"connectMs":2447,"mongoPingMs":473,"isolateAgeMs":22,"served":1,"fnRegion":"us-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #2: 0.048671s / 3.368865s / 3.368962s · {"connectMs":2426,"mongoPingMs":470,"isolateAgeMs":17,"served":1,"fnRegion":"us-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #3: 0.033302s / 3.431225s / 3.431441s · {"connectMs":2439,"mongoPingMs":475,"isolateAgeMs":22,"served":1,"fnRegion":"us-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #4: 0.047892s / 3.458885s / 3.459081s · {"connectMs":2440,"mongoPingMs":472,"isolateAgeMs":22,"served":1,"fnRegion":"us-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #5: 0.049601s / 3.431020s / 3.431511s · {"connectMs":2450,"mongoPingMs":470,"isolateAgeMs":22,"served":1,"fnRegion":"us-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #6: 0.044081s / 3.427930s / 3.428143s · {"connectMs":2430,"mongoPingMs":471,"isolateAgeMs":22,"served":1,"fnRegion":"us-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - books.list(20) #1: 3.462118s / 3.462176s
  - books.list(20) #2: 3.451008s / 3.451222s
  - books.list(20) #3: 3.610511s / 3.610701s
- REST API → http 401
- Auth health → http 200 {"version":"v2.197.0","name":"GoTrue","description":"GoTrue is a user registration and authentication API"}

## Cloudflare

- account id set: yes · api token set: yes · r2 keys set: yes · bucket set: yes (booknest)
- user-token verify: {"success":false,"status":null}
- account-token verify: {"success":true,"status":"active"}
- R2 buckets via API token: {"success":true,"buckets":["booknest"],"errors":[]}
- Workers AI access: {"success":false,"errors":["Authentication error"]}
- R2 S3 keys: write=ok read=ok
