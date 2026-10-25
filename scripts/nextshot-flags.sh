#!/bin/bash
# Fork: list, set, and clear Nextshot's local feature flag overrides.
#
# An override is a UserDefaults string named flag.<flag>. Nextshot reads it
# before the build channel's default (see FeatureFlags.swift in FeedbackKit).
# The app ignores an override that names a state the flag does not allow.
#
# Usage: scripts/nextshot-flags.sh list
#        scripts/nextshot-flags.sh set <flag> <state>
#        scripts/nextshot-flags.sh reset <flag>
#
# NEXTSHOT_FLAGS_DOMAIN replaces the defaults domain. Use it to try the script
# without touching the real overrides.
set -euo pipefail

domain="${NEXTSHOT_FLAGS_DOMAIN:-com.drewschulz.nextshot}"

# One entry per flag: <flag>:<allowed states>. Keep this line in step with
# FeatureFlag in Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift.
# FeatureFlagsTests fails when the two differ.
FLAGS="jevBase:off,on noteCoach:off,shadow,on cropsAnchors:off,shadow,on dupesConflicts:off,shadow,on oneBreath:off promptLanes:off,shadow,on dataGuard:off,shadow,on jevSendImages:off,on jevSendScreenText:off,on zipHandoff:off,on"

usage() {
  echo "Usage: $0 list | set <flag> <state> | reset <flag>" >&2
  exit 2
}

# Prints the allowed states of a flag, comma separated. Fails for an unknown flag.
allowed_states() {
  local entry
  for entry in $FLAGS; do
    if [[ "${entry%%:*}" == "$1" ]]; then
      echo "${entry#*:}"
      return 0
    fi
  done
  return 1
}

# Prints the stored override of a flag, or nothing when there is none.
stored_override() {
  defaults read "$domain" "flag.$1" 2>/dev/null || true
}

remind() {
  echo "Nextshot reads the change at its next check. If unsure, relaunch Nextshot."
}

command="${1:-}"
case "$command" in
  list)
    printf '%-16s %-18s %s\n' "Flag" "Override" "Allowed states"
    for entry in $FLAGS; do
      name="${entry%%:*}"
      allowed="${entry#*:}"
      value="$(stored_override "$name")"
      if [[ -z "$value" ]]; then
        shown="none"
      elif [[ ",$allowed," == *",$value,"* ]]; then
        shown="$value"
      else
        shown="$value (ignored)"
      fi
      printf '%-16s %-18s %s\n' "$name" "$shown" "${allowed//,/, }"
    done
    ;;
  set)
    [[ $# -eq 3 ]] || usage
    flag="$2"
    state="$3"
    if ! allowed="$(allowed_states "$flag")"; then
      echo "Unknown flag '$flag'. Run '$0 list' to see the flags." >&2
      exit 1
    fi
    if [[ ",$allowed," != *",$state,"* ]]; then
      echo "Flag '$flag' does not allow '$state'. Allowed: ${allowed//,/, }." >&2
      exit 1
    fi
    defaults write "$domain" "flag.$flag" -string "$state"
    echo "Set flag.$flag to $state."
    remind
    ;;
  reset)
    [[ $# -eq 2 ]] || usage
    flag="$2"
    if ! allowed_states "$flag" >/dev/null; then
      echo "Unknown flag '$flag'. Run '$0 list' to see the flags." >&2
      exit 1
    fi
    if [[ -n "$(stored_override "$flag")" ]]; then
      defaults delete "$domain" "flag.$flag"
      echo "Removed the override for flag.$flag."
    else
      echo "flag.$flag has no override."
    fi
    remind
    ;;
  *)
    usage
    ;;
esac
