#!/usr/bin/python3
"""Worst second of Energy Impact for each island animation, the way Activity Monitor's Energy tab
counts it: NotchIsland's coalition, 100 × (CPU seconds + 0.0002 × wake-ups) per second (the
default.plist energy constants on Apple silicon), sampled every 0.1 s, maximum over any 1 s window.

    anim.py [scenario ...]
"""
import os, subprocess, sys, time, threading
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coalition import coalition_id, read, TICK
from bench import url

SCENARIOS = {
    "open-home": [("open?page=home", 2.5), ("close", 3)],
    "open-timer": [("open?page=timer", 2.5), ("close", 3)],
    "open-shelf": [("open?page=shelf", 2.5), ("close", 3)],
    "hover": [("demo/hover?inside=1", 2.5), ("demo/hover?inside=0", 3)],
    "siri": [("siri", 2.5), ("close", 3)],
    "siri-apps": [("demo/siriapps", 3), ("close", 3)],
    "siri-clipboard": [("demo/siriclipboard", 2.5), ("close", 3)],
    "volume": [("demo/volume?level=0.3", 0.5), ("demo/volume?level=0.6", 0.5), ("demo/volume?level=0.8", 3)],
    "battery": [("demo/charging", 4), ("demo/reset", 2)],
    "airpods": [("demo/airpods", 5), ("close", 2)],
    "timer-done": [("demo/timerdone", 8), ("demo/reset", 2)],
    "settings": [("settings/general", 4), ("settings/widgets", 4), ("close", 3)],
    # Someone flicking the island open and shut, fast.
    "spam-open": [("open?page=home", 0.25), ("close", 0.25)] * 10 + [("close", 2)],
    "spam-open-slow": [("open?page=home", 0.6), ("close", 0.6)] * 8 + [("close", 2)],
    "spam-hover": [("demo/hover?inside=1", 0.3), ("demo/hover?inside=0", 0.3)] * 10 + [("demo/hover?inside=0", 2)],
    "spam-siri": [("siri", 0.4), ("close", 0.4)] * 8 + [("close", 2)],
    "spam-pages": [("open?page=home", 0.4), ("open?page=timer", 0.4), ("open?page=shelf", 0.4)] * 4 + [("close", 2)],
    "spam-volume": [(f"demo/volume?level={0.1 + (i % 9) / 10}", 0.12) for i in range(30)] + [("demo/reset", 2)],
}

def main():
    names = sys.argv[1:] or list(SCENARIOS)
    pid = int(subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0])
    cid = coalition_id(pid)
    for name in names:
        samples = []; stop = False
        def sampler():
            prev = read(cid); pt = time.time()
            while not stop:
                time.sleep(0.1)
                cur = read(cid); t = time.time()
                samples.append((t, (cur["cpu_time"] - prev["cpu_time"]) * TICK / 1e9,
                                cur["platform_idle_wakeups"] - prev["platform_idle_wakeups"], t - pt))
                prev, pt = cur, t
        th = threading.Thread(target=sampler, daemon=True); th.start()
        time.sleep(0.5)
        for route, wait in SCENARIOS[name]:
            url(route); time.sleep(wait)
        stop = True; th.join()
        total_cpu = sum(s[1] for s in samples)
        def worst(span):
            best = 0.0
            for i in range(len(samples)):
                window = [s for s in samples[i:] if s[0] - samples[i][0] < span]
                dt = sum(s[3] for s in window)
                if dt < span * 0.9: break
                best = max(best, 100 * (sum(s[1] for s in window) + 0.0002 * sum(s[2] for s in window)) / dt)
            return best
        print(f"{name:16} worst 1 s {worst(1.0):6.1f}   worst 5 s (Activity Monitor) {worst(5.0):6.1f}   CPU {total_cpu * 1000:6.0f} ms", flush=True)

if __name__ == "__main__":
    main()
