#!/bin/bash
# Fork: checks the parts of scripts/release.sh that need no network, no
# notarization, and no Cloudflare: version math, the bump suggestion, the
# CHANGELOG.md steps, and the release record. Run it after any edit to
# scripts/release.sh, scripts/release-lib.sh, scripts/release-changelog.py,
# or scripts/nextshot-local.py.
#
# Usage: scripts/test-release.sh
set -uo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/release-lib.sh
source "$repo/scripts/release-lib.sh"
changelog_py="$repo/scripts/release-changelog.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
pass() { echo "ok    $1"; }
bad() { echo "FAIL  $1" >&2; fail=1; }
expect() { # <label> <want> <got>
  if [[ "$3" == "$2" ]]; then pass "$1"; else bad "$1 (got '$3', want '$2')"; fi
}
is_true() { if "${@:2}" 2>/dev/null; then pass "$1"; else bad "$1 (was false)"; fi; }
is_false() { if "${@:2}" 2>/dev/null; then bad "$1 (was true)"; else pass "$1"; fi; }

# --- SemVer ---
is_true "0.3.0 is a version" semver_ok 0.3.0
is_true "99.0.0 is a version" semver_ok 99.0.0
is_false "100.0.0 is not (MAJOR under 100)" semver_ok 100.0.0
is_false "2026.10.25 is not (a date)" semver_ok 2026.10.25
is_false "01.2.3 is not (leading zero)" semver_ok 01.2.3
is_false "0.3 is not" semver_ok 0.3
is_false "0.3.0-rc.1 is not" semver_ok 0.3.0-rc.1
is_true "0.10.0 is newer than 0.9.9" semver_gt 0.10.0 0.9.9
is_true "1.0.0 is newer than 0.99.99" semver_gt 1.0.0 0.99.99
is_false "0.3.0 is not newer than 0.3.0" semver_gt 0.3.0 0.3.0
is_false "0.3.0 is not newer than 0.3.1" semver_gt 0.3.0 0.3.1

# --- Bumps ---
expect "patch" 0.3.1 "$(bump_version 0.3.0 patch)"
expect "minor" 0.4.0 "$(bump_version 0.3.7 minor)"
expect "minor from 0.9.9" 0.10.0 "$(bump_version 0.9.9 minor)"
expect "major from 1.4.2" 2.0.0 "$(bump_version 1.4.2 major)"
is_false "major from 0.x is refused" bump_version 0.3.0 major
is_false "an unknown bump is refused" bump_version 0.3.0 huge

# --- Suggested bump ---
expect "feat suggests minor" minor "$(printf 'fix: a\nfeat: b\ndocs: c\n' | suggest_bump)"
expect "a scoped feat suggests minor" minor "$(printf 'feat(menu): b\n' | suggest_bump)"
expect "fix alone suggests patch" patch "$(printf 'fix: a\ndocs: c\ntest: d\n' | suggest_bump)"
expect "refactor suggests patch" patch "$(printf 'refactor: a\n' | suggest_bump)"
expect "a breaking fix is minor below 1.0" minor "$(printf 'fix!: a\n' | suggest_bump)"
expect "docs and tests alone suggest none" none "$(printf 'docs: a\ntest: b\nchore: c\n' | suggest_bump)"
expect "no commits suggest none" none "$(printf '' | suggest_bump)"
expect "a merge subject is not a feat" none "$(printf 'Merge pull request #1 from x/feat: y\n' | suggest_bump)"

# --- CHANGELOG.md ---
cat >"$tmp/CHANGELOG.md" <<'EOF'
# Changelog

Intro text.

## [Unreleased]

### Added

- The new thing.

### Fixed

- The old bug.

## [0.2.0] - 2026-10-24

### Added

- Round keys.

## [0.1.0] - 2026-10-22

- First.
EOF
is_true "changelog check passes with entries" python3 -I "$changelog_py" check "$tmp/CHANGELOG.md"
expect "notes of Unreleased" "### Added

- The new thing.

### Fixed

- The old bug." "$(python3 -I "$changelog_py" notes Unreleased "$tmp/CHANGELOG.md")"
expect "notes of 0.2.0" "### Added

- Round keys." "$(python3 -I "$changelog_py" notes 0.2.0 "$tmp/CHANGELOG.md")"
python3 -I "$changelog_py" rotate 0.3.0 2026-10-26 "$tmp/CHANGELOG.md"
expect "rotate keeps an empty Unreleased first" "## [Unreleased]" "$(grep -n '^## \[' "$tmp/CHANGELOG.md" | head -1 | cut -d: -f2)"
expect "rotate adds the new version second" "## [0.3.0] - 2026-10-26" "$(grep '^## \[' "$tmp/CHANGELOG.md" | sed -n 2p)"
expect "rotate keeps the older versions" "## [0.2.0] - 2026-10-24" "$(grep '^## \[' "$tmp/CHANGELOG.md" | sed -n 3p)"
expect "the moved notes belong to 0.3.0" "### Added

- The new thing.

### Fixed

- The old bug." "$(python3 -I "$changelog_py" notes 0.3.0 "$tmp/CHANGELOG.md")"
is_false "Unreleased is empty after the rotate" python3 -I "$changelog_py" check "$tmp/CHANGELOG.md"
is_false "rotate refuses an empty Unreleased" python3 -I "$changelog_py" rotate 0.3.1 2026-10-27 "$tmp/CHANGELOG.md"
printf '## [Unreleased]\n\n- x\n' >"$tmp/once.md"
is_false "rotate refuses a bad version" python3 -I "$changelog_py" rotate 0.3 2026-10-26 "$tmp/once.md"
is_false "rotate refuses a bad date" python3 -I "$changelog_py" rotate 0.3.0 26-10-2026 "$tmp/once.md"
printf '## [Unreleased]\n\n- x\n\n## [0.3.0] - 2026-10-26\n\n- y\n' >"$tmp/dup.md"
is_false "rotate refuses a version it already holds" python3 -I "$changelog_py" rotate 0.3.0 2026-10-27 "$tmp/dup.md"
printf '# Changelog\n' >"$tmp/none.md"
is_false "check refuses a file with no Unreleased heading" python3 -I "$changelog_py" check "$tmp/none.md"

# --- Release record ---
dmg="$tmp/Nextshot-0.3.0.dmg"
zip="$tmp/Nextshot-0.3.0.zip"
printf 'dmg bytes' >"$dmg"
printf 'zip bytes' >"$zip"
printf 'The notes.\n' >"$tmp/notes.md"
make_record "$tmp/record.json" 0.3.0 625 "$dmg" "$zip" abc1234 nextshot-v0.3.0 "$tmp/notes.md"
is_true "the record is valid" record_valid "$tmp/record.json"
expect "record version" 0.3.0 "$(record_field "$tmp/record.json" version)"
expect "record build" 625 "$(record_field "$tmp/record.json" build)"
expect "record file" Nextshot-0.3.0.dmg "$(record_field "$tmp/record.json" file)"
expect "record size" 9 "$(record_field "$tmp/record.json" size)"
expect "record hash matches the file" "$(sha256_of "$dmg")" "$(record_field "$tmp/record.json" sha256)"
expect "record zip hash matches the file" "$(sha256_of "$zip")" "$(record_field "$tmp/record.json" zipSha256)"
expect "record tag" nextshot-v0.3.0 "$(record_field "$tmp/record.json" tag)"
expect "record notes" "The notes." "$(record_field "$tmp/record.json" notes)"
printf 'x' >"$tmp/Nextshot-2026.10.24-9d3afc7.dmg"
make_record "$tmp/legacy.json" 2026.10.24 524 "$tmp/Nextshot-2026.10.24-9d3afc7.dmg" - 9d3afc7 - "$tmp/notes.md"
is_true "a legacy record is valid" record_valid "$tmp/legacy.json"
python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); r["sha256"]="abc"; json.dump(r, open(sys.argv[1],"w"))' "$tmp/record.json"
is_false "a record with a short hash is invalid" record_valid "$tmp/record.json"
printf '{not json' >"$tmp/broken.json"
is_false "a broken record is invalid" record_valid "$tmp/broken.json"

# --- R2 functions on the simulated bucket (wrangler --local, no network) ---
export NEXTSHOT_R2_LOCAL="$tmp/r2"
r2_login
printf 'object bytes\n' >"$tmp/obj.txt"
r2_put releases/Nextshot-0.0.1.json "$tmp/obj.txt" application/json
is_true "a stored object can be read back" r2_get releases/Nextshot-0.0.1.json "$tmp/obj.out"
expect "the object read back is the same" "$(cat "$tmp/obj.txt")" "$(cat "$tmp/obj.out" 2>/dev/null)"
is_false "a missing key is not found" r2_get releases/Nextshot-9.9.9.json "$tmp/none.out"
r2_delete releases/Nextshot-0.0.1.json
is_false "a deleted object is gone" r2_get releases/Nextshot-0.0.1.json "$tmp/gone.out"
unset NEXTSHOT_R2_LOCAL

