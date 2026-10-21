# Production health — 2026-10-21T20:02:04Z

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
- edge functions: [{"slug":"booknest-api","status":"ACTIVE","version":74,"updated_at":1792611990801}]

## Live checks

- ping → curl=0 http=200 2.708782s body: {"ok":true,"data":{"databases":{"books":"booknest_books","social":"booknest_social","reviews":"booknest_reviews","chats":"booknest_chats","notifications":"booknest_notifications","users":"booknest_users","dictionary":"booknest_dictionary","feed":"booknest_feed
- books.list → curl=0 http=200 2.831498s body: {"ok":true,"data":{"books":[{"id":"bulk-child-of-storm|h-rider-henry-rider-1856-1925-haggard","title":"Child of Storm","author":"H. Rider (Henry Rider), 1856-1925 Haggard","description":"A beloved history classic by H. Rider (Henry Rider), 1856-1925 Haggard, a
- latency series (tls+connect / first byte / total, server timing):
  - ping #1: 0.045371s / 2.375274s / 2.376920s · 
  - ping #2: 0.053519s / 2.528838s / 2.528924s · 
  - ping #3: 0.032656s / 3.234642s / 3.234964s · 
  - ping #4: 0.046033s / 2.550913s / 2.551231s · 
  - ping #5: 0.028837s / 2.434728s / 2.434997s · {"connectMs":1642,"mongoPingMs":318,"isolateAgeMs":17,"served":1}
  - ping #6: 0.051713s / 2.336137s / 2.336362s · {"connectMs":1661,"mongoPingMs":318,"isolateAgeMs":24,"served":1}
  - books.list(20) #1: 2.520334s / 2.521205s
  - books.list(20) #2: 2.556087s / 2.556275s
  - books.list(20) #3: 2.740830s / 2.740929s
- REST API → http 401
- Auth health → http 200 {"version":"v2.197.0","name":"GoTrue","description":"GoTrue is a user registration and authentication API"}

## Cloudflare

- account id set: yes · api token set: yes · r2 keys set: yes · bucket set: yes (booknest)
- user-token verify: {"success":false,"status":null}
- account-token verify: {"success":true,"status":"active"}
- R2 buckets via API token: {"success":true,"buckets":["booknest"],"errors":[]}
- Workers AI access: {"success":false,"errors":["Authentication error"]}
- R2 S3 keys: write=ok read=ok
