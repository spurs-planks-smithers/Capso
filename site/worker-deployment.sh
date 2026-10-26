#!/bin/bash
# Record or restore one verified Worker deployment. Never edit R2.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
command="$1" config="$2" snapshot="$3"
case "$command" in
  snapshot)
    raw="$(mktemp)"
    trap 'rm -f "$raw"' EXIT
    wrangler deployments list --config "$config" --env-file /dev/null --json >"$raw"
    node "$repo/site/src/staged-site.mjs" snapshot "$raw" >"$snapshot"
    ;;
  rollback)
    version="$(node "$repo/site/src/staged-site.mjs" snapshot-version "$snapshot")"
    wrangler rollback "$version" --config "$config" --env-file /dev/null --yes --message "Restore verified Worker after Guides smoke failure"
    ;;
  *) echo "Use snapshot or rollback" >&2; exit 2 ;;
esac
