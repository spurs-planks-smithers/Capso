#!/bin/bash
# Build and sign the one-operation Chrome helper before Xcode signs its parent app.
set -euo pipefail
: "${SRCROOT:?}" "${TARGET_BUILD_DIR:?}" "${CONTENTS_FOLDER_PATH:?}" "${PRODUCT_BUNDLE_IDENTIFIER:?}"
case "$PRODUCT_BUNDLE_IDENTIFIER" in
  com.drewschulz.nextshot.dev|com.drewschulz.nextshot) ;;
  *) echo 'Browser host requires a Nextshot app identity.' >&2; exit 1 ;;
esac
configuration=release
[[ "${CONFIGURATION:-Release}" == Debug ]] && configuration=debug
scratch="$SRCROOT/build/browser-host-$configuration"
# Honor the caller's cache setting in SwiftPM's nested build as well.
build_host() {
  if [[ "${SDK_STAT_CACHE_ENABLE:-YES}" == NO ]]; then
    swift build --build-system native "$@"
  else
    swift build "$@"
  fi
}
build_host --package-path "$SRCROOT/Packages/BrowserBridgeKit" --scratch-path "$scratch" -c "$configuration" --product NextshotBrowserHost
binary_dir="$(build_host --package-path "$SRCROOT/Packages/BrowserBridgeKit" --scratch-path "$scratch" -c "$configuration" --show-bin-path)"
destination="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
mkdir -p "$destination"
cp "$binary_dir/NextshotBrowserHost" "$destination/NextshotBrowserHost"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime --identifier "$PRODUCT_BUNDLE_IDENTIFIER.browser-host" "$destination/NextshotBrowserHost"
fi
