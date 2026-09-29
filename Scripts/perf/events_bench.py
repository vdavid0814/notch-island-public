#!/usr/bin/python3
"""Each demo event on its own: CPU ms, peak Energy Impact (top POWER, per second) and MB.
events_bench.py <label> [seconds-per-event] [event …]"""
import subprocess, sys, time, os, threading
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import pid, rusage, url

EVENTS = ["demo/volume?value=0.4", "demo/brightness?value=0.6", "demo/charging", "demo/unplug", "demo/low",
          "demo/timerdone", "demo/drop", "demo/airpods", "demo/media", "demo/siriapps", "demo/siriclipboard"]

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
    print(f"{'event':30} {'CPU ms':>7} {'E max':>6} {'MB':>6}")
    for event in events:
        r0 = rusage(p); t0 = time.time()
        url(event)
        time.sleep(seconds)
        if "siri" in event:
            url("close"); time.sleep(1.5)
        r1 = rusage(p); t1 = time.time()
        peak = max([v for t, v in power.items() if t0 - 0.5 <= t <= t1 + 1] or [0])
        print(f"{event:30} {(r1[0]-r0[0])/1e6:7.0f} {peak:6.1f} {r1[1]:6.1f}", flush=True)
        url("demo/reset"); time.sleep(1.5)

if __name__ == "__main__":
    main()
