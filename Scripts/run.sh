#!/bin/bash
# Builds the app (release; CONFIG=debug for a debug build), replaces any running instance and
# launches the fresh build.
# Extra arguments are passed to the app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/NotchIsland.app"

# A release build unless asked otherwise (CONFIG=debug): a debug build takes about three times the
# CPU in Settings and Siri, which is what Activity Monitor then shows.
CONFIG="${CONFIG:-release}" "$ROOT/Scripts/build.sh"

if pgrep -x NotchIsland >/dev/null; then
  echo "==> quitting the running instance"
  pkill -x NotchIsland || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x NotchIsland >/dev/null || break
    sleep 0.2
  done
  if pgrep -x NotchIsland >/dev/null; then
    echo "error: the old instance did not quit" >&2
    exit 1
  fi
fi

echo "==> launching"
open "$APP" --args ${@+"$@"}

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if PID="$(pgrep -x NotchIsland)"; then
    echo "==> NotchIsland is running (pid $PID). Logs: Scripts/logs.sh"
    exit 0
  fi
  sleep 0.2
done

echo "error: NotchIsland did not start. Running the binary directly to show why:" >&2
exec "$APP/Contents/MacOS/NotchIsland" ${@+"$@"}
