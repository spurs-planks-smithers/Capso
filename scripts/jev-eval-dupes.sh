#!/bin/bash
# Fork: runs the duplicates and conflicts live evaluation against TypeSafe
# with Nextshot's own key (#39, #58, #60). The plan is
# docs/superpowers/plans/2026-10-24-dupes-conflicts-test-plan.md, Part A.
#
# It reads the Keychain item TYPESAFE_API_KEY_NEXTSHOT (store it with
# keychain-store.sh), passes it to the test process only, and never prints it.
# The test calls a paid API: one request for each labeled pair, arm, and run.
#
# What it sends: made-up screens and notes (the labeled pairs in
# Packages/JevKit/Tests/Fixtures/dupes-eval), plus the notes of two
# real pairs from Drew's rounds. It never sends their images. It reads those
# rounds in ~/Library/Application Support/Nextshot and writes nothing there.
#
# It writes results.json and report.md in the output folder, which is
# build/jev-eval/<YYYYmmdd-HHMMSS> under the repository unless you name one.
#
# Usage: scripts/jev-eval-dupes.sh [output-folder]
set -euo pipefail

# A relative output folder means relative to where you ran the script.
start="$PWD"
cd "$(dirname "$0")/.."

if ! key="$(security find-generic-password -a "$USER" -s TYPESAFE_API_KEY_NEXTSHOT -w 2>/dev/null)"; then
  echo "No Keychain item TYPESAFE_API_KEY_NEXTSHOT. Store it first:" >&2
  echo "  bash ~/.dotfiles/claude-code/bin/keychain-store.sh TYPESAFE_API_KEY_NEXTSHOT" >&2
  exit 1
fi

if [ $# -ge 1 ] && [ -n "$1" ]; then
  case "$1" in
    /*) out="$1" ;;
    *) out="$start/$1" ;;
  esac
else
  out="$PWD/build/jev-eval/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$out"

status=0
NEXTSHOT_JEV_EVAL=1 TYPESAFE_API_KEY="$key" NEXTSHOT_JEV_EVAL_OUT="$out" \
  swift test --package-path Packages/JevKit --filter DupesConflictsLiveEval || status=$?

echo "Output folder: $out"
exit "$status"
