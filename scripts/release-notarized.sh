#!/bin/bash
# Fork: build a notarized Nextshot.app that installs on another Mac.
#
# Signs with the Developer ID Application certificate in the login keychain,
# with hardened runtime and a secure timestamp. Sends the app to Apple's
# notary service through the keychain profile that
# `xcrun notarytool store-credentials` made, and staples the ticket. Then it
# packs the app with Capso's LICENSE as a disk image (also notarized) and a
# zip. The license is also inside the app (Resources/LICENSE.txt). The stapled
# ticket lets Gatekeeper accept the app with no network. Needs create-dmg
# (brew install create-dmg).
#
# The steps follow upstream's .github/workflows/build-release.yml. The name
# and bundle ID come from scripts/local-project.yml. DEVELOPMENT_TEAM comes
# from scripts/local-signing.env, which git ignores.
#
# Usage: scripts/release-notarized.sh [keychain-profile]   (default: apple-notary)
# Output: build/releases/Nextshot-<version>-<commit>.dmg and .zip
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

if ! command -v create-dmg >/dev/null; then
  echo "create-dmg is missing. Install it: brew install create-dmg" >&2
  exit 1
fi

commit="$(git -C "$repo" rev-parse --short HEAD)"
if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
  commit="$commit-dirty"
fi

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
name="$product_name-$version-$commit"
stem="$repo/build/releases/$name"

# The stapled app with the license next to it, for the DMG and the zip.
stage="$work/$name"
mkdir -p "$stage"
ditto "$app" "$stage/$product_name.app"
cp "$repo/LICENSE" "$stage/LICENSE.txt"

# 5. A zip of that folder, as a fallback.
rm -f "$stem.zip"
ditto -c -k --keepParent "$stage" "$stem.zip"

# 6. A disk image with a link to Applications, signed, notarized, and
# stapled too, so Gatekeeper accepts the image itself. create-dmg copies the
# folder's contents: the app and the license.
rm -f "$stem.dmg"
create-dmg \
  --volname "$product_name" \
  --window-pos 200 120 \
  --window-size 660 460 \
  --icon-size 128 \
  --icon "$product_name.app" 180 170 \
  --app-drop-link 480 170 \
  --icon LICENSE.txt 330 330 \
  --hide-extension "$product_name.app" \
  "$stem.dmg" \
  "$stage"
codesign --force --sign "$sign_id" --timestamp "$stem.dmg"
notarize "$stem.dmg"
staple "$stem.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$stem.dmg"

shasum -a 256 "$stem.dmg" "$stem.zip"
echo "Notarized and stapled: $stem.dmg (and $stem.zip)"
