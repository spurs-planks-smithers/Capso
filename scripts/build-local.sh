#!/bin/bash
# Fork: build Nextshot Dev, the copy Drew runs every day, with Apple
# Development signing under its own bundle ID (com.drewschulz.nextshot.dev)
# and app name, then install it to ~/Applications/Nextshot Dev.app.
#
# The production app is a different app: Nextshot, com.drewschulz.nextshot,
# made by scripts/release-notarized.sh. Because the IDs differ, a build here
# never replaces the production copy, keeps its own screen recording grant,
# and the production installer never quits it
# (docs/decisions/2026-10-25-versioning-and-releases.md).
#
# scripts/dev-project.yml sets the bundle ID, app name, and signing style on
# the Capso target only. Command-line PRODUCT_NAME would rename every package
# resource bundle too. It generates CapsoDev.xcodeproj, so the upstream
# Capso.xcodeproj stays as it is.
#
# Reads DEVELOPMENT_TEAM from scripts/local-signing.env, which git ignores.
#
# Usage: scripts/build-local.sh [Release|Debug] [--no-install]
#   --no-install  build and check the app, but leave ~/Applications alone
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
config="Release"
install=1
for arg in "$@"; do
  case "$arg" in
    Release|Debug) config="$arg" ;;
    --no-install) install=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done
env_file="$repo/scripts/local-signing.env"

if [[ ! -f "$env_file" ]]; then
  echo "Missing $env_file. Create it with one line: DEVELOPMENT_TEAM=<your team ID>" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$env_file"
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM in $env_file}"

bundle_id="com.drewschulz.nextshot.dev"
product_name="Nextshot Dev"
derived="$repo/build/local"
# A dev build shows the VERSION file plus -dev, for example 0.3.0-dev.
nextshot_channel=dev
# shellcheck source=scripts/nextshot-version.sh
source "$repo/scripts/nextshot-version.sh"

cd "$repo"
xcodegen generate --spec scripts/dev-project.yml --project "$repo" --project-root "$repo"
xcodebuild -project "$repo/CapsoDev.xcodeproj" -scheme Capso -configuration "$config" \
  -derivedDataPath "$derived/DerivedData" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  MARKETING_VERSION="$nextshot_version" \
  CURRENT_PROJECT_VERSION="$nextshot_build" \
  build

app="$derived/DerivedData/Build/Products/$config/$product_name.app"
codesign --verify --deep --strict "$app"
echo "Built $app ($bundle_id, $nextshot_version ($nextshot_build))"

if ((install == 0)); then
  exit 0
fi

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

# Before 2026-10-25 this script installed the dev build as Nextshot.app with
# the production bundle ID. Say so when that copy is still there.
legacy="$HOME/Applications/Nextshot.app"
if [[ -d "$legacy" ]]; then
  legacy_sign="$(codesign -dv "$legacy" 2>&1 | sed -n 's/^Authority=\(Apple Development.*\)$/\1/p' | head -1)"
  if [[ -n "$legacy_sign" ]]; then
    echo "Note: $legacy is an older dev build ($legacy_sign) with the production bundle ID."
    echo "Replace it with a release DMG, or delete it, so each app keeps one screen recording grant."
  fi
fi
