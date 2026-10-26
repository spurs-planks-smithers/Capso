#!/bin/bash
# Publish the homepage and Guides. Released app files stay in R2.
# Usage: site/deploy.sh [--video FILE] [--poster FILE] [--stage-only]
#        site/deploy.sh --deploy-staged ARTIFACT [--rollback-snapshot FILE]
# --stage-only prints the complete artifact path on its final stdout line.
# Preview: wrangler dev --config ARTIFACT/wrangler.json --persist-to FOLDER
# --deploy-staged verifies all checksums and publishes without rebuilding.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo/scripts/release-lib.sh"
video="$repo/build/releases/Nextshot-onboarding-2026.10.24.mp4"
poster="$repo/build/site-poster.jpg"
stage_only=0 artifact="" snapshot="" custom_media=0
fail() { echo "deploy: $*" >&2; exit 1; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --video) video="$2"; custom_media=1; shift 2 ;;
    --poster) poster="$2"; custom_media=1; shift 2 ;;
    --stage-only) stage_only=1; shift ;;
    --deploy-staged) artifact="$2"; shift 2 ;;
    --rollback-snapshot) snapshot="$2"; shift 2 ;;
    *) fail "unknown option: $1" ;;
  esac
done
if [[ -n "$artifact" ]]; then
  ((stage_only == 0 && custom_media == 0)) || fail "--deploy-staged cannot rebuild or override staged media"
else
  [[ -f "$video" && -f "$poster" ]] || fail "missing pinned video or poster; use --video FILE --poster FILE to override"
  # Build output goes to stderr. Stdout ends with the reusable artifact path.
  stage_log="$(mktemp)"
  if ! node "$repo/site/src/staged-site.mjs" stage "$repo" "$video" "$poster" >"$stage_log"; then
    cat "$stage_log" >&2
    rm -f "$stage_log"
    fail "Guides staging failed; nothing was deployed"
  fi
  artifact="$(tail -1 "$stage_log")"
  cat "$stage_log" >&2
  rm -f "$stage_log"
fi
artifact="$(cd "$artifact" && pwd)"
metadata="$(node "$repo/site/src/staged-site.mjs" verify "$artifact")" || fail "artifact verification failed"
if ((stage_only)); then
  echo "Preview: wrangler dev --config '$artifact/wrangler.json' --persist-to <rehearsal-bucket-folder>" >&2
  echo "$artifact"
  exit 0
fi
r2_login
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
r2_get latest.json "$work/latest.json" || fail "R2 has no readable latest.json; archive an app release first"
record_valid "$work/latest.json" || fail "latest.json in R2 is invalid"
# The current app must pass before its Worker is accepted as a rollback target.
if [[ -z "$snapshot" ]]; then
  "$repo/site/smoke.sh" --url "${NEXTSHOT_SITE_URL:-https://nextshot.dev}"
  snapshot="$work/worker.json"
  "$repo/site/worker-deployment.sh" snapshot "$artifact/wrangler.json" "$snapshot"
fi
[[ -s "$snapshot" ]] || fail "no verified Worker rollback snapshot"
node "$repo/site/src/staged-site.mjs" snapshot-version "$snapshot" >/dev/null || fail "invalid Worker rollback snapshot"
# Keep the snapshot beside the artifact, outside its sealed inventory.
cp "$snapshot" "$artifact.rollback.json"
# A failed CLI command can follow successful activation. Restore first, then
# verify the active version through a separate Cloudflare read.
restore_worker() {
  local rollback_status=0 wanted observed=""
  wanted="$(node "$repo/site/src/staged-site.mjs" snapshot-version "$artifact.rollback.json")" || return 1
  "$repo/site/worker-deployment.sh" rollback "$artifact/wrangler.json" "$artifact.rollback.json" || rollback_status=$?
  if "$repo/site/worker-deployment.sh" snapshot "$artifact/wrangler.json" "$work/worker-after-rollback.json"; then
    observed="$(node "$repo/site/src/staged-site.mjs" snapshot-version "$work/worker-after-rollback.json")" || observed=""
  fi
  if [[ "$observed" == "$wanted" ]]; then
    echo "deploy: Worker rollback verified: active version $wanted" >&2
    return 0
  fi
  echo "deploy: WORKER ROLLBACK FAILED OR UNVERIFIED (rollback command status $rollback_status). The new site may still be active." >&2
  echo "Inspect Worker: wrangler deployments list --config '$artifact/wrangler.json' --json" >&2
  return 1
}
site_failure() {
  echo "deploy: $1 Restoring the saved Worker version." >&2
  if restore_worker; then
    echo "Guide deployment rolled back. The app release stays live." >&2
  fi
  echo "deploy: app release files and R2 latest.json stay unchanged. Artifact: $artifact" >&2
  echo "Retry site only: site/deploy.sh --deploy-staged '$artifact'" >&2
  exit 1
}
if ! wrangler deploy --config "$artifact/wrangler.json" --env-file /dev/null; then
  site_failure "Worker publish returned an error; activation is uncertain."
fi
video_name="$(printf '%s' "$metadata" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["video"])')"
if ! "$repo/site/smoke.sh" --url "${NEXTSHOT_SITE_URL:-https://nextshot.dev}" --video "$video_name" --guides; then
  site_failure "Guide smoke failed."
fi
echo "Published homepage and Guides from $artifact"
