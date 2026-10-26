# Fork: the functions that scripts/release.sh and site/deploy.sh share. Source
# this file; it runs nothing. The caller sets $repo to the repository root.
#
# R2 is the private Cloudflare bucket nextshot-releases. The layout:
#   releases/Nextshot-<v>.dmg         the DMG people install
#   releases/Nextshot-<v>.zip         a zip of the same app (Sparkle uses it later)
#   releases/Nextshot-<v>.dmg.sha256  the DMG checksum
#   releases/Nextshot-<v>.json        the record of that release
#   latest.json                       a copy of one record: the version /download serves
# Nobody replaces a published file. A bad build gets a new PATCH number, and a
# rollback points latest.json at an older record (release.sh --promote).
#
# Rehearsal: set NEXTSHOT_R2_LOCAL=<folder> and wrangler uses a simulated
# bucket in that folder, with no Cloudflare account involved. A local
# `wrangler dev --persist-to <folder>` reads the same bucket.

release_bucket="nextshot-releases"
release_keychain_item="CLOUDFLARE_API_TOKEN_NEXTSHOT"
release_tag_prefix="nextshot-v"

rel_fail() {
  echo "release: $*" >&2
  exit 1
}

# --- SemVer ---------------------------------------------------------------

# True when $1 is MAJOR.MINOR.PATCH with no leading zero and a MAJOR under 100,
# the same rule as scripts/nextshot-version.sh.
semver_ok() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] && ((BASH_REMATCH[1] < 100))
}

# True when version $1 is newer than version $2.
semver_gt() {
  local IFS=.
  local -a a b
  read -r -a a <<<"$1"
  read -r -a b <<<"$2"
  local i
  for i in 0 1 2; do
    ((a[i] > b[i])) && return 0
    ((a[i] < b[i])) && return 1
  done
  return 1
}

# Prints the version that follows $1 for a bump of patch, minor, or major. A
# major bump below 1.0.0 fails: 1.0.0 is the commercial launch, and Drew
# decides it by typing 1.0.0.
bump_version() {
  local IFS=.
  local -a v
  read -r -a v <<<"$1"
  case "$2" in
    patch) echo "${v[0]}.${v[1]}.$((v[2] + 1))" ;;
    minor) echo "${v[0]}.$((v[1] + 1)).0" ;;
    major)
      ((v[0] >= 1)) || return 1
      echo "$((v[0] + 1)).0.0"
      ;;
    *) return 1 ;;
  esac
}

# Prints minor, patch, or none for the commit subjects on stdin, by their
# conventional prefixes. feat is minor. A breaking change (feat!, fix!) is
# minor too, because the number stays below 1.0.0. fix, perf, and refactor are
# patch. docs, test, chore, and the rest ship hidden, so they are none.
suggest_bump() {
  local subjects
  subjects="$(cat)"
  if printf '%s\n' "$subjects" | grep -Eq '^[a-z]+(\([^)]*\))?!:' ||
    printf '%s\n' "$subjects" | grep -Eq '^feat(\([^)]*\))?:'; then
    echo minor
  elif printf '%s\n' "$subjects" | grep -Eq '^(fix|perf|refactor)(\([^)]*\))?:'; then
    echo patch
  else
    echo none
  fi
}

# --- R2 -------------------------------------------------------------------

# Sets r2_flags for wrangler: the real bucket, or a simulated one.
r2_flags=()
r2_login() {
  if [[ -n "${NEXTSHOT_R2_LOCAL:-}" ]]; then
    mkdir -p "$NEXTSHOT_R2_LOCAL"
    r2_flags=(--local --persist-to "$NEXTSHOT_R2_LOCAL")
    return 0
  fi
  local token
  token="$(security find-generic-password -s "$release_keychain_item" -w 2>/dev/null)" ||
    rel_fail "no Keychain item $release_keychain_item. Store it with keychain-store.sh $release_keychain_item"
  export CLOUDFLARE_API_TOKEN="$token"
  r2_flags=(--remote)
}

