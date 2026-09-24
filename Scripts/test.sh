#!/bin/bash
# Runs the Swift Testing suite. Extra arguments go to `swift test` (e.g. --filter AppCommand).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

cd "$ROOT"
exec xcrun swift test ${@+"$@"}
