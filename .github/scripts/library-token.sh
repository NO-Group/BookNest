#!/usr/bin/env bash
# Shared by the library workflows:
#   1. waits until the live edge function runs the server version in this
#      commit (the Supabase deploy workflow ships it on the same push),
#   2. mints a fresh IMPORT_TOKEN on the server (never printed or stored),
#   3. waits until the server accepts it.
# Exports FN_URL, ANON and IMPORT_TOKEN to later steps via $GITHUB_ENV.
set -euo pipefail
REF="${SUPABASE_PROJECT_REF:-ekgbbbbjwgfixqarlnil}"
FN_URL="https://${REF}.supabase.co/functions/v1/booknest-api"
ANON="$(grep -A3 'supabaseAnonKey = ' lib/config/app_config.dart | grep -oE "eyJ[^']+")"
WANT="$(grep -oE "server: '[0-9.]+'" supabase/functions/booknest-api/index.ts | head -1 | grep -oE '[0-9.]+')"
echo "FN_URL=$FN_URL" >> "$GITHUB_ENV"
echo "ANON=$ANON" >> "$GITHUB_ENV"

for i in $(seq 1 60); do
  GOT="$(curl -s --max-time 20 -X POST "$FN_URL" -H "Authorization: Bearer $ANON" \
    -H 'Content-Type: application/json' -d '{"action":"ping"}' \
    | grep -oE '"server":"[0-9.]+"' | grep -oE '[0-9.]+' || true)"
  if [ "$GOT" = "$WANT" ]; then echo "Server $GOT is live."; break; fi
  echo "waiting for server $WANT (live: ${GOT:-?}) — $i/60"
  if [ "$i" = 60 ]; then echo "Server $WANT never went live" >&2; exit 1; fi
  sleep 20
done

TOKEN="$(openssl rand -hex 24)"
echo "::add-mask::$TOKEN"
echo "IMPORT_TOKEN=$TOKEN" >> "$GITHUB_ENV"
supabase secrets set IMPORT_TOKEN="$TOKEN" --project-ref "$REF" >/dev/null

for i in $(seq 1 18); do
  CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST "$FN_URL" \
    -H "Authorization: Bearer $ANON" -H 'Content-Type: application/json' \
    -d "{\"action\":\"admin.libraryIndex\",\"importToken\":\"$TOKEN\",\"limit\":1}")"
  if [ "$CODE" = "200" ]; then echo "Import key accepted."; exit 0; fi
  echo "attempt $i: HTTP $CODE — waiting for the key to go live…"
  sleep 10
done
echo "The server never accepted the import key" >&2
exit 1
