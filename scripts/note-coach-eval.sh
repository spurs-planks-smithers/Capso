#!/bin/bash
# Fork: measures the note coach's accuracy against TypeSafe with Nextshot's own key.
#
# It sends reviewer note text, text only, to TypeSafe, which keeps each request.
# Drew approved this on 2026-10-24 (issue #62). It reads the Keychain item
# TYPESAFE_API_KEY_NEXTSHOT (store it with keychain-store.sh), passes it to the
# test process only, and never prints it.
#
# The set file holds real notes, so it must sit outside the repository's tracked
# files, for example in the git-ignored build/jev-eval/. The results file
# note-coach-results.json lands next to the set file. It holds labels and
# numbers, never note text.
#
# Usage: scripts/note-coach-eval.sh <path to note-coach-set.json>
set -euo pipefail

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "Usage: scripts/note-coach-eval.sh <path to note-coach-set.json>" >&2
  exit 1
fi
abs="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

cd "$(dirname "$0")/.."

if ! key="$(security find-generic-password -a "$USER" -s TYPESAFE_API_KEY_NEXTSHOT -w 2>/dev/null)"; then
  echo "No Keychain item TYPESAFE_API_KEY_NEXTSHOT. Store it first:" >&2
  echo "  bash ~/.dotfiles/claude-code/bin/keychain-store.sh TYPESAFE_API_KEY_NEXTSHOT" >&2
  exit 1
fi

NEXTSHOT_NOTE_COACH_EVAL="$abs" TYPESAFE_API_KEY="$key" swift test --package-path Packages/JevKit --filter NoteCoachAccuracyTests
