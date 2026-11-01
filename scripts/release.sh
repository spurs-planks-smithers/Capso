#!/bin/bash
# Fork: cut a Nextshot release, or change which version nextshot.dev serves.
# The plan and the reasons are in docs/plans/2026-10-25-versioning-roadmap.md
# (milestone M2) and docs/decisions/2026-10-25-versioning-and-releases.md.
#
# Usage:
#   scripts/release.sh                  show the suggested bump and the plan, change nothing
#   scripts/release.sh --dry-run <bump> preflight checks and the plan only (no tests, build, or DMG check)
#   scripts/release.sh <bump>           cut the release
#   scripts/release.sh --promote X.Y.Z  point /download at an archived version (also the rollback)
#   scripts/release.sh --import-legacy FILE --version V --build N [--commit C] [--and-promote]
#                                       archive a date build that shipped before versions
#   Add --no-smoke to --promote or --import-legacy only while the Worker that
#   reads latest.json is not deployed yet. A release never skips the test.
#
# <bump> is patch, minor, major, or an exact X.Y.Z. major works only from 1.0.0
# on: type 1.0.0 yourself when you decide to launch. --profile NAME picks the
# notary keychain profile (default apple-notary).
#
# App release failures stop the app flow. Guides failures report partial success.
# A release runs these steps:
#   1. Preflight. On main, equal to origin/main, clean tree. Tests pass,
#      JevKit in Release too. Certificate, notary profile, R2, and GitHub
#      route are ready. CHANGELOG.md has an entry under Unreleased.
#   2. Bump. Moves Unreleased to the new version in CHANGELOG.md, writes
#      VERSION, makes the commit "chore: release X.Y.Z" and the tag
#      nextshot-vX.Y.Z. Both stay local until step 6.
#   3. Stage Guides (nonblocking), then build the app: sign, notarize, staple.
#   4. Check the DMG: ticket, Gatekeeper, bundle ID, version, build, signature.
#   5. Ask once. Shows the version, build, hash, and notes. A closed stdin or
#      anything but "y" stops here, and the local commit and tag are undone.
#   6. Archive to R2 (nothing is public yet), push main and the tag, then point
#      latest.json at the new record. Then the smoke test. If it fails,
#      latest.json goes back to the version it replaced.
#   7. Publish the exact staged site. Guide failure restores only the Worker
#      and reports a site-only retry. The verified app stays live.
#
# The terminal asks in step 5, so an unattended job cannot publish.
# Rehearsal: NEXTSHOT_R2_LOCAL=<folder> uses a simulated bucket for --promote
# and --import-legacy. A release itself refuses to run with it.
# On m5pro, production output stays a distribution artifact. Local testing
# uses Nextshot Dev, including Release compiler optimization.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/release-lib.sh
source "$repo/scripts/release-lib.sh"

site_url="${NEXTSHOT_SITE_URL:-https://nextshot.dev}"
profile="apple-notary"
dry_run=0
mode="release"
bump=""
promote_version=""
legacy_file="" legacy_version="" legacy_build="" legacy_commit="" and_promote=0 no_smoke=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --profile) profile="$2"; shift 2 ;;
    --promote) mode="promote"; promote_version="$2"; shift 2 ;;
    --import-legacy) mode="import"; legacy_file="$2"; shift 2 ;;
    --version) legacy_version="$2"; shift 2 ;;
    --build) legacy_build="$2"; shift 2 ;;
    --commit) legacy_commit="$2"; shift 2 ;;
    --and-promote) and_promote=1; shift ;;
    --no-smoke) no_smoke=1; shift ;;
    -h | --help) sed -n '2,40p' "$0"; exit 0 ;;
    -*) rel_fail "unknown option: $1" ;;
    *) [[ -z "$bump" ]] || rel_fail "one bump only: '$bump' and '$1'"; bump="$1"; shift ;;
  esac
done
python3 -I "$repo/scripts/nextshot-local.py" check

# Asks on the terminal. A closed stdin, a pipe, or anything but y stops.
confirm() {
  local answer
  if [[ ! -t 0 ]]; then
    echo "release: no terminal to ask on. Nothing was published." >&2
    return 1
  fi
  read -r -p "$1 [y/N] " answer || return 1
  [[ "$answer" == y || "$answer" == Y || "$answer" == yes ]]
}

# --no-smoke is for one step: filling the bucket before the Worker that reads
# it is deployed. The live site has no /latest.json route yet, so the test
# would fail and put the pointer back. A release never skips the test.
smoke() {
  if ((no_smoke)); then
    echo "release: smoke test skipped (--no-smoke). Run site/smoke.sh after the Worker is deployed."
    return 0
  fi
  "$repo/site/smoke.sh" --url "$site_url"
}

