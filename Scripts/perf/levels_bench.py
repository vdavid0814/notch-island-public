#!/usr/bin/python3
"""Cost of volume changes made elsewhere (the island's cover or the liquid card over macOS's card):
levels_bench.py <label> [changes] — changes the volume by one step and back, 4 s apart, samples
CPU %, Energy Impact (top POWER), wakeups and MB per 0.25 s, and reports per change."""
import subprocess, sys, time, os, threading, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import pid, rusage

def volume():
    return int(subprocess.run(["osascript", "-e", "output volume of (get volume settings)"], capture_output=True, text=True).stdout.strip() or 30)

def set_volume(v):
    subprocess.run(["osascript", "-e", f"set volume output volume {v}"])

def main():
    label = sys.argv[1]; changes = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    p = pid(); assert p
    power = []
    top = subprocess.Popen(["top", "-pid", str(p), "-l", str(changes * 4 + 3), "-s", "1", "-stats", "pid,power"], stdout=subprocess.PIPE, text=True)
    def read():
        for line in top.stdout:
            parts = line.split()
            if len(parts) == 2 and parts[0] == str(p):
                try: power.append(float(parts[1]))
                except ValueError: pass
    threading.Thread(target=read, daemon=True).start()
    base = volume()
    per = []
    for i in range(changes):
        r0 = rusage(p); t0 = time.time()
        set_volume(base + (6 if i % 2 == 0 else 0))
        time.sleep(4)
        r1 = rusage(p)
        per.append(((r1[0] - r0[0]) / 1e6, r1[1], (r1[2] - r0[2])))
    set_volume(base)
    time.sleep(1.5)
    print(f"== {label}: {changes} changes")
    cpu = [c for c, _, _ in per]
    print(f"CPU ms per change: mean {statistics.mean(cpu):.0f}  max {max(cpu):.0f}")
    print(f"wakeups per change: mean {statistics.mean(w for _, _, w in per):.0f}")
    print(f"MB after: {per[-1][1]:.1f}")
    ps = power[1:] or [0]
    print(f"Energy Impact: mean {statistics.mean(ps):.2f}  max {max(ps):.1f}")

if __name__ == "__main__":
    main()
