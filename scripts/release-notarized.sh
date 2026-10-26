#!/bin/bash
# Fork: build a notarized Nextshot.app that installs on another Mac.
#
# Signs with the Developer ID Application certificate in the login keychain,
# with hardened runtime and a secure timestamp. Sends the app to Apple's
# notary service through the keychain profile that
# `xcrun notarytool store-credentials` made, and staples the ticket. Then it
# packs the app as a disk image (also notarized) and a zip. Capso's license
# ships inside the app (Resources/LICENSE.txt), not beside it (Drew,
# 2026-10-25). The stapled ticket lets Gatekeeper accept the app with no
# network. The disk image comes from dmgbuild, which the script installs into
# build/tools/dmgbuild on first use (needs python3).
#
# The steps follow upstream's .github/workflows/build-release.yml. The name
# and bundle ID come from scripts/local-project.yml. DEVELOPMENT_TEAM comes
# from scripts/local-signing.env, which git ignores.
#
# The version comes from the VERSION file (scripts/nextshot-version.sh). Edit
# it in a `chore: release X.Y.Z` commit before this script runs. The script
# stops when build/releases already holds that version.
#
# Usage: scripts/release-notarized.sh [keychain-profile]   (default: apple-notary)
# Output: build/releases/Nextshot-<version>.dmg and .zip (plus -dirty after
#         the version when the tree has uncommitted changes)
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
profile="${1:-apple-notary}"
env_file="$repo/scripts/local-signing.env"
product_name="Nextshot"
sign_id="Developer ID Application"
work="$repo/build/release"
archive="$work/$product_name.xcarchive"
app="$work/export/$product_name.app"

if [[ ! -f "$env_file" ]]; then
  echo "Missing $env_file. Create it with one line: DEVELOPMENT_TEAM=<your team ID>" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$env_file"
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM in $env_file}"

# Stop before the long build when a credential is missing.
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application: .*($DEVELOPMENT_TEAM)"; then
  echo "No Developer ID Application certificate for team $DEVELOPMENT_TEAM in the keychain." >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  echo "Notary profile '$profile' is missing or rejected. Create it in your own terminal:" >&2
  echo "  xcrun notarytool store-credentials $profile --apple-id <developer Apple ID> --team-id $DEVELOPMENT_TEAM" >&2
  exit 1
fi

# dmgbuild writes the Finder view settings itself. create-dmg scripted Finder,
# and lost the background on a Mac where Finder opens windows as tabs.
dmgbuild_version="1.6.7"
dmgbuild="$repo/build/tools/dmgbuild/bin/dmgbuild"
if ! "$repo/build/tools/dmgbuild/bin/pip" show dmgbuild 2>/dev/null | grep -qx "Version: $dmgbuild_version"; then
  python3 -m venv "$repo/build/tools/dmgbuild"
  "$repo/build/tools/dmgbuild/bin/pip" install --quiet "dmgbuild==$dmgbuild_version"
fi

commit="$(git -C "$repo" rev-parse --short HEAD)"
dirty=""
if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
  dirty="-dirty"
fi
# A release build shows the VERSION file as it is, with no -dev suffix.
nextshot_channel=release
# shellcheck source=scripts/nextshot-version.sh
source "$repo/scripts/nextshot-version.sh"

# The file name holds the version and nothing else (docs/decisions/
# 2026-10-25-versioning-and-releases.md). Nobody replaces a published file, so
# the script stops when this version already has a DMG. Fix a bad build with a
# new PATCH number, or move the old files away on purpose.
name="$product_name-$nextshot_version$dirty"
stem="$repo/build/releases/$name"
for existing in "$stem.dmg" "$stem.zip"; do
  if [[ -e "$existing" ]]; then
    echo "$existing already exists. Raise VERSION, or move the old files away." >&2
    exit 1
  fi
done

rm -rf "$work"
mkdir -p "$work/export" "$repo/build/releases"
cd "$repo"

# 1. Archive. A generic macOS destination gives arm64 and x86_64 slices.
xcodegen generate --spec scripts/local-project.yml --project "$repo" --project-root "$repo"
xcodebuild archive \
  -project "$repo/CapsoLocal.xcodeproj" \
  -scheme Capso \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$archive" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$sign_id" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  MARKETING_VERSION="$nextshot_version" \
  CURRENT_PROJECT_VERSION="$nextshot_build" \
  ENABLE_HARDENED_RUNTIME=YES \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  -quiet
ditto "$archive/Products/Applications/$product_name.app" "$app"
lipo -info "$app/Contents/MacOS/$product_name"

