#!/bin/bash
# Samples NotchIsland's energy use to a CSV, for watching it over hours on battery.
#
#   Scripts/energy-monitor.sh [interval-seconds] [output.csv]
#   Scripts/energy-monitor.sh --summary [output.csv]
#
# One row per interval: time, battery %, power source, app pid, cumulative CPU seconds, physical
# footprint (MB), idle wakeups (cumulative), Energy Impact (top's POWER column, averaged over the
# sampling window), and the MediaRemote adapter's CPU seconds and RSS. Nothing here needs sudo.
# Each row also names the scene: the apps playing audio (coreaudiod's audio-out assertions), "video"
# while something holds a display wake lock (a playing video), and "fullscreen" while a full-screen
# window is on the built-in display. `--scenes` compares CPU, wakeups and memory per scene.
#
# The summary turns the cumulative counters into per-interval rates, grouped by app pid (every
# rebuild is a new pid, so versions compare side by side).
set -euo pipefail

OUT_DEFAULT="$HOME/Library/Logs/NotchIsland/energy.csv"

summary() {
  local csv="${1:-$OUT_DEFAULT}"
  /usr/bin/python3 - "$csv" <<'PY'
import csv, sys, collections
rows = list(csv.DictReader(open(sys.argv[1])))
if len(rows) < 2:
    sys.exit("not enough samples yet")
by_pid = collections.OrderedDict()
for r in rows:
    by_pid.setdefault(r["pid"], []).append(r)
print(f"{'pid':>7} {'from':>8} {'to':>8} {'min':>5} {'on batt':>7} {'CPU %':>6} {'wake/s':>7} {'energy':>7} {'MB':>6} {'MB 1st':>6} {'MB last':>7} {'MB max':>6} {'adapter CPU %':>13} {'batt drop':>9} {'%/h batt':>8}")
for pid, rs in by_pid.items():
    if pid == "-" or len(rs) < 2:
        continue
    a, b = rs[0], rs[-1]
    t0, t1 = float(a["epoch"]), float(b["epoch"])
    dt = max(t1 - t0, 1)
    cpu = (float(b["cpu_s"]) - float(a["cpu_s"])) / dt * 100
    wake = (float(b["idle_wakeups"]) - float(a["idle_wakeups"])) / dt
    energy = sum(float(r["energy_impact"]) for r in rs) / len(rs)
    mb = sum(float(r["footprint_mb"]) for r in rs) / len(rs)
    # Leak check: the first and the last tenth of the run (at least one sample each), and the peak.
    k = max(1, len(rs) // 10)
    mb_first = sum(float(r["footprint_mb"]) for r in rs[:k]) / k
    mb_last = sum(float(r["footprint_mb"]) for r in rs[-k:]) / k
    mb_max = max(float(r["footprint_mb"]) for r in rs)
    # Battery drain per hour, over the stretches spent on battery only.
    batt_drop, batt_time = 0.0, 0.0
    for x, y in zip(rs, rs[1:]):
        if x["source"] == "Battery" and y["source"] == "Battery":
            batt_drop += float(x["battery_pct"]) - float(y["battery_pct"])
            batt_time += float(y["epoch"]) - float(x["epoch"])
    per_hour = batt_drop / (batt_time / 3600) if batt_time > 600 else float("nan")
    try:
        acpu = (float(b["adapter_cpu_s"]) - float(a["adapter_cpu_s"])) / dt * 100
    except ValueError:
        acpu = float("nan")
    batt = sum(1 for r in rs if r["source"] == "Battery") * 100 // len(rs)
    drop = float(a["battery_pct"]) - float(b["battery_pct"])
    print(f"{pid:>7} {a['time'][11:19]:>8} {b['time'][11:19]:>8} {dt/60:5.0f} {batt:6d}% {cpu:6.2f} {wake:7.2f} {energy:7.2f} {mb:6.1f} {mb_first:6.0f} {mb_last:7.0f} {mb_max:6.0f} {acpu:13.2f} {drop:8.0f}% {per_hour:8.1f}")
PY
}

scenes() {
  local csv="${1:-$OUT_DEFAULT}"
  /usr/bin/python3 - "$csv" <<'PY'
import csv, sys, collections
rows = [r for r in csv.DictReader(open(sys.argv[1])) if r.get("scene") and r["pid"] != "-"]
acc = collections.OrderedDict()
for a, b in zip(rows, rows[1:]):
    if a["pid"] != b["pid"] or not a["cpu_s"] or not b["cpu_s"]:
        continue
    dt = float(b["epoch"]) - float(a["epoch"])
    if dt <= 0 or dt > 600:
        continue
    k = (b["pid"], b["scene"])
    s = acc.setdefault(k, {"dt": 0, "cpu": 0, "wake": 0, "mb": [], "power": [], "acpu": 0, "batt": 0, "bdt": 0})
    s["dt"] += dt
    s["cpu"] += float(b["cpu_s"]) - float(a["cpu_s"])
    try: s["wake"] += float(b["idle_wakeups"]) - float(a["idle_wakeups"])
    except ValueError: pass
    if b["footprint_mb"]: s["mb"].append(float(b["footprint_mb"]))
    if b["energy_impact"]: s["power"].append(float(b["energy_impact"]))
    try: s["acpu"] += float(b["adapter_cpu_s"]) - float(a["adapter_cpu_s"])
    except ValueError: pass
    if a["source"] == b["source"] == "Battery":
        s["batt"] += float(a["battery_pct"]) - float(b["battery_pct"]); s["bdt"] += dt
print(f"{'pid':>7} {'scene':<28} {'min':>5} {'CPU %':>6} {'wake/s':>7} {'energy':>7} {'MB avg':>6} {'MB max':>6} {'adapter %':>9} {'%/h batt':>8}")
for (pid, scene), s in acc.items():
    dt = s["dt"]
    mb = sum(s["mb"]) / len(s["mb"]) if s["mb"] else float("nan")
    mx = max(s["mb"]) if s["mb"] else float("nan")
    pw = sum(s["power"]) / len(s["power"]) if s["power"] else float("nan")
    ph = s["batt"] / (s["bdt"] / 3600) if s["bdt"] > 600 else float("nan")
    print(f"{pid:>7} {scene[:28]:<28} {dt/60:5.0f} {s['cpu']/dt*100:6.2f} {s['wake']/dt:7.2f} {pw:7.2f} {mb:6.1f} {mx:6.0f} {s['acpu']/dt*100:9.2f} {ph:8.1f}")
PY
}

if [[ "${1:-}" == "--scenes" ]]; then
  scenes "${2:-$OUT_DEFAULT}"
  exit 0
fi

if [[ "${1:-}" == "--summary" ]]; then
  summary "${2:-$OUT_DEFAULT}"
  exit 0
fi

INTERVAL="${1:-60}"
OUT="${2:-$OUT_DEFAULT}"
mkdir -p "$(dirname "$OUT")"
HEADER="time,epoch,battery_pct,source,pid,cpu_s,footprint_mb,idle_wakeups,energy_impact,adapter_cpu_s,adapter_rss_mb,scene"
if [[ ! -s "$OUT" ]]; then
  echo "$HEADER" > "$OUT"
elif ! head -1 "$OUT" | grep -q ',scene$'; then
  # Older files: add the column (their rows have no scene).
  /usr/bin/sed -i '' "1s/.*/$HEADER/" "$OUT"
fi

# The full-screen probe, compiled once next to the log.
PROBE="$(dirname "$OUT")/fullscreen-probe"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ! -x "$PROBE" || "$ROOT/Scripts/fullscreen-probe.swift" -nt "$PROBE" ]]; then
  DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc -O "$ROOT/Scripts/fullscreen-probe.swift" -o "$PROBE" 2>/dev/null || true
