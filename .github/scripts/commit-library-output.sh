#!/usr/bin/env bash
# Commits library reports/samples back to the branch ([skip ci]) so they
# can be read without access to the Actions logs. Never fails the job.
set -uo pipefail
MSG="$1"; shift
git config user.email "booknest-ci@users.noreply.github.com"
git config user.name "booknest-ci"
for f in "$@"; do [ -e "$f" ] && git add -f "$f" 2>/dev/null; done; true
git diff --cached --quiet && { echo "nothing to commit"; exit 0; }
git commit -q -m "$MSG [skip ci]"
for i in 1 2 3 4 5; do
  git pull -q --rebase --autostash origin "${GITHUB_REF_NAME}" && git push -q origin "HEAD:${GITHUB_REF_NAME}" && exit 0
  sleep $((i * 5))
done
echo "could not push library output" >&2
exit 0