# True when the token can reach the bucket (or the simulated bucket is set up).
r2_reachable() {
  [[ -n "${NEXTSHOT_R2_LOCAL:-}" ]] && return 0
  local buckets
  buckets="$(wrangler r2 bucket list --config "$repo/site/wrangler.jsonc" 2>/dev/null)" || return 1
  [[ "$buckets" == *"$release_bucket"* ]]
}

# r2_put <key> <file> <content type>
r2_put() {
  wrangler r2 object put "$release_bucket/$1" --file "$2" --content-type "$3" \
    "${r2_flags[@]}" --config "$repo/site/wrangler.jsonc" >/dev/null 2>&1 ||
    rel_fail "could not upload $1 to R2"
}

# r2_get <key> <file>: writes the object to the file. Fails when it is missing.
r2_get() {
  rm -f "$2"
  wrangler r2 object get "$release_bucket/$1" --file "$2" \
    "${r2_flags[@]}" --config "$repo/site/wrangler.jsonc" >/dev/null 2>&1 && [[ -s "$2" ]]
}

# r2_delete <key>
r2_delete() {
  wrangler r2 object delete "$release_bucket/$1" \
    "${r2_flags[@]}" --config "$repo/site/wrangler.jsonc" >/dev/null 2>&1 ||
    rel_fail "could not delete $1 from R2"
}

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

# record_field <file> <key>: one field of a release record.
record_field() {
  python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"
}

# True when the file is a release record that site/src/releases.mjs accepts.
record_valid() {
  python3 -I - "$1" <<'PY'
import json, re, sys
try:
    r = json.load(open(sys.argv[1]))
    ok = (
        isinstance(r, dict)
        and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", r["version"])
        and isinstance(r["build"], int) and r["build"] >= 1
        and re.fullmatch(r"Nextshot-[0-9]+\.[0-9]+\.[0-9]+(-[0-9a-f]{7})?\.dmg", r["file"])
        and isinstance(r["size"], int) and r["size"] >= 1
        and re.fullmatch(r"[0-9a-f]{64}", r["sha256"])
    )
except Exception:
    ok = False
sys.exit(0 if ok else 1)
PY
}

# --- Release records ------------------------------------------------------

