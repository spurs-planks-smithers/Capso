#!/bin/bash
# Prints the local counts of the on-device summary name (#200, SummaryUseCounter).
# Nothing leaves the Mac. Default domain: Nextshot Dev. For production:
#   NEXTSHOT_FLAGS_DOMAIN=com.drewschulz.nextshot scripts/nextshot-summary-use.sh
domain="${NEXTSHOT_FLAGS_DOMAIN:-com.drewschulz.nextshot.dev}"
out="$(/usr/bin/defaults read "$domain" 2>/dev/null | grep 'summaryUse\.')"
if [ -z "$out" ]; then
  echo "No summary counts yet in $domain."
  exit 0
fi
echo "Domain: $domain"
echo "$out" | sed -E 's/^ *"?summaryUse\.([^"=]*)"? *= *(.*);$/\1: \2/'
