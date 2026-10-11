#!/bin/bash
# Photographs the island over each drawn preview wallpaper, for Settings' pictures
# (Support/SettingsPictures, copied into the app by build.sh):
#   island-<desktop>-<style>-<size>.jpg        the open island, empty, in each surface style at each size
#   activity-<desktop>-<style>-<activity>.jpg  each live activity in the notch
#   idle-<desktop>.jpg                         the bare notch
#   geometry.json                              the open island's outline at each size
#
# The running build shows each one over a drawn desktop that covers the top of the screen
# (notchisland://demo/picture, `DemoDirector`), so the pictures hold nothing of this Mac's desktop
# or menu bar; the settings it changes are put back at the end. Takes about four minutes, during
# which the top of the screen is covered. Needs Screen Recording for the terminal it runs in.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/NotchIsland.app"
OUT="$ROOT/Support/SettingsPictures"
# The scene's size (`DemoDirector.pictureSize`) and the stored pictures' width in pixels.
WIDTH=800
HEIGHT=450
STORED=720
# A live activity's picture: the middle of the scene (`DemoDirector.activityPictureSize`).
ACTIVITY_WIDTH=480
ACTIVITY_HEIGHT=160
ACTIVITY_STORED=600

pgrep -x NotchIsland >/dev/null || { echo "error: NotchIsland is not running (Scripts/run.sh)" >&2; exit 1; }
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
SCREEN="$(xcrun swift -e 'import AppKit; print(Int(NSScreen.main?.frame.width ?? 0))')"
[[ "$SCREEN" -gt "$WIDTH" ]] || { echo "error: no screen wider than $WIDTH pt" >&2; exit 1; }
X=$(( (SCREEN - WIDTH) / 2 ))
ACTIVITY_X=$(( (SCREEN - ACTIVITY_WIDTH) / 2 ))
GEOMETRY="$(xcrun swift -e 'import Foundation; print(NSTemporaryDirectory())')notchisland-picture-geometry.json"

mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'open -a "$APP" "notchisland://demo/picture?on=0"; rm -rf "$WORK"' EXIT

# ONLY=<activity> retakes that live activity's pictures alone.
ONLY="${ONLY:-}"
[[ -n "$ONLY" ]] || rm -f "$OUT"/*.jpg "$OUT/geometry.json" "$GEOMETRY"
for desktop in system systemLight checkerboard; do
  [[ -z "$ONLY" ]] || continue
  open -a "$APP" "notchisland://demo/picture?desktop=$desktop&style=black&activity=idle"
  sleep 2.2
  screencapture -x -R "$X,0,$WIDTH,$HEIGHT" "$WORK/shot.png"
  sips -s format jpeg -s formatOptions 82 --resampleWidth "$STORED" "$WORK/shot.png" --out "$OUT/idle-$desktop.jpg" >/dev/null
  echo "==> idle-$desktop.jpg"
  for style in smoked black fade; do
    for size in extraSmall small compact standard large; do
      open -a "$APP" "notchisland://demo/picture?desktop=$desktop&style=$style&size=$size"
      # The island at its new size, and its glass over the desktop under it.
      sleep 2.2
      screencapture -x -R "$X,0,$WIDTH,$HEIGHT" "$WORK/shot.png"
      sips -s format jpeg -s formatOptions 82 --resampleWidth "$STORED" "$WORK/shot.png" \
        --out "$OUT/island-$desktop-$style-$size.jpg" >/dev/null
      echo "==> island-$desktop-$style-$size.jpg"
    done
    for activity in nowPlaying airPods volumeBanner volumePill power; do
      open -a "$APP" "notchisland://demo/picture?desktop=$desktop&style=$style&activity=$activity"
      sleep 2.2
      screencapture -x -R "$ACTIVITY_X,0,$ACTIVITY_WIDTH,$ACTIVITY_HEIGHT" "$WORK/shot.png"
      sips -s format jpeg -s formatOptions 82 --resampleWidth "$ACTIVITY_STORED" "$WORK/shot.png" \
        --out "$OUT/activity-$desktop-$style-$activity.jpg" >/dev/null
      echo "==> activity-$desktop-$style-$activity.jpg"
    done
  done
done
if [[ -n "$ONLY" ]]; then
  for desktop in system systemLight checkerboard; do
    for style in smoked black fade; do
      open -a "$APP" "notchisland://demo/picture?desktop=$desktop&style=$style&activity=$ONLY"
      sleep 2.2
      screencapture -x -R "$ACTIVITY_X,0,$ACTIVITY_WIDTH,$ACTIVITY_HEIGHT" "$WORK/shot.png"
      sips -s format jpeg -s formatOptions 82 --resampleWidth "$ACTIVITY_STORED" "$WORK/shot.png" \
        --out "$OUT/activity-$desktop-$style-$ONLY.jpg" >/dev/null
      echo "==> activity-$desktop-$style-$ONLY.jpg"
    done
  done
  exit 0
fi
cp "$GEOMETRY" "$OUT/geometry.json"