# make_record <out> <version> <build> <dmg> <zip or -> <commit> <tag or -> <notes file>
# Writes the record JSON for one release.
make_record() {
  python3 -I - "$@" <<'PY'
import datetime, hashlib, json, os, sys

out, version, build, dmg, zip_path, commit, tag, notes_file = sys.argv[1:9]

def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()

record = {
    "version": version,
    "build": int(build),
    "file": os.path.basename(dmg),
    "size": os.path.getsize(dmg),
    "sha256": sha256(dmg),
    "commit": commit,
    "released": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "notes": open(notes_file, encoding="utf-8").read().strip(),
}
if zip_path != "-":
    record["zip"] = os.path.basename(zip_path)
    record["zipSize"] = os.path.getsize(zip_path)
    record["zipSha256"] = sha256(zip_path)
if tag != "-":
    record["tag"] = tag
with open(out, "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

# archive_release <record file> <dmg> <zip or ->
# Uploads the files and then the record, and checks the uploaded DMG against the
# record's hash. The record goes last, so a failed upload leaves no record, and
# the release is not listed. It stops when R2 already holds the version.
archive_release() {
  local record="$1" dmg="$2" zip="$3" version file sums work
  version="$(record_field "$record" version)"
  file="$(record_field "$record" file)"
  work="$(mktemp -d)"
  if r2_get "releases/Nextshot-$version.json" "$work/existing.json"; then
    rm -rf "$work"
    rel_fail "R2 already holds $version. Nobody replaces a published release. Raise the PATCH number."
  fi

  sums="$work/$file.sha256"
  printf '%s  %s\n' "$(record_field "$record" sha256)" "$file" >"$sums"
  r2_put "releases/$file" "$dmg" application/x-apple-diskimage
  if [[ "$zip" != "-" ]]; then
    r2_put "releases/$(basename "$zip")" "$zip" application/zip
  fi
  r2_put "releases/$file.sha256" "$sums" "text/plain; charset=utf-8"

  # Read the DMG back from R2 and compare, before the record makes it official.
  r2_get "releases/$file" "$work/readback.dmg" || rel_fail "could not read $file back from R2"
  [[ "$(sha256_of "$work/readback.dmg")" == "$(record_field "$record" sha256)" ]] ||
    rel_fail "the DMG in R2 does not match its hash. The record was not written."
  r2_put "releases/Nextshot-$version.json" "$record" application/json
  rm -rf "$work"
}

# promote_release <version>
# Points latest.json at the record of an archived version. This is also the
# rollback: promote an older version. It prints the version it replaced.
promote_release() {
  local version="$1" work
  work="$(mktemp -d)"
  r2_get "releases/Nextshot-$version.json" "$work/record.json" ||
    rel_fail "R2 has no record for $version. Nothing to promote."
  record_valid "$work/record.json" || rel_fail "the record for $version is not valid. Not promoting it."
  [[ "$(record_field "$work/record.json" version)" == "$version" ]] ||
    rel_fail "the record for $version names another version."
  release_previous=""
  if r2_get latest.json "$work/previous.json" && record_valid "$work/previous.json"; then
    release_previous="$(record_field "$work/previous.json" version)"
    release_previous_file="$(mktemp -t nextshot-previous-latest.XXXXXX)"
    cp "$work/previous.json" "$release_previous_file"
  fi
  r2_put latest.json "$work/record.json" application/json
  rm -rf "$work"
}
release_previous=""
release_previous_file=""

# restore_latest: puts back the latest.json that promote_release replaced. When
# there was none, it removes the new one, so the site is as it was before.
restore_latest() {
  if [[ -n "$release_previous" && -s "$release_previous_file" ]]; then
    r2_put latest.json "$release_previous_file" application/json
    echo "release: latest.json is back at $release_previous" >&2
  else
    r2_delete latest.json
    echo "release: there was no earlier latest.json, so it was removed" >&2
  fi
}

# --- Checks on a built DMG ------------------------------------------------

# check_dmg <dmg> <version> <build>
# Notarization, Gatekeeper, and what is inside: the bundle ID, version, and
# build of the app, and its signature.
check_dmg() {
  local dmg="$1" version="$2" build="$3" mount app problem=""
  xcrun stapler validate "$dmg" >/dev/null 2>&1 || rel_fail "$(basename "$dmg") has no stapled notarization ticket"
  spctl --assess --type open --context context:primary-signature "$dmg" 2>/dev/null ||
    rel_fail "Gatekeeper refuses $(basename "$dmg")"
  mount="$(mktemp -d)"
  hdiutil attach -nobrowse -readonly -noverify -mountpoint "$mount" "$dmg" >/dev/null 2>&1 ||
    rel_fail "could not mount $(basename "$dmg")"
  app="$mount/Nextshot.app"
  if [[ ! -d "$app" ]]; then
    problem="no Nextshot.app in the image"
  elif [[ "$(plist_value "$app" CFBundleIdentifier)" != "com.drewschulz.nextshot" ]]; then
    problem="the app has bundle ID $(plist_value "$app" CFBundleIdentifier)"
  elif [[ "$(plist_value "$app" CFBundleShortVersionString)" != "$version" ]]; then
    problem="the app says version $(plist_value "$app" CFBundleShortVersionString), not $version"
  elif [[ "$(plist_value "$app" CFBundleVersion)" != "$build" ]]; then
    problem="the app says build $(plist_value "$app" CFBundleVersion), not $build"
  elif ! codesign --verify --deep "$app" 2>/dev/null; then
    problem="the app signature does not verify"
  elif ! spctl --assess --type execute "$app" 2>/dev/null; then
    # Not codesign --strict: the image layout puts a Finder attribute
    # (com.apple.FinderInfo) on the app inside the DMG, which --strict refuses
    # and Gatekeeper accepts (seen on 2026-10-25).
    problem="Gatekeeper refuses the app"
  fi
  hdiutil detach "$mount" -quiet >/dev/null 2>&1 || hdiutil detach "$mount" -force -quiet >/dev/null 2>&1 || true
  rmdir "$mount" 2>/dev/null || true
  [[ -z "$problem" ]] || rel_fail "$(basename "$dmg"): $problem"
}

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }
