#!/usr/bin/env bash
# ============================================================================
# BookNest → Supabase Edge Function deployer
#
# What it does:
#   1. Loads real secrets from backend/secrets.local.env (git-ignored).
#   2. Links the Supabase CLI to project $SUPABASE_PROJECT_REF.
#   3. Pushes every non-empty value into Supabase Edge Function secrets.
#   4. Deploys supabase/functions/booknest-api.
#   5. Prints a smoke-test command to verify MongoDB connectivity.
#
# Prereqs: Node.js + `npm install -g supabase`  (then `supabase login` once).
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f backend/secrets.local.env ]]; then
  echo "❌ backend/secrets.local.env not found."
  echo "   Copy backend/secrets.local.env.example → backend/secrets.local.env"
  echo "   and fill in the real values first."
  exit 1
fi

# Load secrets into env vars WITHOUT printing them.
set -a
# shellcheck disable=SC1091
source backend/secrets.local.env
set +a

command -v supabase >/dev/null 2>&1 || {
  echo "❌ Supabase CLI not found. Install with:  npm install -g supabase"
  exit 1
}

: "${SUPABASE_PROJECT_REF:?Set SUPABASE_PROJECT_REF in secrets.local.env}"

echo "🔗 Linking Supabase project ${SUPABASE_PROJECT_REF}…"
supabase link --project-ref "$SUPABASE_PROJECT_REF"

echo "🔐 Setting Edge Function secrets (values hidden)…"
# NOTE: SUPABASE_* keys are reserved — Supabase auto-injects them into every
# edge function, so they are deliberately NOT set here.
for key in \
  MONGO_URI MONGO_DB_NAME \
  R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET_NAME R2_PUBLIC_DOMAIN_URL \
  CLOUDINARY_API_KEY CLOUDINARY_API_SECRET; do
  value="${!key:-}"
  if [[ -n "$value" ]]; then
    supabase secrets set "$key=$value" >/dev/null
    echo "   ✔ $key set"
  else
    echo "   – $key skipped (empty — fine for R2 until the bucket exists)"
  fi
done

echo "🚀 Deploying booknest-api…"
supabase functions deploy booknest-api

echo
echo "✅ Deployed. Smoke test (MongoDB connectivity):"
echo "   curl -s -X POST '${SUPABASE_URL}/functions/v1/booknest-api' \\"
echo "     -H 'Authorization: Bearer ${SUPABASE_ANON_KEY}' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"action\":\"ping\",\"payload\":{}}'"
echo
echo "   Expect: {\"ok\":true,\"data\":{\"db\":\"booknest\",…}}"
