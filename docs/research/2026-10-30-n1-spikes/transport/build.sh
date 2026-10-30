#!/bin/bash
# Build and sign the N1 transport spike. Usage: build.sh <output folder>
# The app and host get the Apple Development identity of Nextshot Dev. The impostor host
# is the same code signed ad hoc, so the app's identity check should reject it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$1"
mkdir -p "$out"
identity="Apple Development: Drew Schulz (Q432TK5FCL)"
swiftc -O -module-name SpikeApp "$here/Identity.swift" "$here/app/main.swift" -o "$out/spike-app"
swiftc -O -module-name SpikeHost "$here/Identity.swift" "$here/host/main.swift" -o "$out/spike-host"
cp "$out/spike-host" "$out/spike-impostor"
codesign --force -s "$identity" -i com.drewschulz.nextshot.dev.spike-app "$out/spike-app"
codesign --force -s "$identity" -i com.drewschulz.nextshot.dev.spike-host "$out/spike-host"
codesign --force -s - -i com.drewschulz.nextshot.dev.spike-host "$out/spike-impostor"
codesign -dv "$out/spike-app" 2>&1 | grep -E "Identifier|TeamIdentifier"
codesign -dv "$out/spike-host" 2>&1 | grep -E "Identifier|TeamIdentifier"
codesign -dv "$out/spike-impostor" 2>&1 | grep -E "Identifier|Signature"
