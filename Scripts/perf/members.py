#!/usr/bin/python3
"""The processes in NotchIsland's resource coalition (what Activity Monitor's Energy tab adds up
under it), with the CPU time each used over a window.

    members.py <seconds>
"""
import ctypes, os, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coalition import libc, coalition_id, PidCoalition
from bench import RUsageV4, TICK_NS

def members(cid):
    out = []
    n = libc.proc_listallpids(None, 0)
    pids = (ctypes.c_int * (n * 2))()
    n = libc.proc_listallpids(pids, ctypes.sizeof(pids))
    for i in range(n):
        p = pids[i]
        info = PidCoalition()
        if libc.proc_pidinfo(p, 20, 0, ctypes.byref(info), ctypes.sizeof(info)) > 0 and info.ids[0] == cid:
            out.append(p)
    return out

def usage(p):
    info = RUsageV4()
    if libc.proc_pid_rusage(p, 4, ctypes.byref(info)) != 0: return None
    return (info.user_time + info.system_time) * TICK_NS / 1e9, info.billed_energy / 1e9

def name(p):
    return subprocess.run(["ps", "-o", "comm=", "-p", str(p)], capture_output=True, text=True).stdout.strip().split("/")[-1]

app = int(subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0])
cid = coalition_id(app)
seconds = float(sys.argv[1])
before = {p: usage(p) for p in members(cid)}
time.sleep(seconds)
after = {p: usage(p) for p in members(cid)}
for p in sorted(set(before) | set(after)):
    a, b = before.get(p), after.get(p)
    if b is None: continue
    cpu = b[0] - (a[0] if a else 0); energy = b[1] - (a[1] if a else 0)
    print(f"{p:7} {name(p)[:40]:40} cpu {cpu * 1000:7.1f} ms  energy {energy * 1000:8.1f} mJ{'  (new)' if a is None else ''}")
