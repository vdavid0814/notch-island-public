#!/bin/bash
# Builds NotchIsland.dmg from build/NotchIsland.app: the app and a link to /Applications in a dark
# window with a drag arrow (Scripts/dmg-background.swift), the volume and the .dmg file wearing the
# app's icon (Support/AppIcon.icns).
#
#   CONFIG=release Scripts/build.sh && Scripts/make-dmg.sh
#
# Releases keep their users' permissions only when every one is signed by the same certificate:
# macOS keys Accessibility, Input Monitoring and the others on the signature's designated
# requirement. The one every release must have is pinned in Support/release-requirement.txt; a
# build signed otherwise is refused (ALLOW_OTHER_SIGNER=1 makes a test image anyway).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
APP="$ROOT/build/NotchIsland.app"
DMG="$ROOT/NotchIsland.dmg"
ICON="$ROOT/Support/AppIcon.icns"
PINNED="$ROOT/Support/release-requirement.txt"
[[ -d "$APP" ]] || { echo "error: build the app first (CONFIG=release Scripts/build.sh)" >&2; exit 1; }

echo "==> signature"
ACTUAL="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
if [[ "$ACTUAL" != "$(cat "$PINNED")" ]]; then
  cat >&2 <<WARN

  !!  This build is not signed like the releases before it:
  !!    built:  $ACTUAL
  !!    pinned: $(cat "$PINNED")
  !!  Users updating to it would lose Accessibility, Input Monitoring and the other
  !!  permissions. Build on the Mac with the release certificate (SIGN_ID).
WARN
  if [[ "${ALLOW_OTHER_SIGNER:-}" != 1 ]]; then exit 1; fi
  echo "    ALLOW_OTHER_SIGNER=1: making a test image anyway" >&2
fi

echo "==> report addresses"
# A release without them cannot send a bug report, a feature request or any diagnostics: About's
# buttons stay greyed out ("This build cannot send reports") and Detailed Diagnostics cannot be
# turned on. 0.8.2 went out so (built where the git-ignored Support/telemetry.json and
# Support/diagnostics-webhooks.json were missing). ALLOW_NO_REPORTS=1 makes a test image anyway.
PLIST="$APP/Contents/Info.plist"
MISSING=()
/usr/libexec/PlistBuddy -c "Print :NITelemetry:sentryDSN" "$PLIST" >/dev/null 2>&1 || MISSING+=("Sentry (Support/telemetry.json)")
/usr/libexec/PlistBuddy -c "Print :NITelemetry:mixpanelToken" "$PLIST" >/dev/null 2>&1 || MISSING+=("Mixpanel (Support/telemetry.json)")
/usr/libexec/PlistBuddy -c "Print :NIDiagnosticsConfig" "$PLIST" >/dev/null 2>&1 \
  || /usr/libexec/PlistBuddy -c "Print :NIDiagnosticsWebhookURL" "$PLIST" >/dev/null 2>&1 \
  || MISSING+=("Discord (Support/diagnostics-webhooks.json)")
if (( ${#MISSING[@]} )); then
  printf '\n  !!  This build has no address for: %s\n  !!  Its users could not report a bug or send diagnostics.\n\n' "${MISSING[*]}" >&2
  if [[ "${ALLOW_NO_REPORTS:-}" != 1 ]]; then exit 1; fi
  echo "    ALLOW_NO_REPORTS=1: making a test image anyway" >&2
fi

WORK="$(mktemp -d)"
trap 'hdiutil detach "$WORK/mnt" -quiet -force 2>/dev/null || true; rm -rf "$WORK"' EXIT
xcrun swiftc -O "$ROOT/Scripts/set-icon.swift" -o "$WORK/set-icon"
xcrun swiftc -O "$ROOT/Scripts/dmg-background.swift" -o "$WORK/dmg-background"

mkdir -p "$WORK/stage/.background"
cp -R "$APP" "$WORK/stage/"
ln -s /Applications "$WORK/stage/Applications"
# The background at 1x and 2x in one TIFF: Finder picks the one for the screen.
"$WORK/dmg-background" "$WORK/bg.png" 1
"$WORK/dmg-background" "$WORK/bg@2x.png" 2
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/stage/.background/background.tiff" 2>/dev/null

echo "==> image"
hdiutil create -quiet -volname NotchIsland -srcfolder "$WORK/stage" -fs HFS+ -format UDRW -size 200m -ov "$WORK/rw.dmg"
mkdir "$WORK/mnt"
# Mounted where Finder sees it (under /Volumes) so it can lay out the window.
DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | awk '/Apple_HFS/ {print $1}')"
VOLUME="/Volumes/NotchIsland"
for _ in $(seq 1 20); do [[ -d "$VOLUME" ]] && break; sleep 0.25; done
# The mounted volume's icon (.VolumeIcon.icns, flagged as custom).
"$WORK/set-icon" "$ICON" "$VOLUME"

echo "==> window layout"
# 660 × 400 pt content, icons at 128 pt over the background's glows; no toolbar, no status bar.
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "NotchIsland"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 548}
    set options to the icon view options of container window
    set arrangement of options to not arranged
    set icon size of options to 112
    set text size of options to 13
    set background picture of options to file ".background:background.tiff"
    set position of item "NotchIsland.app" of container window to {165, 190}
    set position of item "Applications" of container window to {495, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach -quiet "$DEVICE" || hdiutil detach -quiet -force "$DEVICE"

echo "==> compressing"
rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
# The .dmg file's own icon here (a download loses it: it lives in extended attributes).
"$WORK/set-icon" "$ICON" "$DMG"
echo "==> $DMG"
