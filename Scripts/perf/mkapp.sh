#!/bin/bash
# mkapp.sh <binary> <dest.app>: a test copy of build/NotchIsland.app with another binary in it,
# diagnostics reports removed, signed alike — for back-to-back comparisons of builds.
#   swift build -c release --product NotchIsland && Scripts/perf/mkapp.sh .build/release/NotchIsland Scripts/perf/apps/new.app
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
rm -rf "$2"; mkdir -p "$(dirname "$2")"; cp -R "$ROOT/build/NotchIsland.app" "$2"
cp "$1" "$2/Contents/MacOS/NotchIsland"
plutil -remove NIDiagnosticsConfig "$2/Contents/Info.plist" 2>/dev/null || true
plutil -remove NIDiagnosticsWebhookURL "$2/Contents/Info.plist" 2>/dev/null || true
ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
codesign --force --sign "$ID" --timestamp=none --entitlements "$ROOT/Support/NotchIsland.entitlements" "$2" 2>&1 | tail -1
