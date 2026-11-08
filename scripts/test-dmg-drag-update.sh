#!/bin/bash
# Tests the DMG update paths end to end (#88, Drew, 2026-11-07).
#
# It compiles the real install files (LaunchPlan, SingleInstanceGuard,
# DiskImageInstaller, DiskImageWatcher) into a harness app with its own
# bundle ID (com.drewschulz.nextshot.installtest), as build 100 and build 101.
# It signs both with the local Apple Development identity, puts build 101 on a
# disk image, and runs each case with real mounts, a real Finder copy with
# replacing (the same copy engine as a drag), and real Launch Services opens.
# It never touches Nextshot or Nextshot Dev.
#
# Cases:
#   control      build 100 runs without the watcher. Finder refuses to replace it.
#   drag         build 100 runs. The image mounts. A Finder replace succeeds,
#                and build 101 runs from the install place.
#   install      the same, with a click on Install instead of a drag.
#   not-now      a click on Not Now opens build 100 again.
#   same-build   build 101 runs. Its own image mounts. Nothing happens.
#
# Needs: Xcode command line tools, an Apple Development signing identity.
# macOS asks once to let the terminal app control Finder (Automation), and
# for the two button cases, System Events (Accessibility). A button case
# that cannot click reports SKIP. Keep hands off the keyboard while it runs:
# the dialogs take focus, and Return would press Install.
#
# Usage: scripts/test-dmg-drag-update.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID=com.drewschulz.nextshot.installtest
NAME="Nshot Install Test"
EXE=NshotInstallTest
VOLNAME="NshotInstallTest-101"
VOLUME="/Volumes/$VOLNAME"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

WORK="$(cd "$(mktemp -d /tmp/nshot-dmg-test.XXXXXX)" && pwd -P)"
INSTALL_DIR="$WORK/Applications-none" # set per case by reset
INSTALLED="$INSTALL_DIR/$NAME.app"
OLD="$WORK/build-100/$NAME.app"
NEW="$WORK/image/$NAME.app"
DMG="$WORK/new.dmg"
RESULTS=()
FAILED=0

say() { printf '%s\n' "$*"; }

IDENTITY="$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')"
if [ -z "$IDENTITY" ]; then
  say "FAIL: no Apple Development signing identity in the keychain."
  exit 1
fi

# --- Build -----------------------------------------------------------------

write_info() { # $1 app, $2 build number
  cat > "$1/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.$2</string>
  <key>CFBundleVersion</key><string>$2</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
PLIST
}

make_app() { # $1 app path, $2 build number
  mkdir -p "$1/Contents/MacOS"
  cp "$WORK/$EXE" "$1/Contents/MacOS/$EXE"
  write_info "$1" "$2"
  codesign --force --sign "$IDENTITY" --timestamp=none "$1" >/dev/null 2>&1 \
    || { say "FAIL: codesign of build $2"; exit 1; }
}

say "Compiling the harness in $WORK"
swiftc -swift-version 6 -parse-as-library -O -module-name "$EXE" -o "$WORK/$EXE" \
  "$ROOT/App/Feedback/LaunchPlan.swift" \
  "$ROOT/App/Feedback/DiskImageInstaller.swift" \
  "$ROOT/App/Feedback/SingleInstanceGuard.swift" \
  "$ROOT/App/Feedback/DiskImageWatcher.swift" \
  "$ROOT/scripts/dmg-update-harness/Stubs.swift" \
  "$ROOT/scripts/dmg-update-harness/Harness.swift" || { say "FAIL: swiftc"; exit 1; }
make_app "$OLD" 100
make_app "$NEW" 101
hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$WORK/image" -format UDZO -ov "$DMG" \
  || { say "FAIL: hdiutil create"; exit 1; }

# --- Helpers ---------------------------------------------------------------

