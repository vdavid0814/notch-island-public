#!/bin/bash
# Builds NotchIsland.dmg from build/NotchIsland.app: the app and a link to /Applications, the
# volume and the .dmg file wearing the app's icon (Support/AppIcon.icns).
#
#   CONFIG=release Scripts/build.sh && Scripts/make-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
APP="$ROOT/build/NotchIsland.app"
DMG="$ROOT/NotchIsland.dmg"
ICON="$ROOT/Support/AppIcon.icns"
[[ -d "$APP" ]] || { echo "error: build the app first (CONFIG=release Scripts/build.sh)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'hdiutil detach "$WORK/mnt" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT
xcrun swiftc -O "$ROOT/Scripts/set-icon.swift" -o "$WORK/set-icon"

mkdir -p "$WORK/stage"
cp -R "$APP" "$WORK/stage/"
ln -s /Applications "$WORK/stage/Applications"

echo "==> image"
hdiutil create -quiet -volname NotchIsland -srcfolder "$WORK/stage" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
mkdir "$WORK/mnt"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$WORK/mnt" "$WORK/rw.dmg"
# The mounted volume's icon (.VolumeIcon.icns, flagged as custom).
"$WORK/set-icon" "$ICON" "$WORK/mnt"
hdiutil detach -quiet "$WORK/mnt"

echo "==> compressing"
rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
# The .dmg file's own icon here (a download loses it: it lives in extended attributes).
"$WORK/set-icon" "$ICON" "$DMG"
echo "==> $DMG"
