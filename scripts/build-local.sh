#!/bin/bash
# Fork: build Nextshot (this fork of Capso) with Apple Development signing
# under its own bundle ID and app name, then install it to ~/Applications.
#
# scripts/local-project.yml sets the bundle ID, app name, and signing style on
# the Capso target only. Command-line PRODUCT_NAME would rename every package
# resource bundle too. It generates CapsoLocal.xcodeproj, so the upstream
# Capso.xcodeproj stays as it is.
#
# Reads DEVELOPMENT_TEAM from scripts/local-signing.env, which git ignores.
#
# Usage: scripts/build-local.sh [Release|Debug]
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
config="${1:-Release}"
env_file="$repo/scripts/local-signing.env"

if [[ ! -f "$env_file" ]]; then
  echo "Missing $env_file. Create it with one line: DEVELOPMENT_TEAM=<your team ID>" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$env_file"
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM in $env_file}"

bundle_id="com.drewschulz.nextshot"
product_name="Nextshot"
derived="$repo/build/local"
# shellcheck source=scripts/nextshot-version.sh
source "$repo/scripts/nextshot-version.sh"

cd "$repo"
xcodegen generate --spec scripts/local-project.yml --project "$repo" --project-root "$repo"
xcodebuild -project "$repo/CapsoLocal.xcodeproj" -scheme Capso -configuration "$config" \
  -derivedDataPath "$derived/DerivedData" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  MARKETING_VERSION="$nextshot_version" \
  CURRENT_PROJECT_VERSION="$nextshot_build" \
  build

app="$derived/DerivedData/Build/Products/$config/$product_name.app"
dest="$HOME/Applications/$product_name.app"
mkdir -p "$HOME/Applications"

# Replace only an earlier build of this same app.
if [[ -d "$dest" ]]; then
  installed_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$dest/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$installed_id" != "$bundle_id" ]]; then
    echo "$dest exists with bundle ID '$installed_id', not '$bundle_id'. Not replacing it." >&2
    exit 1
  fi
  rm -rf "$dest"
fi

ditto "$app" "$dest"
codesign --verify --deep --strict "$dest"
echo "Installed $dest ($bundle_id)"
