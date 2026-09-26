#!/usr/bin/python3
"""CPU % of each NotchIsland thread over a window (ps -M system + user time).

    threads.py <seconds>
"""
import re, subprocess, sys, time

def snap(pid):
    rows = []
    for line in subprocess.run(["ps", "-M", "-p", pid], capture_output=True, text=True).stdout.splitlines()[1:]:
        times = re.findall(r"\b(\d+):(\d+\.\d+)\b", line)
        if len(times) < 2: continue
        (sm, ss), (um, us) = times[-2], times[-1]
        rows.append(int(sm) * 60 + float(ss) + int(um) * 60 + float(us))
    return rows

pid = subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0]
seconds = float(sys.argv[1])
a = snap(pid); time.sleep(seconds); b = snap(pid)
total = 0.0
for i, (x, y) in enumerate(zip(a, b)):
    d = (y - x) / seconds * 100; total += d
    if d >= 0.01: print(f"thread {i:2d} {'(main)' if i == 0 else '':7} {d:6.2f} %")
print(f"total {total:.2f} %")
