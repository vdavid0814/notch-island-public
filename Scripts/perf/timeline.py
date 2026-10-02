#!/usr/bin/python3
"""timeline.py <scenario> [step]: the coalition's energy every `step` s (default 0.05) through one
anim.py scenario — the app's own CPU energy, GPU, and what other processes billed to it — to see
which moment of a scenario makes its peak and who pays for it."""
import os, subprocess, sys, time, threading
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coalition import coalition_id, read, TICK
from bench import url
from anim import SCENARIOS

name = sys.argv[1]; step = float(sys.argv[2]) if len(sys.argv) > 2 else 0.05
pid = int(subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0])
cid = coalition_id(pid)
rows = []; marks = []; stop = False
def sampler():
    prev = read(cid); pt = t0
    while not stop:
        time.sleep(step)
        cur = read(cid); t = time.time()
        d = {k: cur[k] - prev[k] for k in cur}
        rows.append((t - t0, t - pt, d)); prev, pt = cur, t
t0 = time.time()
th = threading.Thread(target=sampler, daemon=True); th.start()
time.sleep(0.3)
for route, wait in SCENARIOS[name]:
    if route: marks.append((time.time() - t0, route)); url(route)
    time.sleep(wait)
stop = True; th.join()
mi = 0
tot = dict(cpu=0, p=0, e=0, b=0, g=0)
for t, dt, d in rows:
    while mi < len(marks) and marks[mi][0] <= t:
        print(f"         --> {marks[mi][1]}"); mi += 1
    cpu = d["cpu_time"] * TICK / 1e6; p = d["cpu_ptime"] * TICK / 1e6
    e = d["energy"] / 1e6; b = d["energy_billed_to_me"] / 1e6; g = (d["gpu_energy_nj"] + d["gpu_energy_nj_billed_to_me"]) / 1e6
    tot["cpu"] += cpu; tot["p"] += p; tot["e"] += e; tot["b"] += b; tot["g"] += g
    if e + b + g > 0.3 * step * 20:
        print(f"{t:6.2f}s cpu {cpu:5.1f}ms p {p:5.1f}ms | own {e:6.1f} mJ billed {b:6.1f} gpu {g:5.1f} | mW {1000*(e+b+g)/dt:7.0f} wake {d['platform_idle_wakeups']:3d}")
print(f"total cpu {tot['cpu']:.0f} ms (p {tot['p']:.0f}) own {tot['e']:.0f} mJ billed {tot['b']:.0f} mJ gpu {tot['g']:.0f} mJ")
