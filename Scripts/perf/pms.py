#!/usr/bin/python3
# pms.py <seconds> [step]: the app's coalition every step s: energy mJ, CPU ms, P-core ms, billed mJ (wall clock).
import sys, time, subprocess, datetime
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
from coalition import coalition_id, read, TICK
secs=float(sys.argv[1]); step=float(sys.argv[2]) if len(sys.argv)>2 else 0.25
pid=int(subprocess.run(["pgrep","-x","NotchIsland"],capture_output=True,text=True).stdout.split()[0])
cid=coalition_id(pid); prev=read(cid); t0=time.time()
while time.time()-t0<secs:
    time.sleep(step); cur=read(cid)
    e=sum(cur[k]-prev[k] for k in ("energy","gpu_energy_nj","energy_billed_to_me","gpu_energy_nj_billed_to_me"))/1e6
    print(f"{datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3]} E {e:7.1f} mJ cpu {(cur['cpu_time']-prev['cpu_time'])*TICK/1e6:6.1f} P {(cur['cpu_ptime']-prev['cpu_ptime'])*TICK/1e6:6.1f} billed {(cur['energy_billed_to_me']-prev['energy_billed_to_me'])/1e6:6.1f}",flush=True)
    prev=cur