# --- Mode: promote -----------------------------------------------------------

if [[ "$mode" == promote ]]; then
  [[ "$promote_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || rel_fail "--promote needs a version such as 0.3.0"
  r2_login
  confirm "Point $site_url/download at $promote_version?" || exit 1
  promote_release "$promote_version"
  echo "release: latest.json now says $promote_version (it said ${release_previous:-nothing}). Guides unchanged."
  if ! smoke; then
    restore_latest
    rel_fail "the smoke test failed"
  fi
  exit 0
fi

# --- Mode: import a date build ----------------------------------------------

if [[ "$mode" == import ]]; then
  [[ -f "$legacy_file" ]] || rel_fail "no file: $legacy_file"
  [[ "$legacy_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || rel_fail "--version needs a version such as 2026.10.24"
  [[ "$legacy_build" =~ ^[0-9]+$ ]] || rel_fail "--build needs the build number, such as 524"
  legacy_name="$(basename "$legacy_file")"
  [[ "$legacy_name" =~ ^Nextshot-$legacy_version-([0-9a-f]{7})\.dmg$ ]] ||
    rel_fail "$legacy_name is not a date build named Nextshot-$legacy_version-<commit>.dmg"
  legacy_commit="${legacy_commit:-${BASH_REMATCH[1]}}"
  r2_login
  check_dmg "$legacy_file" "$legacy_version" "$legacy_build"
  work="$(mktemp -d)"
  printf 'Shipped before versions were numbered, labeled %s.\n' "$legacy_version" >"$work/notes.md"
  make_record "$work/record.json" "$legacy_version" "$legacy_build" "$legacy_file" - "$legacy_commit" - "$work/notes.md"
  confirm "Archive $legacy_name as $legacy_version (build $legacy_build) in R2?" || exit 1
  archive_release "$work/record.json" "$legacy_file" -
  echo "release: archived $legacy_name"
  if ((and_promote)); then
    confirm "Point $site_url/download at $legacy_version?" || exit 1
    promote_release "$legacy_version"
    smoke || { restore_latest; rel_fail "the smoke test failed"; }
  fi
  rm -rf "$work"
  exit 0
fi

# --- Mode: release -----------------------------------------------------------

[[ -z "${NEXTSHOT_R2_LOCAL:-}" ]] || rel_fail "a release does not run with NEXTSHOT_R2_LOCAL set: the rehearsal bucket is not the site"
((no_smoke == 0)) || rel_fail "a release always runs the smoke test: --no-smoke is for --promote and --import-legacy only"

# With no bump the command only suggests one, as a dry run does.
[[ -n "$bump" ]] || dry_run=1

failures=0
# need <description> <command...>: a failed check stops a release and is only
# counted in a dry run.
need() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok    $description"
  else
    echo "FAIL  $description" >&2
    if ((dry_run)); then failures=$((failures + 1)); else exit 1; fi
  fi
}

on_main() { [[ "$(git -C "$repo" branch --show-current)" == main ]]; }
at_origin_main() {
  git -C "$repo" fetch origin --no-tags -q && [[ "$(git -C "$repo" rev-parse HEAD)" == "$(git -C "$repo" rev-parse origin/main)" ]]
}
clean_tree() { [[ -z "$(git -C "$repo" status --porcelain)" ]]; }
has_cert() { security find-identity -v -p codesigning | grep -q "Developer ID Application"; }
has_notary_profile() { xcrun notarytool history --keychain-profile "$profile"; }
route_ok() { github-route status; }
changelog_ready() { python3 -I "$repo/scripts/release-changelog.py" check "$repo/CHANGELOG.md"; }

run_tests() {
  local log="$repo/build/release-tests.log"
  mkdir -p "$repo/build"
  : >"$log"
  {
    "$repo/scripts/test-nextshot-version.sh"
    bash "$repo/scripts/test-release.sh"
    node --test "$repo/site/test/releases.test.mjs"
    swift test --package-path "$repo/Packages/FeedbackKit"
    swift test --package-path "$repo/Packages/JevKit"
    # An optimizer bug lost a dupes result in Release only, on 2026-10-25.
    swift test -c release -Xswiftc -enable-testing --package-path "$repo/Packages/JevKit"
    (cd "$repo" && xcodegen generate && xcodebuild test -project Capso.xcodeproj -scheme Capso -configuration Debug \
      CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:CapsoTests)
  } >>"$log" 2>&1 || { echo "release: tests failed, see $log" >&2; return 1; }
}

echo "== Preflight"
need "on main" on_main
need "equal to origin/main" at_origin_main
need "no uncommitted changes" clean_tree
need "Developer ID certificate in the keychain" has_cert
need "notary profile '$profile'" has_notary_profile
need "GitHub route is the personal account" route_ok
need "CHANGELOG.md has an entry under Unreleased" changelog_ready
r2_login
need "R2 bucket $release_bucket is reachable" r2_reachable

current="$(tr -d '[:space:]' <"$repo/VERSION")"
semver_ok "$current" || rel_fail "VERSION holds '$current', which is not MAJOR.MINOR.PATCH"
last_tag="$(git -C "$repo" describe --tags --match "${release_tag_prefix}*" --abbrev=0 2>/dev/null || true)"

if [[ -n "$last_tag" ]]; then
  suggested="$(git -C "$repo" log --format=%s "$last_tag..HEAD" | suggest_bump)"
  commits="$(git -C "$repo" rev-list --count "$last_tag..HEAD")"
else
  suggested="(no earlier $release_tag_prefix tag, so name the bump yourself)"
  commits="$(git -C "$repo" rev-list --count HEAD)"
fi

if [[ -z "$bump" ]]; then
  echo
  echo "VERSION:          $current"
  echo "Last release tag: ${last_tag:-none}"
  echo "Commits since:    $commits"
  echo "Suggested bump:   $suggested"
  echo
  echo "Run: scripts/release.sh <patch|minor|major|X.Y.Z>   (add --dry-run to see the plan first)"
  ((failures == 0)) || exit 1
  exit 0
fi

case "$bump" in
  patch | minor | major)
    new="$(bump_version "$current" "$bump")" ||
      rel_fail "'major' works only from 1.0.0 on. To launch 1.0.0, run: scripts/release.sh 1.0.0"
    ;;
  *)
    semver_ok "$bump" || rel_fail "'$bump' is not patch, minor, major, or MAJOR.MINOR.PATCH"
    semver_gt "$bump" "$current" || rel_fail "$bump is not newer than $current"
    new="$bump"
    ;;
esac
tag="$release_tag_prefix$new"
today="$(date -u +%Y-%m-%d)"
no_tag() { ! git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null; }
not_in_r2() { r2_reachable && ! r2_get "releases/Nextshot-$new.json" "$(mktemp)"; }
need "tag $tag does not exist" no_tag
need "R2 holds no release $new" not_in_r2

echo
echo "== Plan"
echo "  Version:   $current -> $new ($bump; the commits suggest: $suggested)"
echo "  Tag:       $tag"
echo "  Files:     build/releases/Nextshot-$new.dmg and .zip"
echo "  R2:        releases/Nextshot-$new.{dmg,zip,dmg.sha256,json}, then latest.json"
echo "  Site:      $site_url"
echo "  Notes (CHANGELOG.md, Unreleased):"
python3 -I "$repo/scripts/release-changelog.py" notes Unreleased "$repo/CHANGELOG.md" 2>/dev/null | sed 's/^/    /' || true

if ((dry_run)); then
  echo
  echo "Dry run: nothing was changed, built, or uploaded. The real run also runs the tests (JevKit in Release too)."
  ((failures == 0)) || { echo "$failures check(s) would stop a real run." >&2; exit 1; }
  exit 0
fi

echo
echo "== Tests"
run_tests
echo "ok    tests passed"

# --- Steps 2 to 6 change things. Undo the local commit and tag on any failure
# before the push.
orig_head="$(git -C "$repo" rev-parse HEAD)"
created_commit="" created_tag="" pushed=0 app_verified=0
guides_artifact="" guides_status="not staged"
work="$(mktemp -d)"

shelve_build() {
  local stem="$repo/build/releases/Nextshot-$new" shelf="$repo/build/releases/unreleased"
  if [[ -e "$stem.dmg" || -e "$stem.zip" ]]; then
    mkdir -p "$shelf"
    mv -n "$stem.dmg" "$stem.zip" "$shelf/" 2>/dev/null || true
    echo "release: moved the unpublished build to $shelf" >&2
  fi
}

on_exit() {
  local status=$?
  trap - EXIT
  rm -rf "$work"
  if ((status != 0 && pushed == 0)); then
    [[ -z "$created_tag" ]] || git -C "$repo" tag -d "$created_tag" >/dev/null 2>&1 || true
    if [[ -n "$created_commit" && "$(git -C "$repo" rev-parse HEAD)" == "$created_commit" ]]; then
      git -C "$repo" reset --keep "$orig_head" >/dev/null 2>&1 && echo "release: undid the local release commit and tag" >&2
    fi
    shelve_build
  elif ((status != 0 && app_verified)); then
    echo "release: partial success. Nextshot $new passed its app checks before the site deploy. Guides: $guides_status." >&2
    echo "The app files and latest.json remain published in R2. Check the site recovery result above." >&2
    if [[ -n "$guides_artifact" ]]; then
      echo "Retry site only: site/deploy.sh --deploy-staged '$guides_artifact'" >&2
    else
      echo "Retry site only after fixing staging: site/deploy.sh" >&2
    fi
  elif ((status != 0)); then
    echo "release: main and $tag are pushed. Fix the problem, then run: scripts/release.sh --promote $new" >&2
  fi
  exit "$status"
}
trap on_exit EXIT

echo
echo "== Bump"
python3 -I "$repo/scripts/release-changelog.py" rotate "$new" "$today" "$repo/CHANGELOG.md"
printf '%s\n' "$new" >"$repo/VERSION"
git -C "$repo" add VERSION CHANGELOG.md
git -C "$repo" commit -q -m "chore: release $new" -- VERSION CHANGELOG.md
created_commit="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" tag -a "$tag" -m "Nextshot $new"
created_tag="$tag"
echo "ok    commit ${created_commit:0:7} and tag $tag, local only"

# Guides failure never blocks the app build or its existing approval.
echo
echo "== Stage Guides (nonblocking for app release)"
if "$repo/site/deploy.sh" --stage-only >"$work/guides-stage.log" 2>&1; then
  guides_artifact="$(tail -1 "$work/guides-stage.log")"
  guides_status="staged at $guides_artifact"
else
  guides_status="STAGING FAILED; app release can continue. Guides unchanged"
  cat "$work/guides-stage.log" >&2
fi
echo "Guides: $guides_status"

echo
echo "== Build"
"$repo/scripts/release-notarized.sh" "$profile"
dmg="$repo/build/releases/Nextshot-$new.dmg"
zip="$repo/build/releases/Nextshot-$new.zip"
[[ -f "$dmg" && -f "$zip" ]] || rel_fail "the build left no $dmg"
build="$(git -C "$repo" rev-list --count HEAD)"

echo
echo "== Check"
check_dmg "$dmg" "$new" "$build"
echo "ok    $(basename "$dmg"): ticket, Gatekeeper, bundle ID, version $new, build $build, signature"

python3 -I "$repo/scripts/release-changelog.py" notes "$new" "$repo/CHANGELOG.md" >"$work/notes.md"
make_record "$work/record.json" "$new" "$build" "$dmg" "$zip" "${created_commit:0:7}" "$tag" "$work/notes.md"

echo
echo "== Ask"
echo "  Version  $new (build $build), commit ${created_commit:0:7}, tag $tag"
echo "  DMG      $(basename "$dmg"), $(stat -f %z "$dmg") bytes, SHA-256 $(record_field "$work/record.json" sha256)"
echo "  Guides   $guides_status"
echo "  Notes"
sed 's/^/    /' "$work/notes.md"
echo
confirm "Archive to R2, push main and $tag to origin, point $site_url/download at $new, then publish Guides if staged?" ||
  rel_fail "stopped before anything was published"

echo
echo "== Archive"
archive_release "$work/record.json" "$dmg" "$zip"
echo "ok    R2 holds $new and its hash matches"

echo
echo "== Publish"
github-route status >/dev/null || rel_fail "github-route status failed. Nothing was pushed."
git -C "$repo" push origin main
git -C "$repo" push origin "$tag"
pushed=1
promote_release "$new"
echo "ok    pushed, and latest.json says $new (it said ${release_previous:-nothing})"
if ! smoke; then
  restore_latest
  rel_fail "the smoke test failed and latest.json was reset. main and $tag stay pushed."
fi
app_verified=1
echo
echo "Released Nextshot $new (build $build) at $site_url"

# Snapshot only after the new app passes. A guide rollback changes this Worker
# version alone. It must never restore the app pointer in latest.json.
if [[ -z "$guides_artifact" ]]; then
  exit 1
fi
echo
echo "== Publish Guides"
if ! "$repo/site/worker-deployment.sh" snapshot "$guides_artifact/wrangler.json" "$work/verified-worker.json"; then
  guides_status="Worker snapshot failed; Guides unchanged"
  exit 1
fi
if ! "$repo/site/deploy.sh" --deploy-staged "$guides_artifact" --rollback-snapshot "$work/verified-worker.json"; then
  guides_status="publish or smoke failed; inspect the verified Worker recovery result above"
  exit 1
fi
guides_status="published and verified"
echo "Released Nextshot $new and Guides at $site_url"
