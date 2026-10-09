#!/usr/bin/python3
"""Energy of each step of a sequence, as Activity Monitor (1 s) would show it: for every
`notchisland://` step, the coalition's energy (mJ), CPU / P-core ms and the worst 1 s window
(mW = Activity Monitor's Energy Impact) from the step until the next one.

    phases.py <route>=<seconds> ...      e.g. settings/general=3 settings/widgets=3 close=3
    A step "move:x,y" or "click:x,y" moves or clicks the real pointer (ws/mouse) instead.
"""
import os, subprocess, sys, threading, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coalition import coalition_id, read, TICK
from bench import url

def main():
    steps = [(a.rsplit("=", 1)[0], float(a.rsplit("=", 1)[1])) for a in sys.argv[1:]]
    pid = int(subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0])
    cid = coalition_id(pid)
    samples = []; stop = False
    def sampler():
        prev = read(cid); pt = time.time()
        while not stop:
            time.sleep(0.05)
            cur = read(cid); t = time.time()
            e = sum(cur[k] - prev[k] for k in ("energy", "gpu_energy_nj", "energy_billed_to_me", "gpu_energy_nj_billed_to_me"))
            samples.append((t, e / 1e9, (cur["cpu_time"] - prev["cpu_time"]) * TICK / 1e6, (cur["cpu_ptime"] - prev["cpu_ptime"]) * TICK / 1e6))
            prev, pt = cur, t
    th = threading.Thread(target=sampler, daemon=True); th.start()
    time.sleep(0.3)
    marks = []
    for route, wait in steps:
        marks.append((time.time(), route))
        if route.startswith(("move:", "click:")):
            verb, point = route.split(":", 1); x, y = point.split(",")
            subprocess.run([os.path.join(os.path.dirname(os.path.abspath(__file__)), "ws", "mouse"), verb, x, y] + (["8", "8"] if verb == "move" else []))
        else:
            url(route)
        time.sleep(wait)
    marks.append((time.time(), None))
    stop = True; th.join()
    for (t0, route), (t1, _) in zip(marks, marks[1:]):
        win = [s for s in samples if t0 < s[0] <= t1]
        e = sum(s[1] for s in win) * 1000; cpu = sum(s[2] for s in win); p = sum(s[3] for s in win)
        worst = 0
        for i, s in enumerate(win):
            w = [x for x in win[i:] if x[0] - s[0] < 1.0]
            if w[-1][0] - s[0] < 0.9 and i > 0: break
            worst = max(worst, sum(x[1] for x in w) * 1000)
        print(f"{route:28} {e:7.1f} mJ  cpu {cpu:5.0f} ms  p {p:4.0f} ms  worst 1 s {worst:6.1f}", flush=True)

if __name__ == "__main__":
    main()
