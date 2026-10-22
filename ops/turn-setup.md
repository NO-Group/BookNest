# TURN relay setup — 2026-10-22 07:21 UTC
- server secrets readable: 18 names
- server secrets present: 
- ❌ could not create a TURN key: `[{"code":10000,"message":"Authentication error","documentation_url":"https://developers.cloudflare.com/api/resources/calls/subresources/turn/methods/create"}]`
  The Cloudflare API token needs the **Calls: Edit** (Realtime) permission, or create a TURN key in the dashboard (Realtime → TURN) and add GitHub secrets CF_TURN_KEY_ID + CF_TURN_KEY_API_TOKEN.