fi

# "Music", "Music+video", "video+fullscreen", "idle"...
scene() {
  local a audio="" video=""
  a=$(pmset -g assertions)
  audio=$(grep -A1 'audio.*preventuseridlesleep' <<< "$a" | grep -Eo 'Created for PID: [0-9]+' | grep -Eo '[0-9]+' | sort -u \
    | while read -r p; do ps -o comm= -p "$p" 2>/dev/null | xargs basename 2>/dev/null; done | sort -u | paste -sd+ -)
  # Per-process assertions only (the totals at the top list every type, with a count).
  if grep -E '^ +pid [0-9]+\(' <<< "$a" | grep 'PreventUserIdleDisplaySleep' | grep -vq 'powerd'; then video=video; fi
  local parts=()
  [[ -n "$audio" ]] && parts+=("$audio")
  [[ -n "$video" ]] && parts+=("$video")
  [[ -x "$PROBE" && "$("$PROBE" 2>/dev/null)" == 1 ]] && parts+=(fullscreen)
  if (( ${#parts[@]} )); then (IFS=+; echo "${parts[*]}"); else echo idle; fi
}

# "1:02.35" or "1:02:03.40" (ps TIME) -> seconds
to_seconds() {
  /usr/bin/awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; printf "%.2f", s }' <<< "$1"
}

while true; do
  now=$(date '+%Y-%m-%d %H:%M:%S'); epoch=$(date +%s)
  batt=$(pmset -g batt)
  pct=$(grep -Eo '[0-9]+%' <<< "$batt" | head -1 | tr -d '%')
  if grep -q "Battery Power" <<< "$batt"; then source=Battery; else source=AC; fi
  pid=$(pgrep -x NotchIsland | head -1 || true)
  if [[ -n "$pid" ]]; then
    cpu=$(to_seconds "$(ps -o time= -p "$pid" | tr -d ' ')")
    fp=$(footprint "$pid" 2>/dev/null | grep -m1 -Eo 'Footprint: [0-9.]+ [KMG]B' | awk '{v=$2; if ($3=="KB") v/=1024; if ($3=="GB") v*=1024; printf "%.1f", v}')
    # Two top samples over the interval's first 5 s: the second carries POWER for that window.
    read -r wake power < <(top -l 2 -s 5 -stats pid,idlew,power -pid "$pid" | awk -v p="$pid" '$1==p {gsub(/\+/,"",$2); w=$2; e=$3} END {print w, e}')
    adapter=$(pgrep -f 'mediaremote-adapter.pl .*stream' | head -1 || true)
    if [[ -n "$adapter" ]]; then
      acpu=$(to_seconds "$(ps -o time= -p "$adapter" | tr -d ' ')")
      arss=$(ps -o rss= -p "$adapter" | awk '{printf "%.1f", $1/1024}')
    else
      acpu=""; arss=""
    fi
  else
    pid="-"; cpu=""; fp=""; wake=""; power=""; acpu=""; arss=""
  fi
  echo "$now,$epoch,$pct,$source,$pid,$cpu,${fp:-},${wake:-},${power:-},$acpu,$arss,$(scene)" >> "$OUT"
  sleep "$(( INTERVAL > 5 ? INTERVAL - 5 : 1 ))"
done
