#!/bin/bash
# Fork: publish nextshot.dev, the Nextshot download page, to Cloudflare.
#
# Stages build/site from site/public and the newest onboarding video in
# build/releases. Then it runs `wrangler deploy` and the smoke test
# (site/smoke.sh) against the live site. The DMGs are not part of a deploy: they
# live in the private R2 bucket nextshot-releases, and latest.json there says
# which one /download serves (scripts/release.sh writes both). The Cloudflare
# API token comes from the Keychain item CLOUDFLARE_API_TOKEN_NEXTSHOT, in
# memory only. See docs/site.md.
#
# Usage: site/deploy.sh [--video FILE] [--poster FILE] [--stage-only]
#   --poster      an image for the video poster (default: a frame from the video)
#   --stage-only  stage build/site and stop (for `wrangler dev` checks)
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
releases="$repo/build/releases"
stage="$repo/build/site"
max_bytes=$((25 * 1024 * 1024)) # Workers static assets limit per file
# shellcheck source=scripts/release-lib.sh
source "$repo/scripts/release-lib.sh"

video="" poster="" stage_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --video) video="$2"; shift 2 ;;
    --poster) poster="$2"; shift 2 ;;
    --stage-only) stage_only=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

fail() { echo "deploy: $*" >&2; exit 1; }

# Default input: the newest dated video. The Codex video drafts do not match
# this glob. Music option cuts (-musicB.mp4) are skipped: they are newer than
# the main cut but are not the published choice.
[[ -n "$video" ]] || video="$(ls -t "$releases"/Nextshot-onboarding-20*.mp4 2>/dev/null | grep -v -- '-music' | head -1 || true)"

for f in "$video" ${poster:+"$poster"} "$repo/LICENSE"; do
  [[ -n "$f" && -f "$f" ]] || fail "missing input file: ${f:-(none found)}"
done
for f in "$video" ${poster:+"$poster"}; do
  (($(stat -f %z "$f") < max_bytes)) || fail "$(basename "$f") is 25 MiB or larger, over the static asset limit"
done

video_name="$(basename "$video")"
if [[ -n "$poster" ]]; then
  poster_name="${video_name%.mp4}-poster.${poster##*.}"
else
  poster_name="${video_name%.mp4}-poster.jpg"
fi

# Empty the folder in place: a running `wrangler dev` loses a deleted folder.
mkdir -p "$stage"
find "$stage" -mindepth 1 -delete
mkdir -p "$stage/media" "$stage/fonts"
cp "$repo/site/public/"* "$stage/"
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
# {{VERSION}} stays in the page: the Worker fills it from latest.json on each
# request, so a release or a rollback shows with no deploy.
sed -i '' -e "s|{{VIDEO}}|$video_name|g" -e "s|{{POSTER}}|$poster_name|g" "$stage/index.html"
! grep -o '{{[A-Z]*}}' "$stage/index.html" | grep -qv '{{VERSION}}' || fail "index.html still has a placeholder"

# Byte sizes for the Worker's Range replies (see sizeOf in src/worker.js).
sizes="/media/$video_name=$(stat -f %z "$video")"

echo "Staged $stage: $video_name"
if ((stage_only)); then
  echo "Local check: wrangler dev --config site/wrangler.jsonc --var SIZES:$sizes --persist-to <folder>"
  echo "(--persist-to is the folder NEXTSHOT_R2_LOCAL points at, so the local Worker reads the rehearsal bucket)"
  exit 0
fi

# A deploy replaces the Worker. The new Worker serves /download from latest.json
# in R2, so stop when R2 has none: the site would have nothing to offer.
r2_login
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
r2_get latest.json "$work/latest.json" ||
  fail "R2 has no latest.json (or the token cannot read R2). Archive a release first: scripts/release.sh --import-legacy or a release."
record_valid "$work/latest.json" || fail "latest.json in R2 is not a valid release record"
echo "R2 serves $(record_field "$work/latest.json" version) ($(record_field "$work/latest.json" file))"

wrangler deploy --config "$repo/site/wrangler.jsonc" --var "SIZES:$sizes"

"$repo/site/smoke.sh" --url "${NEXTSHOT_SITE_URL:-https://nextshot.dev}" --video "$video_name"
