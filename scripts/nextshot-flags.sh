#!/bin/bash
# Fork: list, set, and clear Nextshot's local feature flag overrides.
#
# An override is a UserDefaults string named flag.<flag>. Nextshot reads it
# before the build channel's default (see FeatureFlags.swift in FeedbackKit).
# The app ignores an override that names a state the flag does not allow.
# App capability changes require a normal quit and reopen. Optional recording,
# translation, cloud sharing, and URL automation also need standaloneCapture on.
#
# Usage: scripts/nextshot-flags.sh list
#        scripts/nextshot-flags.sh set <flag> <state>
#        scripts/nextshot-flags.sh reset <flag>
#        scripts/nextshot-flags.sh feature <parent> <state>
#        scripts/nextshot-flags.sh feature <parent> reset
#
# A feature flag can have sub-flags (see SUBFLAGS below). A sub-flag runs at
# the lower of its own state and its parent's state, so a trial needs both.
# "feature" sets the parent and every sub-flag in one step, or removes all
# their overrides.
#
# The script edits the settings of Nextshot Dev (com.drewschulz.nextshot.dev),
# the copy Drew runs every day. The Jev flags are dev-only, so they run only
# there (docs/decisions/2026-10-25-versioning-and-releases.md).
#
# NEXTSHOT_FLAGS_DOMAIN replaces the defaults domain. Use it to try the script
# without touching the real overrides, or to set a flag for the production app
# with NEXTSHOT_FLAGS_DOMAIN=com.drewschulz.nextshot.
set -euo pipefail

domain="${NEXTSHOT_FLAGS_DOMAIN:-com.drewschulz.nextshot.dev}"

# One entry per flag: <flag>:<allowed states>. Keep this line in step with
# FeatureFlag in Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift.
# FeatureFlagsTests fails when the two differ.
FLAGS="jevBase:off,on noteCoach:off,shadow,on noteCoachVague:off,shadow,on noteCoachQuestion:off,shadow,on noteCoachEmpty:off,shadow,on cropsAnchors:off,shadow,on cropsItemCrops:off,shadow,on cropsSearchLines:off,shadow,on dupesConflicts:off,shadow,on dupesMerge:off,shadow,on dupesConflict:off,shadow,on oneBreath:off promptLanes:off,shadow,on lanesOrder:off,shadow,on lanesSplit:off,shadow,on dataGuard:off,shadow,on dataGuardInjection:off,shadow,on dataGuardContact:off,shadow,on dataGuardNumbers:off,shadow,on dataGuardSecrets:off,shadow,on dataGuardFaces:off,shadow,on jevSendImages:off,on jevSendScreenText:off,on zipHandoff:off,on supportSubmission:off,on standaloneCapture:off,on recordingTools:off,on translationTools:off,on cloudShare:off,on automationURLs:off,on automaticUpdates:off,on screenshotCopy:off,on diagnostics:off,on sessionTitle:off,on"


