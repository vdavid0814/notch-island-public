#!/usr/bin/python3
"""Worst stretch of Energy Impact for each island animation, the way Activity Monitor's Energy tab
counts it on Apple silicon: the energy NotchIsland's coalition used, in milliwatts (measured:
Activity Monitor's number is this, averaged over its 5 s update; at rest 0.0–0.2, flicking the
island open ~100). Sampled every 0.1 s; the worst 1 s and 5 s windows. CPU time alongside.

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
    "open-battery": [("open?page=battery", 2.5), ("close", 3)],
    "hover": [("demo/hover?inside=1", 2.5), ("demo/hover?inside=0", 3)],
    "siri": [("siri", 2.5), ("close", 3)],
    "siri-apps": [("demo/siriapps", 3), ("close", 3)],
    "siri-clipboard": [("demo/siriclipboard", 2.5), ("close", 3)],
    # Typing a query that reaches apps, commands, settings panes and emoji.
    "siri-search": [("demo/siritype?text=smile", 3), ("close", 3)],
    "volume": [("demo/volume?level=0.3", 0.5), ("demo/volume?level=0.6", 0.5), ("demo/volume?level=0.8", 3)],
    "battery": [("demo/charging", 4), ("demo/reset", 2)],
    "airpods": [("demo/airpods", 5), ("close", 2)],
    "timer-done": [("demo/timerdone", 8), ("demo/reset", 2)],
    "settings": [("settings/general", 4), ("settings/widgets", 4), ("close", 3)],
    # Opened on General, left a moment, closed.
    "settings-open": [("settings/general", 3), ("close", 3)],
    # Every page in turn, twice, then closed.
    "settings-tour": [(f"settings/{p}", 1.5) for p in ["general", "widgets", "activities", "siri", "about"] * 2] + [("close", 3)],
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
                e = sum(cur[k] - prev[k] for k in ("energy", "gpu_energy_nj", "energy_billed_to_me", "gpu_energy_nj_billed_to_me"))
                samples.append((t, (cur["cpu_time"] - prev["cpu_time"]) * TICK / 1e9, e / 1e9, t - pt))
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
                best = max(best, 1000 * sum(s[2] for s in window) / dt)
            return best
        print(f"{name:16} worst 1 s {worst(1.0):6.1f}   worst 5 s (Activity Monitor) {worst(5.0):6.1f}   CPU {total_cpu * 1000:6.0f} ms", flush=True)

if __name__ == "__main__":
    main()
