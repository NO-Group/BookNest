#!/usr/bin/env bash
# Pushes the tail of a failed desktop build to desktop-diag-<os> and opens
# an issue with it, so the real error is readable without the log host.
# Usage: desktop-diag.sh <os>
set -u
OS="$1"
OUT="desktop-error-${OS}.txt"
{
  echo "${OS} build diag $(date -u +%FT%TZ) — run ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
  echo '--- build.log tail ---'
  tail -c 3000 build.log 2>/dev/null || echo "(build.log missing — failed before the build step)"
  echo '--- dist ---'
  ls -la dist 2>&1 | tail -10
} > "$OUT"
git config user.email "booknest-ci@users.noreply.github.com"
git config user.name "booknest-ci"
git checkout -q -B "desktop-diag-${OS}"
git add "$OUT"
git commit -q -m "${OS} build diag $(date -u +%FT%TZ)" || true
git push -q -f origin "desktop-diag-${OS}" || true
{
  echo "OS: ${OS} — [run log](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID})"
  echo ''
  echo '```'
  cat "$OUT"
  echo '```'
} > issue-body.md
gh issue create --title "Desktop build failed: ${OS} ($(date -u +%H:%M))" \
  --body-file issue-body.md || true
