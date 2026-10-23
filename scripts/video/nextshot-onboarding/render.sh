#!/bin/bash
# Render the Nextshot onboarding video in one step.
#
#   scripts/video/nextshot-onboarding/render.sh
#
# 1. make_audio.py: voice, effects, music, and timing.js
# 2. hyperframes render: the video with the soundtrack
# 3. ffmpeg: move the index to the front (faststart), save the poster frame
# 4. checks: format, length, size, and loudness
#
# Output goes beside the DMG in build/releases/, which git ignores.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
OUT_DIR="$REPO/build/releases"
DATE="$(git -C "$REPO" log -1 --format=%cd --date=format:%Y.%m.%d)"
VIDEO="$OUT_DIR/Nextshot-onboarding-$DATE.mp4"
POSTER="$OUT_DIR/Nextshot-onboarding-poster.png"
RAW="$HERE/renders/raw.mp4"

mkdir -p "$OUT_DIR" "$HERE/renders"
python3 "$HERE/make_audio.py"
"$HERE/node_modules/.bin/hyperframes" render "$HERE" -o "$RAW" --quality delivery --quiet
ffmpeg -y -loglevel error -i "$RAW" -c copy -movflags +faststart "$VIDEO"
DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO")"
POSTER_AT="$(python3 -c "print(max(0.0, $DURATION - 0.5))")"
ffmpeg -y -loglevel error -ss "$POSTER_AT" -i "$VIDEO" -frames:v 1 "$POSTER"

echo "video  $VIDEO"
echo "poster $POSTER"
ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,pix_fmt \
  -show_entries format=duration,size -of compact "$VIDEO"
ffmpeg -hide_banner -i "$VIDEO" -af ebur128=peak=true -f null - 2>&1 | grep -E '^\s+(I|Peak):'
