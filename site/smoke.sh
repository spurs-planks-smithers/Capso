#!/bin/bash
# Fork: smoke test for nextshot.dev, or for a local Worker. site/deploy.sh and
# scripts/release.sh run it after a change goes live.
#
# It reads /latest.json from the site, then checks the page, the redirect, the
# DMG bytes (SHA-256 and size), Range replies, and that a path cannot reach
# other files in the bucket. The user agent marks these requests as bots on
# /stats. For the live site, curl asks public DNS (1.1.1.1 over HTTPS), because
# this Mac can cache "no such domain" from before the custom domain existed.
#
# Usage: site/smoke.sh [--url URL] [--video NAME]
#   --url    the site to test (default: $NEXTSHOT_SITE_URL, else https://nextshot.dev)
#   --video  also check a Range request for /media/NAME (the page deploy passes it)
set -uo pipefail

url="${NEXTSHOT_SITE_URL:-https://nextshot.dev}"
video=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) url="$2"; shift 2 ;;
    --video) video="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
url="${url%/}"

ua="nextshot-smoke-test"
live=0
[[ "$url" == "https://nextshot.dev" ]] && live=1
get() {
  if ((live)); then curl --doh-url https://1.1.1.1/dns-query "$@"; else curl "$@"; fi
}
status() { get -s -o /dev/null -A "$ua" -w '%{http_code}' "$@"; }
header() { # <name> <curl args...>: one response header value, without the line end
  local name="$1"
  shift
  get -sI -A "$ua" "$@" | awk -v n="$(printf '%s' "$name" | tr 'A-Z' 'a-z')" 'tolower($1) == n ":" { $1 = ""; sub(/^ /, ""); sub(/\r$/, ""); print }'
}
field() { python3 -I -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }

failed=0
check() { # <want> <got> <label>
  if [[ "$2" == "$1" ]]; then echo "ok    $3"; else echo "FAIL  $3 (got '$2', want '$1')" >&2; failed=1; fi
}

# A new custom domain can take a minute to get its certificate.
if ((live)); then
  for _ in $(seq 1 24); do
    [[ "$(status "$url/")" == 200 ]] && break
    sleep 5
  done
fi

check 200 "$(status "$url/")" "page"
check "noindex, nofollow" "$(header X-Robots-Tag "$url/")" "noindex header"

latest="$(get -s -A "$ua" "$url/latest.json")"
version="$(printf '%s' "$latest" | field version 2>/dev/null)"
file="$(printf '%s' "$latest" | field file 2>/dev/null)"
sha="$(printf '%s' "$latest" | field sha256 2>/dev/null)"
size="$(printf '%s' "$latest" | field size 2>/dev/null)"
if [[ -z "$version" || -z "$file" || -z "$sha" || -z "$size" ]]; then
  echo "FAIL  /latest.json has no usable record" >&2
  exit 1
fi
echo "ok    /latest.json says $version ($file)"

check 1 "$(get -s -A "$ua" "$url/" | grep -cF "Version $version")" "page shows Version $version"
check "$url/releases/$file" "$(get -s -o /dev/null -A "$ua" -w '%{redirect_url}' "$url/download")" "/download redirect"
check "$sha" "$(get -s -A "$ua" "$url/releases/$file" | shasum -a 256 | cut -d' ' -f1)" "DMG SHA-256"
check "$size" "$(header Content-Length "$url/releases/$file")" "DMG size (HEAD)"
check 206 "$(status -r 0-1023 "$url/releases/$file")" "DMG range request"
check "bytes 0-1023/$size" "$(get -s -D - -o /dev/null -r 0-1023 -A "$ua" "$url/releases/$file" | awk 'tolower($1) == "content-range:" { sub(/\r$/, ""); print $2 " " $3 }')" "DMG Content-Range"
check 416 "$(status -r "$((size + 10))-$((size + 20))" "$url/releases/$file")" "range past the end"
check 404 "$(status "$url/releases/..%2Flatest.json")" "path cannot leave releases/"
check 404 "$(status "$url/releases/latest.json")" "latest.json is not a release file"
check 404 "$(status "$url/releases/Nextshot-0.0.0.dmg")" "unknown release"
check 200 "$(status "$url/stats")" "stats page"
if ((live)); then
  check 301 "$(status "https://www.nextshot.dev/x")" "www redirect"
fi
if [[ -n "$video" ]]; then
  check 206 "$(status -r 0-1023 "$url/media/$video")" "video range request"
fi

((failed == 0)) || { echo "smoke test failed" >&2; exit 1; }
echo "Live: $url ($version)"