# --- The Cloudflare token stays out of curl's arguments ---
# A fake security returns a known token. A fake curl records its arguments and
# its stdin. r2_login must pass the token on stdin only (curl -K -).
fake="$tmp/fake-bin"
mkdir -p "$fake"
printf '#!/bin/bash\nprintf "tok-0123456789abcdef"\n' >"$fake/security"
cat >"$fake/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$FAKE_CURL_ARGS"
cat >"$FAKE_CURL_STDIN"
printf '{"result":{"id":"key-id-1"}}'
EOF
chmod +x "$fake/security" "$fake/curl"
login_id="$(FAKE_CURL_ARGS="$tmp/curl.args" FAKE_CURL_STDIN="$tmp/curl.stdin" PATH="$fake:$PATH" TMPDIR="$tmp" \
  bash -c 'source "$1/scripts/release-lib.sh" && r2_login && printf "%s" "$r2_key_id"' _ "$repo")"
expect "r2_login reads the token id from the verify reply" key-id-1 "$login_id"
is_false "the token is not in curl's arguments" grep -q 'tok-0123456789abcdef' "$tmp/curl.args"
is_true "curl reads the token from stdin" grep -q 'Authorization: Bearer tok-0123456789abcdef' "$tmp/curl.stdin"
is_false "no shell script puts a Bearer header on a curl line" \
  grep -rnE 'curl[^|]*Bearer' --include='*.sh' --exclude=test-release.sh --exclude-dir=node_modules "$repo/scripts" "$repo/site"

# Local app identity and m5pro policy. Fixtures never launch or install an app.
if python3 -I - "$repo" "$tmp" <<'PY'
import importlib.util
import pathlib
import plistlib
import sys
import unittest

script = pathlib.Path(sys.argv[1]) / "scripts/nextshot-local.py"
assert script.is_file(), "Dev-only local app guard is missing"
spec = importlib.util.spec_from_file_location("local_policy", script)
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)
root = pathlib.Path(sys.argv[2]) / "apps"
root.mkdir()

def app(name, identifier, version="0.4.0-dev", schemes=("nextshot-dev",)):
    path = root / name
    (path / "Contents").mkdir(parents=True, exist_ok=True)
    with (path / "Contents/Info.plist").open("wb") as stream:
        plistlib.dump({"CFBundleIdentifier": identifier,
                      "CFBundleShortVersionString": version,
                      "CFBundleURLTypes": [{"CFBundleURLSchemes": list(schemes)}]}, stream)
    return path

class LocalPolicyTests(unittest.TestCase):
    def setUp(self):
        for path in root.glob("*.app/Contents/Info.plist"):
            path.unlink()

    def test_optimized_dev_build_is_allowed(self):
        policy.verify_dev_app(app("Nextshot Dev.app", policy.DEV_ID))

    def test_production_identity_is_refused(self):
        with self.assertRaises(ValueError):
            policy.verify_dev_app(app("Nextshot Dev.app", policy.PRODUCTION_ID))

    def test_production_url_scheme_is_refused(self):
        with self.assertRaises(ValueError):
            policy.verify_dev_app(app("Nextshot Dev.app", policy.DEV_ID, schemes=("nextshot",)))

    def test_release_version_is_refused(self):
        with self.assertRaises(ValueError):
            policy.verify_dev_app(app("Nextshot Dev.app", policy.DEV_ID, version="0.4.0"))

    def test_renamed_installed_production_is_refused(self):
        app("Renamed.app", policy.PRODUCTION_ID)
        with self.assertRaises(ValueError):
            policy.check_local_policy("m5pro.local", [root], [])

    def test_history_review_is_refused(self):
        app("Renamed.app", "com.drewschulz.nextshot.historyreview")
        with self.assertRaises(ValueError):
            policy.check_local_policy("M5PRO", [root], [])

    def test_running_production_artifact_is_refused(self):
        path = app("Outside.app", policy.PRODUCTION_ID)
        with self.assertRaises(ValueError):
            policy.check_local_policy("m5pro", [], [path])

    def test_distribution_artifact_can_remain_uninstalled(self):
        app("Artifact.app", policy.PRODUCTION_ID)
        policy.check_local_policy("m5pro", [], [])

    def test_other_mac_can_perform_release_validation(self):
        app("Nextshot.app", policy.PRODUCTION_ID)
        policy.check_local_policy("release-test-mac", [root], [])

    def test_process_paths_keep_spaces(self):
        text = "/usr/sbin/launchd\n /tmp/Long Build/Nextshot.app/Contents/MacOS/Nextshot\n"
        self.assertEqual(policy.running_app_paths(text), [pathlib.Path("/tmp/Long Build/Nextshot.app")])

    def test_empty_process_inventory_fails(self):
        with self.assertRaises(ValueError):
            policy.running_app_paths("")

unittest.main(argv=[sys.argv[0]])
PY
then pass "local Dev policy"; else bad "local Dev policy"; fi

exit $fail
