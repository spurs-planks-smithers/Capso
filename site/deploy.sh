#!/bin/bash
# Fork: publish nextshot.dev, the Nextshot download page, to Cloudflare.
#
# Stages build/site from site/public, the newest notarized DMG, and the newest
# onboarding video in build/releases. Then it runs `wrangler deploy` and a
# smoke test against the live site. The Cloudflare API token comes from the
# Keychain item CLOUDFLARE_API_TOKEN_NEXTSHOT, in memory only. See docs/site.md.
#
# Usage: site/deploy.sh [--dmg FILE] [--video FILE] [--poster FILE] [--stage-only]
#   --poster      an image for the video poster (default: a frame from the video)
#   --stage-only  stage build/site and stop (for `wrangler dev` checks)
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
releases="$repo/build/releases"
stage="$repo/build/site"
keychain_item="CLOUDFLARE_API_TOKEN_NEXTSHOT"
site_url="https://nextshot.dev"
max_bytes=$((25 * 1024 * 1024)) # Workers static assets limit per file

dmg="" video="" poster="" stage_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg) dmg="$2"; shift 2 ;;
    --video) video="$2"; shift 2 ;;
    --poster) poster="$2"; shift 2 ;;
    --stage-only) stage_only=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

fail() { echo "deploy: $*" >&2; exit 1; }

# The newest file for a glob, by modification time. Empty when none match.
newest() { ls -t $1 2>/dev/null | head -1 || true; }

# Default inputs: the newest versioned DMG and the newest dated video. A
# versioned DMG is Nextshot-<MAJOR>.<MINOR>.<PATCH>.dmg with a one or two digit
# MAJOR, for example Nextshot-0.4.0.dmg. The date builds (Nextshot-2026.10.24-*),
# the Capso 1.2.5 DMGs (in legacy/), and the Codex video drafts do not match.
# Pass --dmg for a legacy file. Music option cuts (-musicB.mp4) are skipped:
# they are newer than the main cut but are not the published choice.
[[ -n "$dmg" ]] || dmg="$(newest "$releases/Nextshot-[0-9].[0-9]*.dmg $releases/Nextshot-[0-9][0-9].[0-9]*.dmg")"
[[ -n "$video" ]] || video="$(ls -t "$releases"/Nextshot-onboarding-20*.mp4 2>/dev/null | grep -v -- '-music' | head -1 || true)"

for f in "$dmg" "$video" ${poster:+"$poster"} "$repo/LICENSE"; do
  [[ -n "$f" && -f "$f" ]] || fail "missing input file: ${f:-(none found)}"
done
for f in "$dmg" "$video" ${poster:+"$poster"}; do
  (($(stat -f %z "$f") < max_bytes)) || fail "$(basename "$f") is 25 MiB or larger, over the static asset limit"
done
xcrun stapler validate "$dmg" >/dev/null 2>&1 || fail "$(basename "$dmg") has no stapled notarization ticket"

dmg_name="$(basename "$dmg")"
# The version is the file name between "Nextshot-" and ".dmg". A date build
# also ends in -<commit>, which is cut off. A dirty build is never published.
version="${dmg_name#Nextshot-}"
version="${version%.dmg}"
[[ "$version" != *-dirty ]] || fail "$dmg_name was built from uncommitted changes"
version="${version%-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "$dmg_name does not hold a MAJOR.MINOR.PATCH version"
video_name="$(basename "$video")"
if [[ -n "$poster" ]]; then
  poster_name="${video_name%.mp4}-poster.${poster##*.}"
else
  poster_name="${video_name%.mp4}-poster.jpg"
fi
size="$(awk -v b="$(stat -f %z "$dmg")" 'BEGIN { printf "%.1f MB", b / 1000000 }')"

# Empty the folder in place: a running `wrangler dev` loses a deleted folder.
mkdir -p "$stage"
find "$stage" -mindepth 1 -delete
mkdir -p "$stage/media" "$stage/releases" "$stage/fonts"
cp "$repo/site/public/"* "$stage/"
cp "$dmg" "$stage/releases/$dmg_name"
cp "$video" "$stage/media/$video_name"
if [[ -n "$poster" ]]; then
  cp "$poster" "$stage/media/$poster_name"
