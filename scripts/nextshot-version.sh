# Fork: Nextshot's version numbers. build-local.sh and release-notarized.sh
# source this file after they set $repo, then pass both values to xcodebuild.
#
# The version comes from the VERSION file at the repo root, which holds the
# last released version as MAJOR.MINOR.PATCH, for example 0.3.0. Only the
# release step edits it (docs/decisions/2026-10-25-versioning-and-releases.md).
# A release build shows it as it is. A dev build adds -dev, for example
# 0.3.0-dev, so a dev copy never passes for a release.
#
# The build number is the commit count on HEAD. Releases come only from main,
# so it only rises from one release to the next. Preferences and the Nshot
# menu show "0.3.0 (625)". Upstream's project.yml keeps Capso's numbers for
# Capso.app.
#
# Set nextshot_channel to "release" before sourcing to get the plain version.
# It defaults to "dev", so a stray build is never taken for a release.
nextshot_channel="${nextshot_channel:-dev}"
nextshot_base="$(tr -d '[:space:]' < "$repo/VERSION")"
# SemVer 2.0.0 item 2: no leading zeros. A MAJOR of 100 or more is refused, so
# a date such as 2026.10.25 from the old scheme cannot pass as a version.
if [[ ! "$nextshot_base" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || ((BASH_REMATCH[1] >= 100)); then
  echo "$repo/VERSION must hold MAJOR.MINOR.PATCH, for example 0.3.0, with MAJOR under 100. It holds '$nextshot_base'." >&2
  return 1 2>/dev/null || exit 1
fi
case "$nextshot_channel" in
  release) nextshot_version="$nextshot_base" ;;
  dev) nextshot_version="$nextshot_base-dev" ;;
  *)
    echo "nextshot_channel must be 'release' or 'dev', not '$nextshot_channel'." >&2
    return 1 2>/dev/null || exit 1
    ;;
esac
nextshot_build="$(git -C "$repo" rev-list --count HEAD)"
