#!/usr/bin/python3
"""launch.py <app> [seconds] [step]: launches the app and prints its coalition's energy every
`step` s (default 0.25) for `seconds` (default 40): what the launch and the work prepared after it
(Settings, Siri, pictures) cost, moment by moment, and the worst 1 s window (Activity Monitor at
"Very often")."""
import os, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coalition import coalition_id, read, TICK
app = sys.argv[1]; secs = float(sys.argv[2]) if len(sys.argv) > 2 else 40; step = float(sys.argv[3]) if len(sys.argv) > 3 else 0.25
subprocess.run(["pkill", "-x", "NotchIsland"]); time.sleep(1.5)
t0 = time.time(); subprocess.run(["open", "-g", "-a", app] + (["--env", os.environ["NI_ENV"]] if os.environ.get("NI_ENV") else []))
pid = None
while pid is None and time.time() - t0 < 10:
    out = subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()
    pid = int(out[0]) if out else None; time.sleep(0.02)
cid = coalition_id(pid); prev = read(cid); pt = time.time(); rows = []
while time.time() - t0 < secs:
    time.sleep(step); cur = read(cid); t = time.time()
    d = {k: cur[k] - prev[k] for k in cur}
    e = (d["energy"] + d["gpu_energy_nj"] + d["energy_billed_to_me"] + d["gpu_energy_nj_billed_to_me"]) / 1e6
    rows.append((t - t0, t - pt, e, d["cpu_time"] * TICK / 1e6, d["cpu_ptime"] * TICK / 1e6, d["energy_billed_to_me"] / 1e6))
    prev, pt = cur, t
for t, dt, e, c, p, b in rows:
    if e > 0.5: print(f"{t:6.2f}s {e:7.1f} mJ ({1000*e/dt:6.0f} mW)  cpu {c:6.1f} ms  p {p:6.1f}  billed {b:6.1f}")
worst = 0; at = 0
for i in range(len(rows)):
    w = [r for r in rows[i:] if r[0] - rows[i][0] < 1.0]
    dt = sum(r[1] for r in w); e = sum(r[2] for r in w)
    if dt >= 0.9 and 1000 * e / dt > worst: worst, at = 1000 * e / dt, rows[i][0]
print(f"worst 1 s {worst:.0f} at {at:.1f}s; total {sum(r[2] for r in rows):.0f} mJ, cpu {sum(r[3] for r in rows):.0f} ms (p {sum(r[4] for r in rows):.0f})")