else
  # No --poster: use the finished end card, 1 s before the video ends. The v3.1
  # end card builds until about 3 s before the end.
  duration="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$video")"
  poster_at="$(awk -v d="$duration" 'BEGIN { printf "%.2f", d - 1.0 }')"
  ffmpeg -loglevel error -y -ss "$poster_at" -i "$video" -frames:v 1 -q:v 3 "$stage/media/$poster_name"
fi
cp "$repo/.github/assets/nextshot-icon.png" "$stage/nextshot-icon.png"
cp "$repo/scripts/video/nextshot-onboarding/assets/fonts/Inter-latin.woff2" "$stage/fonts/"
cp "$repo/LICENSE" "$stage/LICENSE.txt"
sed -i '' -e "s|{{VERSION}}|$version|g" -e "s|{{SIZE}}|$size|g" \
  -e "s|{{VIDEO}}|$video_name|g" -e "s|{{POSTER}}|$poster_name|g" "$stage/index.html"
! grep -q '{{' "$stage/index.html" || fail "index.html still has a placeholder"

# Byte sizes for the Worker's Range replies (see sizeOf in src/worker.js).
sizes="/media/$video_name=$(stat -f %z "$video"),/releases/$dmg_name=$(stat -f %z "$dmg")"

echo "Staged $stage: $dmg_name ($version, $size), $video_name"
if ((stage_only)); then
  echo "Local check: wrangler dev --config site/wrangler.jsonc --var DMG_FILE:$dmg_name --var VERSION:$version --var SIZES:$sizes"
  exit 0
fi

token="$(security find-generic-password -s "$keychain_item" -w 2>/dev/null)" ||
  fail "no Keychain item $keychain_item. Store it with keychain-store.sh $keychain_item"
export CLOUDFLARE_API_TOKEN="$token"
wrangler deploy --config "$repo/site/wrangler.jsonc" --var "DMG_FILE:$dmg_name" --var "VERSION:$version" --var "SIZES:$sizes"

# Smoke test. The user agent marks these requests as bots on /stats. curl asks
# public DNS (1.1.1.1 over HTTPS), because this Mac can cache "no such domain"
# from before the custom domain existed.
ua="nextshot-smoke-test"
live() { curl --doh-url https://1.1.1.1/dns-query "$@"; }
status() { live -s -o /dev/null -A "$ua" -w '%{http_code}' "$@"; }
failed=0
check() {
  if [[ "$2" == "$1" ]]; then echo "ok    $3"; else echo "FAIL  $3 (got '$2', want '$1')" >&2; failed=1; fi
}

# A new custom domain can take a minute to get its certificate.
for _ in $(seq 1 24); do
  [[ "$(status "$site_url/")" == 200 ]] && break
  sleep 5
done

check 200 "$(status "$site_url/")" "page"
check "noindex, nofollow" "$(live -sI -A "$ua" "$site_url/" | awk 'tolower($1) == "x-robots-tag:" { $1 = ""; sub(/^ /, ""); sub(/\r$/, ""); print }')" "noindex header"
check "$site_url/releases/$dmg_name" "$(live -s -o /dev/null -A "$ua" -w '%{redirect_url}' "$site_url/download")" "/download redirect"
check "$(shasum -a 256 <"$dmg" | cut -d' ' -f1)" "$(live -s -A "$ua" "$site_url/releases/$dmg_name" | shasum -a 256 | cut -d' ' -f1)" "DMG SHA-256"
check 206 "$(status -r 0-1023 "$site_url/media/$video_name")" "video range request"
check 301 "$(status "https://www.nextshot.dev/x")" "www redirect"
check 200 "$(status "$site_url/stats")" "stats page"

((failed == 0)) || fail "smoke test failed"
echo "Live: $site_url ($version)"
