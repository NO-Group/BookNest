#!/usr/bin/env bash
# Google Play readiness report for a built APK (+ AAB). Prints Markdown.
#   • package / versionCode / targetSdk (Play needs target 35+ in 2025-26)
#   • merged permissions, flagging ones Play restricts or reviews
#   • 16 KB page-size support: every arm64/x86_64 native library must have
#     LOAD segments aligned to 16 KB (0x4000) — Play rejects updates that
#     target Android 15+ without it — plus the zip alignment of the APK.
# Report only: never fails the build.
set -uo pipefail
APK="$1"; AAB="${2:-}"
BT="$(ls -d "$ANDROID_HOME"/build-tools/* 2>/dev/null | sort -V | tail -1)"
AAPT2="$BT/aapt2"; ZIPALIGN="$BT/zipalign"
READELF="$(command -v readelf || ls "$ANDROID_HOME"/ndk/*/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf 2>/dev/null | tail -1)"

echo "# Google Play readiness — $(date -u +%F' '%H:%M) UTC"
echo
echo "Build tools: \`$(basename "$BT")\` · APK $(du -h "$APK" | cut -f1)${AAB:+ · AAB $(du -h "$AAB" | cut -f1)}"
echo

BADGING="$("$AAPT2" dump badging "$APK" 2>/dev/null)"
PKG="$(printf '%s\n' "$BADGING" | grep -oE "^package: name='[^']+'" | cut -d"'" -f2)"
VC="$(printf '%s\n' "$BADGING" | grep -oE "versionCode='[0-9]+'" | head -1 | cut -d"'" -f2)"
VN="$(printf '%s\n' "$BADGING" | grep -oE "versionName='[^']+'" | head -1 | cut -d"'" -f2)"
TSDK="$(printf '%s\n' "$BADGING" | grep -oE "^targetSdkVersion:'[0-9]+'" | cut -d"'" -f2)"
MSDK="$(printf '%s\n' "$BADGING" | grep -oE "^(minSdkVersion|sdkVersion):'[0-9]+'" | head -1 | cut -d"'" -f2)"
ok() { [ "$1" = 1 ] && echo "✅" || echo "❌"; }
echo "## App"
echo
echo "| item | value | Play |"
echo "|---|---|---|"
echo "| package | \`$PKG\` | |"
echo "| version | $VN ($VC) | |"
echo "| minSdk | ${MSDK:-?} | |"
echo "| targetSdk | ${TSDK:-?} | $(ok $([ "${TSDK:-0}" -ge 35 ] && echo 1 || echo 0)) needs ≥ 35 |"
echo

echo "## Permissions"
echo
printf '%s\n' "$BADGING" | grep -oE "^uses-permission: name='[^']+'" | cut -d"'" -f2 | sort -u | while read -r p; do
  note=""
  case "$p" in
    *REQUEST_IGNORE_BATTERY_OPTIMIZATIONS) note=" ❌ restricted by Play policy" ;;
    *READ_MEDIA_IMAGES|*READ_MEDIA_VIDEO) note=" ❌ Play photo/video policy — use the photo picker" ;;
    *MANAGE_EXTERNAL_STORAGE|*QUERY_ALL_PACKAGES|*READ_SMS|*READ_CALL_LOG|*ACCESS_BACKGROUND_LOCATION) note=" ❌ restricted — needs a Play declaration" ;;
    *FOREGROUND_SERVICE_*) note=" ⚠️ declare this foreground-service type in Play Console (App content)" ;;
    *USE_EXACT_ALARM|*SCHEDULE_EXACT_ALARM) note=" ⚠️ exact alarms — Play declaration needed" ;;
    *USE_FULL_SCREEN_INTENT) note=" ⚠️ full-screen intent — Play declaration (calls/alarms only)" ;;
    *CAMERA|*RECORD_AUDIO) note=" · Data safety form" ;;
  esac
  echo "- \`$p\`$note"
done
echo

echo "## 16 KB page size (native libraries)"
echo
TMP="$(mktemp -d)"
unzip -q -o "$APK" 'lib/*' -d "$TMP" 2>/dev/null || true
BAD=0; TOTAL=0
ROWS=""
for so in $(find "$TMP/lib" -name '*.so' 2>/dev/null | sort); do
  abi="$(basename "$(dirname "$so")")"
  case "$abi" in arm64-v8a|x86_64) ;; *) continue ;; esac
  TOTAL=$((TOTAL + 1))
  min="$("$READELF" -lW "$so" 2>/dev/null | awk '$1=="LOAD"{print $NF}' | while read -r a; do printf '%d\n' "$a"; done | sort -n | head -1)"
  if [ -n "$min" ] && [ "$min" -ge 16384 ]; then :; else
    BAD=$((BAD + 1)); ROWS="$ROWS\n| $abi | $(basename "$so") | ${min:-?} |"
  fi
done
if [ "$TOTAL" = 0 ]; then
  echo "No 64-bit native libraries found."
elif [ "$BAD" = 0 ]; then
  echo "✅ All $TOTAL 64-bit libraries are 16 KB aligned."
else
  echo "❌ $BAD of $TOTAL 64-bit libraries are NOT 16 KB aligned (Play blocks such updates):"
  echo
  echo "| abi | library | smallest LOAD alignment (bytes) |"
  echo "|---|---|---|"
  printf "%b\n" "${ROWS#\\n}"
fi
echo
if "$ZIPALIGN" -c -P 16 -v 4 "$APK" > "$TMP/za.txt" 2>&1; then
  echo "✅ APK zip alignment OK for 16 KB pages."
else
  echo "❌ APK zip alignment fails the 16 KB check:"
  echo '```'; grep -v "(OK" "$TMP/za.txt" | tail -15; echo '```'
fi
echo
if [ -n "$AAB" ]; then
  echo "## App Bundle"
  echo
  echo "- \`$(basename "$AAB")\` contains $(unzip -l "$AAB" | grep -c '\.so$') native library entries; upload it in Play Console → Test and release."
fi
rm -rf "$TMP"
