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
# Usage: site/smoke.sh [--url URL] [--video NAME] [--guides|--guides-only]
# Guides checks are opt-in, so app-only publishing works before Guides exists.
#   --url    the site to test (default: $NEXTSHOT_SITE_URL, else https://nextshot.dev)
#   --video  also check a Range request for /media/NAME (the page deploy passes it)
set -uo pipefail

url="${NEXTSHOT_SITE_URL:-https://nextshot.dev}"
video=""
guides=0 guides_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) url="$2"; shift 2 ;;
    --video) video="$2"; shift 2 ;;
    --guides) guides=1; shift ;;
    --guides-only) guides=1; guides_only=1; shift ;;
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

if ((guides_only == 0)); then
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

fi

if ((guides)); then
  guide_work="$(mktemp -d)"
  trap 'rm -rf "$guide_work"' EXIT
  for path in /guides/ /guides/first-handoff/ /guides/install/ /guides/connect-agent/ /guides/multiple-captures/ /guides/reuse-rounds/ /guides/shortcuts/ /guides/troubleshooting/; do
    check 200 "$(status "$url$path")" "guide $path"
    check "noindex, nofollow" "$(header X-Robots-Tag "$url$path")" "guide noindex $path"
    get -fsS -A "$ua" "$url$path" >>"$guide_work/pages.html" || failed=1
  done
  # Parse actual links, so a missing CSS build cannot pass as HTML fallback.
  python3 -I - "$guide_work/pages.html" >"$guide_work/assets" <<'PYASSETS'
from html.parser import HTMLParser
import sys
class Assets(HTMLParser):
    paths=set()
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if tag=='link' and 'stylesheet' in a.get('rel','').split(): self.paths.add(a.get('href',''))
        if tag in ('video','source') and a.get('src','').split('?')[0].endswith(('.mp4','.webm')): self.paths.add(a['src'])
p=Assets(); p.feed(open(sys.argv[1]).read())
css=[s for s in p.paths if s.startswith('/guides/') and s.endswith('.css')]
if not css: raise SystemExit('Guides has no stylesheet')
for s in sorted(p.paths):
    if s.startswith('/guides/'): print(s)
PYASSETS
  [[ $? == 0 && -s "$guide_work/assets" ]] || { echo "FAIL  guide assets were not found" >&2; failed=1; }
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    check 200 "$(status "$url$path")" "guide asset $path"
    case "$path" in
      *.css) check text/css "$(header Content-Type "$url$path" | cut -d';' -f1)" "CSS content type $path" ;;
      *.mp4|*.webm) check 206 "$(status -r 0-31 "$url$path")" "guide clip Range $path" ;;
    esac
  done <"$guide_work/assets"
  for path in /guides/pagefind/pagefind.js /guides/pagefind/pagefind-entry.json; do
    check 200 "$(status "$url$path")" "search asset $path"
  done
  get -fsS -A "$ua" "$url/guides/pagefind/pagefind-entry.json" >"$guide_work/search.json" || failed=1
  python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d.get("languages"), "empty Pagefind languages"' "$guide_work/search.json" || { echo "FAIL  search index is empty" >&2; failed=1; }
  check 200 "$(status "$url/guides/resources/nextshot-shortcuts.pdf")" "shortcuts PDF"
  check application/pdf "$(header Content-Type "$url/guides/resources/nextshot-shortcuts.pdf" | cut -d';' -f1)" "PDF content type"
  check '%PDF-' "$(get -s -A "$ua" -r 0-4 "$url/guides/resources/nextshot-shortcuts.pdf" | head -c 5)" "PDF bytes"
  check 404 "$(status "$url/guides/this-page-must-not-exist/")" "real guide 404"
  check "noindex, nofollow" "$(header X-Robots-Tag "$url/guides/this-page-must-not-exist/")" "404 noindex"
fi

((failed == 0)) || { echo "smoke test failed" >&2; exit 1; }
echo "Live: $url (${version:-Guides only})"
