#!/bin/bash
# Runs the Swift Testing suite. Extra arguments go to `swift test` (e.g. --filter AppCommand).
#
# The widget snapshots (WidgetSnapshotTests) are exact only in a process of their own: suites that
# draw before them shift a few values by 1 in 255. They run only with NI_SNAPSHOTS set (verify, or
# record to write them). Without a --filter, the suite runs without them, then they run alone as a
# second step; the run fails if either does. A --filter that selects them
# does the same two steps.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

cd "$ROOT"

filtered=false
filter=""
previous=""
unfiltered=()
for argument in ${@+"$@"}; do
    if [[ $previous == --filter ]]; then filtered=true; filter="$argument"
    elif [[ $argument == --filter=* ]]; then filtered=true; filter="${argument#--filter=}"
    elif [[ $argument != --filter ]]; then unfiltered+=("$argument"); fi
    previous="$argument"
done

drawing=(WidgetSnapshotTests)
if $filtered && ! grep -Eq -- "$filter" <<< "$(printf 'NotchIslandKitTests.%s/\n' "${drawing[@]}")"; then
    exec xcrun swift test ${@+"$@"}
fi

status=0
env -u NI_SNAPSHOTS xcrun swift test ${@+"$@"} || status=$?
# Each in a process of its own.
for suite in "${drawing[@]}"; do
    if ! $filtered || grep -Eq -- "$filter" <<< "NotchIslandKitTests.$suite/"; then
        NI_SNAPSHOTS="${NI_SNAPSHOTS:-verify}" xcrun swift test ${unfiltered[@]+"${unfiltered[@]}"} --filter "$suite" || status=$?
    fi
done
exit "$status"
