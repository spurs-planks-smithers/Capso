# Fork: Nextshot's version numbers, from git. build-local.sh and
# release-notarized.sh source this file after they set $repo, then pass both
# values to xcodebuild.
#
# The version is the date of the HEAD commit, for example 2026.10.22. The
# build number is the commit count on HEAD, so it rises with every commit and
# tells two builds from the same day apart. Preferences shows "2026.10.22 (489)".
# Upstream's project.yml keeps Capso's numbers for Capso.app.
nextshot_version="$(git -C "$repo" log -1 --date=format-local:%Y.%-m.%-d --format=%cd)"
nextshot_build="$(git -C "$repo" rev-list --count HEAD)"
