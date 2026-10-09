#!/usr/bin/python3
"""Energy Impact at rest, second by second, as Activity Monitor (1 s refresh) shows it: the
coalition's energy in mW (own + GPU + billed to it by other processes), CPU ms, wake-ups.

    rest.py <seconds> [label]     a row per second, then: mean, worst, seconds that would read
                                  0.0 / ≥0.1 / ≥0.5 in Activity Monitor, and the footprint.
"""
import ctypes, os, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coalition import coalition_id, read, TICK, libc

class RUsage(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(n, ctypes.c_uint64) for n in (
        "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups", "pageins", "wired_size", "resident_size",
        "phys_footprint", "proc_start_abstime", "proc_exit_abstime")]

def footprint(pid):
    r = RUsage()
    return r.phys_footprint / 1048576 if libc.proc_pid_rusage(pid, 0, ctypes.byref(r)) == 0 else 0

def hid_idle():
    out = subprocess.run(["ioreg", "-c", "IOHIDSystem"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "HIDIdleTime" in line:
            return int(line.split()[-1]) / 1e9
    return -1

def main():
    seconds = int(sys.argv[1]); label = sys.argv[2] if len(sys.argv) > 2 else ""
    quiet = os.environ.get("QUIET") == "1"
    pid = int(subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0])
    cid = coalition_id(pid)
    prev = read(cid); pt = time.time(); rows = []
    for i in range(seconds):
        time.sleep(max(0, pt + 1 - time.time()))
        cur = read(cid); t = time.time(); dt = t - pt
        e = sum(cur[k] - prev[k] for k in ("energy", "gpu_energy_nj", "energy_billed_to_me", "gpu_energy_nj_billed_to_me"))
        mw = e / 1e6 / dt
        own = (cur["energy"] - prev["energy"]) / 1e6 / dt
        gpu = (cur["gpu_energy_nj"] - prev["gpu_energy_nj"] + cur["gpu_energy_nj_billed_to_me"] - prev["gpu_energy_nj_billed_to_me"]) / 1e6 / dt
        billed = (cur["energy_billed_to_me"] - prev["energy_billed_to_me"]) / 1e6 / dt
        bcpu = (cur["cpu_time_billed_to_me"] - prev["cpu_time_billed_to_me"]) * TICK / 1e6 / dt
        cpu = (cur["cpu_time"] - prev["cpu_time"]) * TICK / 1e6 / dt
        wake = (cur["platform_idle_wakeups"] - prev["platform_idle_wakeups"]) / dt
        iw = (cur["interrupt_wakeups"] - prev["interrupt_wakeups"]) / dt
        touched = hid_idle() < 1.2
        rows.append((mw, cpu, wake, iw, touched))
        if not quiet:
            print(f"{i + 1:4d}s{'*' if touched else ' '} EI {mw:6.2f}  cpu {cpu:6.2f} ms  idle-wake {wake:5.1f}  int-wake {iw:6.1f} | own {own:6.2f} gpu {gpu:6.2f} "
                  f"billed {billed:6.2f} ({bcpu:5.2f} ms)", flush=True)
        prev, pt = cur, t
    touched = sum(1 for r in rows if r[4])
    rows = [r for r in rows if not r[4]] or rows
    ei = [r[0] for r in rows]
    zero = sum(1 for v in ei if v < 0.05); one = sum(1 for v in ei if v >= 0.05); half = sum(1 for v in ei if v >= 0.5)
    print(f"{label:24} EI mean {sum(ei)/len(ei):5.3f} max {max(ei):6.2f} | 0.0 {zero}/{len(ei)}  ≥0.1 {one}  ≥0.5 {half} | "
          f"cpu {sum(r[1] for r in rows)/len(rows):5.2f} ms/s  wake {sum(r[2] for r in rows)/len(rows):4.1f}/s "
          f"int {sum(r[3] for r in rows)/len(rows):5.1f}/s | MB {footprint(pid):5.1f} | input in {touched} s (left out)", flush=True)

if __name__ == "__main__":
    main()
