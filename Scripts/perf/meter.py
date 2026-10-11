#!/usr/bin/python3
"""Steps driven by the real pointer and keys (`stress.py`'s long-lived driver), each with its energy
as Activity Monitor counts it (own + GPU + billed to the app), its worst 1 s window, CPU and
performance-core ms, and the energy of each second.

    from meter import run, move, click, key, send, wait
    run([("open", lambda: …), ("rest", wait(2))])
"""
import os, subprocess, sys, threading, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coalition import coalition_id, read, TICK
from stress import move, click, key, send

def run(steps, settle=1.0):
    pid = int(subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0])
    cid = coalition_id(pid)
    send("pos")  # the driver started (and checked by the system) before anything is measured
    samples = []; marks = []; done = threading.Event()
    def sampler():
        prev = read(cid)
        while not done.is_set():
            time.sleep(0.1)
            cur = read(cid)
            energy = sum(cur[k] - prev[k] for k in ("energy", "gpu_energy_nj", "energy_billed_to_me", "gpu_energy_nj_billed_to_me"))
            samples.append((time.time(), (cur["cpu_time"] - prev["cpu_time"]) * TICK / 1e6, energy / 1e6,
                            (cur["cpu_ptime"] - prev["cpu_ptime"]) * TICK / 1e6,
                            (cur["energy_billed_to_me"] - prev["energy_billed_to_me"]) / 1e6))
            prev = cur
    thread = threading.Thread(target=sampler, daemon=True); thread.start()
    time.sleep(settle)
    for name, step in steps:
        marks.append((time.time(), name)); step()
    marks.append((time.time(), "end"))
    done.set(); thread.join()
    rows = []
    for (start, name), (end, _) in zip(marks, marks[1:]):
        window = [s for s in samples if start <= s[0] < end]
        if not window: continue
        worst = max(sum(s[2] for s in window[i:] if s[0] - window[i][0] < 1.0) for i in range(len(window)))
        seconds = {}
        for s in window: seconds.setdefault(int(s[0] - start), []).append(s[2])
        row = (name, sum(s[2] for s in window), sum(s[4] for s in window), worst, sum(s[1] for s in window), sum(s[3] for s in window))
        rows.append(row)
        print(f"{name:14} {row[1]:6.0f} mJ (billed {row[2]:4.0f})  worst 1 s {row[3]:6.0f}  CPU {row[4]:5.0f} ms  P {row[5]:4.0f} ms  | "
              + " ".join(f"{sum(v):.0f}" for _, v in sorted(seconds.items())), flush=True)
    return rows

def wait(seconds):
    return lambda: time.sleep(seconds)