# 2. Re-sign Sparkle from the inside out: executables, XPC services,
# Updater.app, the framework. The Swift package ships it with another
# signature, which the notary service rejects.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle" ]]; then
  find "$sparkle" -type f -perm +111 \( -name Autoupdate -o -name Updater -o -name Downloader -o -name Installer \) -print0 |
    while IFS= read -r -d '' binary; do
      codesign --force --sign "$sign_id" --options runtime --timestamp "$binary"
    done
  find "$sparkle" -name "*.xpc" -type d -print0 |
    while IFS= read -r -d '' xpc; do
      codesign --force --sign "$sign_id" --options runtime --timestamp "$xpc"
    done
  find "$sparkle" -name Updater.app -type d -print0 |
    while IFS= read -r -d '' updater; do
      codesign --force --sign "$sign_id" --options runtime --timestamp "$updater"
    done
  codesign --force --sign "$sign_id" --options runtime --timestamp "$sparkle"
fi

# 3. Capso's Business Source License must be shown on each modified copy,
# so it goes inside the app before the app's own signature seals it.
cp "$repo/LICENSE" "$app/Contents/Resources/LICENSE.txt"

# Re-sign the app last, with its entitlements, then check it.
codesign --force --sign "$sign_id" --options runtime --timestamp \
  --entitlements "$repo/App/Entitlements/Capso.entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

# Sends a file to Apple's notary service and waits, usually a few minutes.
# On any status but Accepted, prints Apple's log and stops the script.
notarize() {
  local file="$1" result="$work/notary-$(basename "$1").json"
  xcrun notarytool submit "$file" --keychain-profile "$profile" --wait \
    --output-format json > "$result" || true
  local status submission_id
  status="$(plutil -extract status raw "$result" 2>/dev/null || echo unknown)"
  submission_id="$(plutil -extract id raw "$result" 2>/dev/null || echo unknown)"
  echo "Notary status for $(basename "$file"): $status (submission $submission_id)"
  if [[ "$status" != "Accepted" ]]; then
    if [[ "$submission_id" != "unknown" ]]; then
      xcrun notarytool log "$submission_id" --keychain-profile "$profile" || true
    fi
    exit 1
  fi
}

# Staples the ticket to a file. Apple's servers can lag the Accepted status.
staple() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if xcrun stapler staple "$1"; then
      xcrun stapler validate "$1"
      return
    fi
    echo "Staple attempt $attempt failed. Retrying in 15 seconds." >&2
    sleep 15
  done
  exit 1
}

# 4. Notarize and staple the app.
submission="$work/$product_name-notarize.zip"
ditto -c -k --keepParent "$app" "$submission"
notarize "$submission"
staple "$app"
spctl --assess --type execute --verbose=2 "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
if [[ "$version" != "$nextshot_version" ]]; then
  echo "The built app says $version, not $nextshot_version from VERSION." >&2
  exit 1
fi

# The stapled app alone, for the DMG and the zip. The license is inside it.
stage="$work/$name"
mkdir -p "$stage"
ditto "$app" "$stage/$product_name.app"

# The files are built under $work and move to build/releases only when every
# step has passed, so a failed run leaves no half-made release behind.
built="$work/out/$name"
mkdir -p "$work/out"

# 5. A zip of that folder, as a fallback.
ditto -c -k --keepParent "$stage" "$built.zip"

# 6. A disk image with a link to Applications, signed, notarized, and
# stapled too, so Gatekeeper accepts the image itself. The volume name holds
# the version, as the top row of the Nshot menu does, so Finder's sidebar
# tells images apart. The background says to drag, and how to update.
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
background="$work/dmg-background.tiff"
swift "$repo/scripts/brand/make_dmg_background.swift" "$background"
"$dmgbuild" \
  -s "$repo/scripts/dmg-settings.py" \
  -D app="$stage/$product_name.app" \
  -D background="$background" \
  "$product_name $version ($build)" \
  "$built.dmg"
codesign --force --sign "$sign_id" --timestamp "$built.dmg"
notarize "$built.dmg"
staple "$built.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$built.dmg"

# 7. Publish to build/releases. mv -n refuses to replace a file that appeared
# since the check at the top.
mv -n "$built.dmg" "$stem.dmg"
mv -n "$built.zip" "$stem.zip"
[[ -f "$stem.dmg" && -f "$stem.zip" && ! -e "$built.dmg" && ! -e "$built.zip" ]] || {
  echo "A file in build/releases changed during the build. Nothing was replaced." >&2
  exit 1
}

shasum -a 256 "$stem.dmg" "$stem.zip"
echo "Notarized and stapled: $stem.dmg (and $stem.zip), built from $commit$dirty"
