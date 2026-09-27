#!/bin/bash
# Makes this Mac's numbers the reference every user's report is compared with, for the version
# running now (the one published on GitHub). Run it after NotchIsland has run for a few hours as
# usual (the energy averages need the time), then commit and push docs/diagnostics-baseline.json.
#
#   Scripts/publish-baseline.sh
#
# The `rules` of the file already in docs/ (thresholds tuned by hand) are kept.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$HOME/Library/Application Support/NotchIsland/diagnostics-baseline.json"
DEST="$ROOT/docs/diagnostics-baseline.json"

pgrep -x NotchIsland >/dev/null || { echo "error: NotchIsland is not running" >&2; exit 1; }
# Only a Mac marked as the reference may write one (a link on a web page cannot).
defaults write com.davidvarga.notchisland ni2.diagnostics.reference -bool true

BEFORE="$(stat -f %m "$OUT" 2>/dev/null || echo 0)"
open "notchisland://diagnostics/baseline"
echo "==> measuring (about 10 s)…"
for _ in $(seq 1 60); do
  sleep 1
  [[ "$(stat -f %m "$OUT" 2>/dev/null || echo 0)" != "$BEFORE" ]] && break
done
[[ "$(stat -f %m "$OUT" 2>/dev/null || echo 0)" != "$BEFORE" ]] || { echo "error: no baseline was written (see Scripts/logs.sh)" >&2; exit 1; }

python3 - "$OUT" "$DEST" <<'PY'
import json, os, sys
new_path, dest = sys.argv[1], sys.argv[2]
new = json.load(open(new_path))
if os.path.exists(dest):
    old = json.load(open(dest))
    if old.get("rules"):
        new["rules"] = old["rules"]
json.dump(new, open(dest, "w"), indent=2, sort_keys=True)
print(f"==> reference for v{new['version']} ({new['build']}) on {new['machine']}, {new['uptimeHours']} h of running")
for key, value in sorted(new["metrics"].items()):
    print(f"    {key:26} {value}")
if new["uptimeHours"] < 2:
    print("    ⚠ NotchIsland has run for less than 2 hours: the energy numbers are rough.")
PY
echo "==> wrote ${DEST#"$ROOT"/} — commit and push it so every copy compares with it"
