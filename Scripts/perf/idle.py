#!/usr/bin/python3
"""Energy Impact at rest, as Activity Monitor's Energy tab adds it up: NotchIsland plus its child
processes (the MediaRemote adapter).

top's POWER column (Activity Monitor's number) comes once a second at best, so the app is also
sampled every 0.1 s through rusage: CPU time, idle wake-ups and the kernel's billed energy. A
least-squares fit of POWER on CPU % and wake-ups over the run turns the 0.1 s samples into
Energy Impact at that resolution.

    idle.py <seconds> [label]
"""
import ctypes, os, statistics, subprocess, sys, threading, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import libc, RUsageV4, TICK_NS

PERIOD = 0.1

def pids():
    app = subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()
    if not app: sys.exit("NotchIsland is not running")
    kids = subprocess.run(["pgrep", "-P", app[0]], capture_output=True, text=True).stdout.split()
    return int(app[0]), [int(k) for k in kids]

def usage(pids):
    cpu = wake = energy = mb = 0.0
    for p in pids:
        info = RUsageV4()
        if libc.proc_pid_rusage(p, 4, ctypes.byref(info)) != 0: continue
        cpu += (info.user_time + info.system_time) * TICK_NS
        wake += info.pkg_idle_wkups + info.interrupt_wkups
        energy += info.billed_energy
        if p == pids[0]: mb = info.phys_footprint / 1048576
    return cpu, wake, energy, mb

def main():
    seconds = int(sys.argv[1]); label = sys.argv[2] if len(sys.argv) > 2 else ""
    app, kids = pids(); every = [app] + kids
    fine = []; stop = False
    def sampler():
        prev = usage(every); pt = time.time()
        while not stop:
            time.sleep(PERIOD)
            cur = usage(every); t = time.time(); dt = t - pt
            fine.append((t, (cur[0] - prev[0]) / 1e9 / dt * 100, (cur[1] - prev[1]) / dt, (cur[2] - prev[2]) / 1e9 / dt, cur[3]))
            prev, pt = cur, t
    th = threading.Thread(target=sampler, daemon=True); th.start()
    args = ["top", "-l", str(seconds + 1), "-s", "1", "-stats", "pid,power"]
    for p in every: args += ["-pid", str(p)]
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, text=True)
    coarse = []; tick = -1; acc = 0.0
    for line in proc.stdout:
        if line.startswith("PID"):
            if tick >= 1: coarse.append((time.time(), acc))
            tick += 1; acc = 0.0; continue
        parts = line.split()
        if len(parts) == 2 and parts[0].isdigit():
            try: acc += float(parts[1])
            except ValueError: pass
    stop = True; th.join()
    pw = [v for _, v in coarse]
    # Fit POWER ≈ a·CPU% + b·wake/s on 1 s windows of the fine samples.
    rows = []
    for t, v in coarse:
        w = [f for f in fine if t - 1 < f[0] <= t]
        if w: rows.append((statistics.mean(f[1] for f in w), statistics.mean(f[2] for f in w), v))
    a = b = 0.0
    if len(rows) > 3:
        sxx = sum(r[0] * r[0] for r in rows); syy = sum(r[1] * r[1] for r in rows); sxy = sum(r[0] * r[1] for r in rows)
        sxz = sum(r[0] * r[2] for r in rows); syz = sum(r[1] * r[2] for r in rows); det = sxx * syy - sxy * sxy
        if det: a = (sxz * syy - syz * sxy) / det; b = (syz * sxx - sxz * sxy) / det
    est = [a * f[1] + b * f[2] for f in fine]
    cpu = [f[1] for f in fine]; wake = [f[2] for f in fine]; watts = [f[3] for f in fine]
    print(f"{label:26} ENERGY(top 1s) mean {statistics.mean(pw):5.2f} max {max(pw):5.2f} | "
          f"0.1s: cpu mean {statistics.mean(cpu):5.2f}% max {max(cpu):5.1f}%  wake/s {statistics.mean(wake):5.1f}  "
          f"energy≈ mean {statistics.mean(est):5.2f} max {max(est):5.2f}  billed {statistics.mean(watts)*1000:6.2f} mW  "
          f"MB {fine[-1][4]:5.1f}  kids {len(kids)}", flush=True)

if __name__ == "__main__":
    main()
