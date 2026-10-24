#!/bin/bash
# Fork: runs JevKit's one live test against TypeSafe with Nextshot's own key.
#
# It reads the Keychain item TYPESAFE_API_KEY_NEXTSHOT (store it with
# keychain-store.sh), passes it to the test process only, and never prints it.
# The test sends made-up text only.
#
# Usage: scripts/jev-live-test.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if ! key="$(security find-generic-password -a "$USER" -s TYPESAFE_API_KEY_NEXTSHOT -w 2>/dev/null)"; then
  echo "No Keychain item TYPESAFE_API_KEY_NEXTSHOT. Store it first:" >&2
  echo "  bash ~/.dotfiles/claude-code/bin/keychain-store.sh TYPESAFE_API_KEY_NEXTSHOT" >&2
  exit 1
fi

NEXTSHOT_JEV_LIVE=1 TYPESAFE_API_KEY="$key" swift test --package-path Packages/JevKit --filter JevLiveTests