# Settings visibility flags come from the typed registry. Unknown paths fail closed.
settings_registry="$(cd "$(dirname "$0")/.." && pwd)/Packages/FeedbackKit/Sources/FeedbackKit/SettingsVisibilityFlag.swift"
settings_flags="$(sed -nE 's/^[[:space:]]*case [[:alnum:]]+ = "([^"]+)"$/settingsVisibility.\1:off,on/p' "$settings_registry")"
[[ -n "$settings_flags" ]] || { echo "Settings visibility registry is empty." >&2; exit 1; }
ALL_FLAGS="$FLAGS $settings_flags"

# One entry per feature flag that has sub-flags: <parent>:<sub-flags>. A
# sub-flag runs at the lower of its own state and its parent's state, so it
# runs nothing alone (#94). FeatureFlagsTests compares this line with the
# parents in the registry.
SUBFLAGS="noteCoach:noteCoachVague,noteCoachQuestion,noteCoachEmpty cropsAnchors:cropsItemCrops,cropsSearchLines dupesConflicts:dupesMerge,dupesConflict promptLanes:lanesOrder,lanesSplit dataGuard:dataGuardInjection,dataGuardContact,dataGuardNumbers,dataGuardSecrets,dataGuardFaces"

usage() {
  echo "Usage: $0 list | set <flag> <state> | reset <flag> | feature <parent> <state|reset>" >&2
  exit 2
}

# Prints the allowed states of a flag, comma separated. Fails for an unknown flag.
allowed_states() {
  # Custom preset identifiers come from CapturePreset.id. Refuse all other paths.
  if [[ "$1" =~ ^settingsVisibility\.screenshots\.capturePresets\.customPreset\.instance\.(ratio|fixed)-[0-9]+-[0-9]+$ ]]; then
    echo "off,on"
    return 0
  fi
  local entry
  for entry in $ALL_FLAGS; do
    if [[ "${entry%%:*}" == "$1" ]]; then
      echo "${entry#*:}"
      return 0
    fi
  done
  return 1
}

# Prints the sub-flags of a feature flag, comma separated. Fails for a flag
# with no sub-flags.
sub_flags() {
  local entry
  for entry in $SUBFLAGS; do
    if [[ "${entry%%:*}" == "$1" ]]; then
      echo "${entry#*:}"
      return 0
    fi
  done
  return 1
}

# Prints the parent of a sub-flag. Fails for any other flag.
parent_of() {
  local entry
  for entry in $SUBFLAGS; do
    if [[ ",${entry#*:}," == *",$1,"* ]]; then
      echo "${entry%%:*}"
      return 0
    fi
  done
  return 1
}

# Prints the stored override of a flag, or nothing when there is none.
stored_override() {
  defaults read "$domain" "flag.$1" 2>/dev/null || true
}

# Removes the stored override of a flag.
clear_override() {
  if [[ -n "$(stored_override "$1")" ]]; then
    defaults delete "$domain" "flag.$1"
    echo "Removed the override for flag.$1."
  else
    echo "flag.$1 has no override."
  fi
}

remind() {
  echo "Nextshot reads the change at its next check. If unsure, relaunch Nextshot."
}

command="${1:-}"
case "$command" in
  list)
    printf '%-20s %-18s %s\n' "Flag" "Override" "Allowed states"
    custom_overrides="$(defaults read "$domain" 2>/dev/null | sed -nE 's/^[[:space:]]*"flag\.(settingsVisibility\.screenshots\.capturePresets\.customPreset\.instance\.(ratio|fixed)-[0-9]+-[0-9]+)".*/\1:off,on/p' || true)"
    for entry in $ALL_FLAGS $custom_overrides; do
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
      # A sub-flag sits under its parent, indented.
      label="$name"
      if parent_of "$name" >/dev/null; then
        label="  $name"
      fi
      printf '%-20s %-18s %s\n' "$label" "$shown" "${allowed//,/, }"
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
    clear_override "$flag"
    remind
    ;;
  feature)
    [[ $# -eq 3 ]] || usage
    parent="$2"
    state="$3"
    if ! allowed_states "$parent" >/dev/null; then
      echo "Unknown flag '$parent'. Run '$0 list' to see the flags." >&2
      exit 1
    fi
    if ! subs="$(sub_flags "$parent")"; then
      echo "Flag '$parent' has no sub-flags. Use 'set' or 'reset' for it." >&2
      exit 1
    fi
    members="$parent ${subs//,/ }"
    if [[ "$state" == "reset" ]]; then
      for flag in $members; do
        clear_override "$flag"
      done
    else
      # Check every flag before writing any, so a refusal leaves no partial change.
      for flag in $members; do
        allowed="$(allowed_states "$flag")"
        if [[ ",$allowed," != *",$state,"* ]]; then
          echo "Flag '$flag' does not allow '$state'. Allowed: ${allowed//,/, }." >&2
          exit 1
        fi
      done
      for flag in $members; do
        defaults write "$domain" "flag.$flag" -string "$state"
        echo "Set flag.$flag to $state."
      done
    fi
    remind
    ;;
  *)
    usage
    ;;
esac
