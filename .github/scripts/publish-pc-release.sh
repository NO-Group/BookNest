#!/usr/bin/env bash
# Attaches files to this run's shared "BookNest <ver> for PC" release.
# Usage: publish-pc-release.sh <version> <file>...
# Every desktop job calls this; whichever finishes first creates the
# release, the rest upload into it. Retries cover the create race.
set -uo pipefail

VER="$1"; shift
TAG="pc-${VER}-${GITHUB_RUN_ID}"
TITLE="BookNest ${VER} for PC"
NOTES="BookNest ${VER} for PC.

• Windows: download **BookNest-Setup.exe** and run it (or the portable BookNest-windows.zip → booknest.exe).
• macOS: BookNest-macos.zip → drag BookNest to Applications. Unsigned: right-click → Open the first time.
• Linux: BookNest-linux.tar.gz → untar, run ./booknest.

Built from ${GITHUB_SHA:0:7}."

for f in "$@"; do
  [ -f "$f" ] || { echo "missing $f"; exit 1; }
done

for attempt in 1 2 3 4 5; do
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$@" --clobber && { echo "uploaded $* → $TAG"; exit 0; }
  else
    gh release create "$TAG" "$@" --target "$GITHUB_SHA" \
      --title "$TITLE" --notes "$NOTES" && { echo "created $TAG with $*"; exit 0; }
  fi
  echo "attempt $attempt failed — retrying"
  sleep $((attempt * 7))
done
echo "could not publish $* to $TAG"
exit 1