pids_under() { # PIDs of harness processes whose executable path starts with $1
  local pid
  for pid in $(pgrep -x "$EXE"); do
    case "$(ps -o command= -p "$pid")" in "$1"*) echo "$pid" ;; esac
  done
}
running_from() { [ -n "$(pids_under "$1")" ]; }
not_running_from() { [ -z "$(pids_under "$1")" ]; }
installed_build() { /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INSTALLED/Contents/Info.plist" 2>/dev/null; }
is_mounted() { mount | grep -q " on $VOLUME "; }
not_mounted() { ! is_mounted; }

wait_for() { # $1 seconds, then a command that succeeds when the wait is over
  local end=$((SECONDS + $1)); shift
  while (( SECONDS < end )); do "$@" && return 0; sleep 0.5; done
  "$@"
}

image_running_and_installed_gone() { running_from "$VOLUME/" && not_running_from "$INSTALL_DIR/"; }
installed_runs_build() { [ "$(installed_build)" = "$1" ] && running_from "$INSTALL_DIR/" && not_running_from "$VOLUME/"; }

finder_replace() { # copies the image app over the installed copy, with Finder's copy engine
  osascript - "$NEW_ON_IMAGE" "$INSTALL_DIR" 2>&1 <<'APPLESCRIPT'
on run argv
  tell application "Finder" to duplicate (POSIX file (item 1 of argv) as alias) to (POSIX file (item 2 of argv) as alias) with replacing
end run
APPLESCRIPT
}
NEW_ON_IMAGE="$VOLUME/$NAME.app"

click_button() { # $1 PID, $2 button title
  osascript - "$1" "$2" 2>&1 <<'APPLESCRIPT'
on run argv
  tell application "System Events"
    set p to first process whose unix id is ((item 1 of argv) as integer)
    click button (item 2 of argv) of window 1 of p
  end tell
end run
APPLESCRIPT
}

# Each case gets a new install folder. Finder keeps its own view of a folder.
# After a shell `rm` and `ditto` in a folder that Finder already copied into,
# Finder's replace failed with -48 ("already an item with that name"), with no
# harness running (2026-11-07). A real drag into /Applications has no such step.
reset() { # $1 build to install (100 or 101), $2 case name
  pkill -x "$EXE" 2>/dev/null
  wait_for 10 not_running_from / >/dev/null
  is_mounted && hdiutil detach -quiet -force "$VOLUME"
  INSTALL_DIR="$WORK/Applications-$2"
  INSTALLED="$INSTALL_DIR/$NAME.app"
  mkdir -p "$INSTALL_DIR"
  if [ "$1" = 101 ]; then ditto "$NEW" "$INSTALLED"; else ditto "$OLD" "$INSTALLED"; fi
}

start_installed() { # extra arguments go to the app
  open -n "$INSTALLED" --args "$@"
  wait_for 10 running_from "$INSTALL_DIR/" || return 1
  sleep 3 # the launch-time eject runs 2 seconds after launch
}

mount_image() { hdiutil attach -quiet "$DMG" && wait_for 10 is_mounted; }

record() { # $1 case, $2 PASS, FAIL, or SKIP, $3 evidence
  RESULTS+=("$2  $1: $3")
  [ "$2" = FAIL ] && FAILED=1
  say "$2  $1: $3"
}

# --- Cases -----------------------------------------------------------------

case_control() {
  reset 100 control
  start_installed --no-watch || { record control FAIL "build 100 did not start"; return; }
  mount_image || { record control FAIL "the image did not mount"; return; }
  sleep 3
  local out; out="$(finder_replace)"
  if running_from "$INSTALL_DIR/" && [ "$(installed_build)" = 100 ] && [[ "$out" == *"-8087"* || "$out" == *"in use"* || "$out" == *"error"* ]]; then
    record control PASS "Finder refused while build 100 ran (${out##*: })"
  else
    record control FAIL "Finder output: $out, installed build $(installed_build)"
  fi
}

case_drag() {
  reset 100 drag
  start_installed || { record drag FAIL "build 100 did not start"; return; }
  mount_image || { record drag FAIL "the image did not mount"; return; }
  if ! wait_for 20 image_running_and_installed_gone; then
    record drag FAIL "no hand-off: the image copy did not start, or build 100 did not quit"; return
  fi
  local out; out="$(finder_replace)"
  if [[ "$out" == *"error"* ]]; then record drag FAIL "Finder: $out"; return; fi
  if ! wait_for 20 installed_runs_build 101; then
    record drag FAIL "after the drag: installed build $(installed_build), image copy running: $(pids_under "$VOLUME/")"; return
  fi
  if wait_for 15 not_mounted; then
    record drag PASS "Finder replaced it, build 101 runs from the install place, image ejected"
  else
    record drag FAIL "build 101 runs, but the image stayed mounted"
  fi
}

case_button() { # $1 case name, $2 button, $3 build expected after
  reset 100 "$1"
  start_installed || { record "$1" FAIL "build 100 did not start"; return; }
  mount_image || { record "$1" FAIL "the image did not mount"; return; }
  if ! wait_for 20 image_running_and_installed_gone; then
    record "$1" FAIL "no hand-off"; return
  fi
  sleep 1
  local pid out; pid="$(pids_under "$VOLUME/" | head -1)"
  out="$(click_button "$pid" "$2")"
  if [[ "$out" == *"error"* || "$out" == *"not allowed"* ]]; then
    record "$1" SKIP "could not click $2 (grant Accessibility to the terminal app): $out"; return
  fi
  if ! wait_for 20 installed_runs_build "$3"; then
    record "$1" FAIL "after $2: installed build $(installed_build)"; return
  fi
  if wait_for 15 not_mounted; then
    record "$1" PASS "$2 left build $3 running from the install place, image ejected"
  else
    record "$1" FAIL "build $3 runs, but the image stayed mounted"
  fi
}

case_same_build() {
  reset 101 same-build
  start_installed || { record same-build FAIL "build 101 did not start"; return; }
  local before; before="$(pids_under "$INSTALL_DIR/")"
  mount_image || { record same-build FAIL "the image did not mount"; return; }
  sleep 6
  if [ "$(pids_under "$INSTALL_DIR/")" = "$before" ] && not_running_from "$VOLUME/"; then
    record same-build PASS "build 101 kept running (pid $before), no hand-off"
  else
    record same-build FAIL "the running copy changed or the image copy started"
  fi
}

cleanup() {
  pkill -x "$EXE" 2>/dev/null
  is_mounted && hdiutil detach -quiet -force "$VOLUME"
  local app
  for app in "$WORK"/Applications-*/"$NAME.app" "$OLD" "$NEW"; do
    [ -d "$app" ] && "$LSREGISTER" -u "$app" >/dev/null 2>&1
  done
  if [ "${KEEP_WORK:-0}" = 1 ]; then say "Kept $WORK"; else rm -rf "$WORK"; fi
}
trap cleanup EXIT

# ONLY=<case> runs one case. KEEP_WORK=1 keeps the build folder.
only="${ONLY:-all}"
[[ "$only" == all || "$only" == control ]] && case_control
[[ "$only" == all || "$only" == drag ]] && case_drag
[[ "$only" == all || "$only" == install ]] && case_button install Install 101
[[ "$only" == all || "$only" == not-now ]] && case_button not-now "Not Now" 100
[[ "$only" == all || "$only" == same-build ]] && case_same_build

say ""
say "Summary"
for line in ${RESULTS[@]+"${RESULTS[@]}"}; do say "  $line"; done
exit "$FAILED"
