#!/usr/bin/python3
"""steady.py [seconds]: what each state costs while it is left open (the coalition's mW, as
Activity Monitor's Energy Impact), after 2 s to settle: rest, the panel, Siri, its gallery,
Settings pages, Customize."""
import os, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coalition import coalition_id, read, TICK
from bench import url
STATES = [("rest", ["close"]), ("panel home", ["open?page=home", "pin"]), ("siri field", ["pin", "siri"]),
          ("siri gallery", ["demo/siriapps"]), ("settings general", ["settings/general"]),
          ("settings widgets", ["settings/widgets"]), ("customize", ["widget/nowplaying/customize"]),
          ("rest again", ["customize/close", "close"])]
secs = float(sys.argv[1]) if len(sys.argv) > 1 else 8
pid = int(subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0])
cid = coalition_id(pid)
for name, routes in STATES:
    for r in routes: url(r); time.sleep(0.4)
    time.sleep(2)
    a = read(cid); t0 = time.time(); time.sleep(secs); b = read(cid); dt = time.time() - t0
    e = sum(b[k] - a[k] for k in ("energy", "gpu_energy_nj", "energy_billed_to_me", "gpu_energy_nj_billed_to_me")) / 1e6
    print(f"{name:18} {e / dt * 1000 / 1000:7.1f} mW  cpu {(b['cpu_time'] - a['cpu_time']) * TICK / 1e6 / dt / 10:5.2f} %  wake/s {(b['platform_idle_wakeups'] - a['platform_idle_wakeups']) / dt:5.1f}", flush=True)
