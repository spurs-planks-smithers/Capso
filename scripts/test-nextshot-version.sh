#!/bin/bash
# Fork: checks scripts/nextshot-version.sh. Good values must give the right
# version, and a VERSION that is not a SemVer number, or is date-shaped, must
# stop the script. Run it after any edit to the version script or its callers.
#
# Usage: scripts/test-nextshot-version.sh
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/nextshot-version.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
git -C "$tmp" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m one
git -C "$tmp" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m two

fail=0
# <channel> <VERSION text> <wanted version> <wanted build>
expect_ok() {
  printf '%s\n' "$2" > "$tmp/VERSION"
  got="$(bash -c "set -euo pipefail; repo='$tmp'; nextshot_channel='$1'; source '$script'; echo \"\$nextshot_version \$nextshot_build\"" 2>&1)"
  if [[ "$got" == "$3 $4" ]]; then echo "ok    $1 '$2' -> $got"; else echo "FAIL  $1 '$2' -> '$got' (want '$3 $4')"; fail=1; fi
}
# <channel> <VERSION text>
expect_fail() {
  printf '%s\n' "$2" > "$tmp/VERSION"
  if out="$(bash -c "set -euo pipefail; repo='$tmp'; nextshot_channel='$1'; source '$script'; echo PASSED" 2>&1)" && [[ "$out" == *PASSED* ]]; then
    echo "FAIL  $1 '$2' passed but must fail"; fail=1
  else
    echo "ok    $1 '$2' refused"
  fi
}

expect_ok release 0.3.0 0.3.0 2
expect_ok dev 0.3.0 0.3.0-dev 2
expect_ok dev "  1.20.300  " 1.20.300-dev 2
expect_ok release 99.0.0 99.0.0 2
expect_fail release 2026.10.25
expect_fail release 100.0.0
expect_fail release 01.2.3
expect_fail release 0.03.0
expect_fail release 0.3
expect_fail release v0.3.0
expect_fail release 0.3.0-rc.1
expect_fail release ""
expect_fail beta 0.3.0

# A missing VERSION file must stop the script too.
rm -f "$tmp/VERSION"
if bash -c "set -euo pipefail; repo='$tmp'; source '$script'; echo PASSED" 2>/dev/null | grep -q PASSED; then
  echo "FAIL  missing VERSION passed but must fail"; fail=1
else
  echo "ok    missing VERSION refused"
fi

# The default channel is dev.
printf '0.3.0\n' > "$tmp/VERSION"
got="$(bash -c "set -euo pipefail; repo='$tmp'; source '$script'; echo \"\$nextshot_version\"")"
if [[ "$got" == "0.3.0-dev" ]]; then echo "ok    default channel -> $got"; else echo "FAIL  default channel -> $got"; fail=1; fi

exit $fail
