#!/usr/bin/python3
"""Steady-state cost of each island state: CPU %, Energy Impact (top POWER), idle wakeups/s, MB.
states.py <label> [seconds-per-state]"""
import subprocess, sys, time, os, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import pid, rusage, url

STATES = [
    ("rest (compact or idle)", "close", None),
    ("expanded home", "open?page=home", None),
    ("expanded timer", "open?page=timer", None),
    ("expanded battery", "open?page=battery", None),
    ("siri field", "siri", None),
    ("settings general", "settings/general", None),
    ("settings widgets", "settings/widgets", None),
    ("settings activities", "settings/activities", None),
]

def measure(p, seconds):
    top = subprocess.Popen(["top", "-pid", str(p), "-l", str(seconds + 1), "-s", "1", "-stats", "pid,power"],
                           stdout=subprocess.PIPE, text=True)
    r0 = rusage(p); t0 = time.time()
    powers = []
    for line in top.stdout:
        parts = line.split()
        if len(parts) == 2 and parts[0] == str(p):
            try: powers.append(float(parts[1]))
            except ValueError: pass
    r1 = rusage(p); dt = time.time() - t0
    return ((r1[0] - r0[0]) / 1e9 / dt * 100, statistics.mean(powers[1:] or [0]), max(powers[1:] or [0]),
            (r1[2] - r0[2]) / dt, r1[1])

def main():
    label = sys.argv[1]; seconds = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    p = pid()
    print(f"== {label}")
    print(f"{'state':26} {'CPU %':>6} {'energy':>7} {'e max':>6} {'wake/s':>7} {'MB':>6}")
    for name, u, _ in STATES:
        url(u)
        # pinned so it stays open without the pointer
        if u.startswith("open"):
            time.sleep(0.8); url("pin")
        time.sleep(3)  # let it settle
        cpu, e, emax, wake, mb = measure(p, seconds)
        print(f"{name:26} {cpu:6.2f} {e:7.2f} {emax:6.1f} {wake:7.1f} {mb:6.1f}", flush=True)
        if u.startswith("open"):
            url("pin")
    url("close")

if __name__ == "__main__":
    main()
