#!/usr/bin/python3
"""Each demo event on its own: CPU ms, GPU ms, idle wakeups, peak Energy Impact (top POWER, per second) and MB.
events_bench.py <label> [seconds-per-event] [event …]   (rows also written to <label>.events.json)"""
import subprocess, sys, time, os, threading, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import pid, rusage, url, gpu_ns

EVENTS = ["demo/volume?level=0.4", "demo/brightness?level=0.6", "demo/charging", "demo/unplug", "demo/low",
          "demo/timerdone", "demo/drop", "demo/airpods", "demo/airpodsmode?mode=anc", "demo/airpodsmode?mode=transparency",
          "demo/airpodsmode?mode=adaptive", "demo/airpodsmode?mode=off", "demo/media", "demo/siriapps", "demo/siriclipboard"]

def main():
    label = sys.argv[1]; seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 5
    events = sys.argv[3:] or EVENTS
    p = pid(); assert p
    power = {}
    top = subprocess.Popen(["top", "-pid", str(p), "-l", str(int(len(events) * (seconds + 1.5)) + 5), "-s", "1", "-stats", "pid,power"],
                           stdout=subprocess.PIPE, text=True)
    def read():
        for line in top.stdout:
            parts = line.split()
            if len(parts) == 2 and parts[0] == str(p):
                try: power[int(time.time())] = float(parts[1])
                except ValueError: pass
    threading.Thread(target=read, daemon=True).start()
    time.sleep(2)
    print(f"== {label}")
    print(f"{'event':36} {'CPU ms':>7} {'GPU ms':>7} {'wakes':>6} {'E max':>6} {'MB':>6}")
    rows = []
    for event in events:
        r0 = rusage(p); g0 = gpu_ns(p); t0 = time.time()
        url(event)
        time.sleep(seconds)
        if "siri" in event or event.startswith("settings"):
            url("close"); time.sleep(1.5)
        r1 = rusage(p); g1 = gpu_ns(p); t1 = time.time()
        peak = max([v for t, v in power.items() if t0 - 0.5 <= t <= t1 + 1] or [0])
        row = dict(event=event, cpu_ms=round((r1[0]-r0[0])/1e6), gpu_ms=round((g1-g0)/1e6), wakeups=r1[2]-r0[2], ei_peak=peak, mb=round(r1[1], 1))
        rows.append(row)
        print(f"{event:36} {row['cpu_ms']:7} {row['gpu_ms']:7} {row['wakeups']:6} {peak:6.1f} {r1[1]:6.1f}", flush=True)
        url("demo/reset"); time.sleep(1.5)
    json.dump(rows, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), label + ".events.json"), "w"), indent=1)

if __name__ == "__main__":
    main()
