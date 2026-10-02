#!/usr/bin/python3
"""parts.py <scenario ...>: like anim.py, but the energy of each scenario split: CPU, GPU, billed to the app by others (mJ)."""
import os, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coalition import coalition_id, read, TICK
from bench import url
from anim import SCENARIOS
pid = int(subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0])
cid = coalition_id(pid)
for name in sys.argv[1:]:
    a = read(cid); time.sleep(0.3)
    for route, wait in SCENARIOS[name]: url(route); time.sleep(wait)
    b = read(cid)
    d = {k: b[k] - a[k] for k in a}
    print(f"{name:14} cpu {d['energy']/1e6:7.1f} mJ  gpu {d['gpu_energy_nj']/1e6:6.1f}  billed {d['energy_billed_to_me']/1e6:6.1f}  gpu-billed {d['gpu_energy_nj_billed_to_me']/1e6:6.1f}  "
          f"cpu-ms {d['cpu_time']*TICK/1e6:6.0f}  p-ms {d['cpu_ptime']*TICK/1e6:6.0f}  instr {d['cpu_instructions']/1e6:6.0f}M", flush=True)
