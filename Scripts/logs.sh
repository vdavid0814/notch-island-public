#!/bin/bash
# Streams NotchIsland's unified log.
#
#   Scripts/logs.sh           everything
#   Scripts/logs.sh levels    one category: app island window media power levels shelf timers system
set -euo pipefail

PREDICATE='subsystem == "com.davidvarga.notchisland"'
if [[ $# -gt 0 ]]; then
  PREDICATE="$PREDICATE AND category == \"$1\""
fi
exec log stream --style compact --level debug --predicate "$PREDICATE"
