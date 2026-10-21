# Production health — 2026-10-21T20:06:52Z

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

- ping → curl=0 http=200 3.488418s body: {"ok":true,"data":{"databases":{"books":"booknest_books","social":"booknest_social","reviews":"booknest_reviews","chats":"booknest_chats","notifications":"booknest_notifications","users":"booknest_users","dictionary":"booknest_dictionary","feed":"booknest_feed
- books.list → curl=0 http=200 3.962289s body: {"ok":true,"data":{"books":[{"id":"bulk-child-of-storm|h-rider-henry-rider-1856-1925-haggard","title":"Child of Storm","author":"H. Rider (Henry Rider), 1856-1925 Haggard","description":"A beloved history classic by H. Rider (Henry Rider), 1856-1925 Haggard, a
- latency series (tls+connect / first byte / total, server timing):
  - ping #1: 0.049076s / 3.404118s / 3.404210s · {"connectMs":2435,"mongoPingMs":472,"isolateAgeMs":21,"served":1,"fnRegion":"us-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #2: 0.068722s / 3.440072s / 3.440160s · {"connectMs":2445,"mongoPingMs":469,"isolateAgeMs":22,"served":1,"fnRegion":"us-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #3: 0.046754s / 3.441841s / 3.442079s · {"connectMs":2460,"mongoPingMs":471,"isolateAgeMs":22,"served":1,"fnRegion":"us-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #4: 0.045370s / 3.423264s / 3.423494s · {"connectMs":2436,"mongoPingMs":472,"isolateAgeMs":22,"served":1,"fnRegion":"us-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #5: 0.046371s / 3.431795s / 3.432030s · {"connectMs":2458,"mongoPingMs":474,"isolateAgeMs":22,"served":1,"fnRegion":"us-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #6: 0.045482s / 3.399000s / 3.399241s · {"connectMs":2436,"mongoPingMs":472,"isolateAgeMs":22,"served":1,"fnRegion":"us-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
- latency series pinned to eu-west-1 (what the app sends from 2.33):
  - ping #1: 1.902699s / 1.902919s · {"connectMs":479,"mongoPingMs":82,"isolateAgeMs":21,"served":1,"fnRegion":"eu-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #2: 1.167306s / 1.167529s · {"connectMs":525,"mongoPingMs":87,"isolateAgeMs":24,"served":1,"fnRegion":"eu-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #3: 1.448449s / 1.448665s · {"connectMs":487,"mongoPingMs":84,"isolateAgeMs":22,"served":1,"fnRegion":"eu-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #4: 1.107804s / 1.108051s · {"connectMs":490,"mongoPingMs":82,"isolateAgeMs":22,"served":1,"fnRegion":"eu-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #5: 1.079599s / 1.079789s · {"connectMs":486,"mongoPingMs":85,"isolateAgeMs":22,"served":1,"fnRegion":"eu-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - ping #6: 1.093872s / 1.094070s · {"connectMs":484,"mongoPingMs":82,"isolateAgeMs":22,"served":1,"fnRegion":"eu-west-1","dbRegion":"GCP:WESTERN_EUROPE"}
  - books.list(20) eu-west-1 #1: 1.073556s / 1.074006s
  - books.list(20) eu-west-1 #2: 1.739290s / 1.739430s
  - books.list(20) eu-west-1 #3: 1.089034s / 1.089478s
  - books.list(20) #1: 3.429600s / 3.429700s
  - books.list(20) #2: 3.458540s / 3.466160s
  - books.list(20) #3: 3.421489s / 3.421550s
- REST API → http 401
- Auth health → http 200 {"version":"v2.197.0","name":"GoTrue","description":"GoTrue is a user registration and authentication API"}

## Edge function logs (last 30 min)

```
```

## Cloudflare

- account id set: yes · api token set: yes · r2 keys set: yes · bucket set: yes (booknest)
- user-token verify: {"success":false,"status":null}
- account-token verify: {"success":true,"status":"active"}
- R2 buckets via API token: {"success":true,"buckets":["booknest"],"errors":[]}
- Workers AI access: {"success":false,"errors":["Authentication error"]}
- R2 S3 keys: write=ok read=ok
