#!/usr/bin/python3
"""NotchIsland's resource coalition, as Activity Monitor's Energy tab counts it: every process in it,
plus the CPU and energy other processes spent on its behalf ("billed to me").

    coalition.py <seconds> [interval]       prints one line per interval
"""
import ctypes, ctypes.util, subprocess, sys, time

libc = ctypes.CDLL(ctypes.util.find_library("c"))
FIELDS = ["tasks_started", "tasks_exited", "time_nonempty", "cpu_time", "interrupt_wakeups", "platform_idle_wakeups",
          "bytesread", "byteswritten", "gpu_time", "cpu_time_billed_to_me", "cpu_time_billed_to_others", "energy",
          "lw1", "lw2", "lw3", "lw4", "lw5", "lw6", "lw7", "lw8", "energy_billed_to_me", "energy_billed_to_others",
          "cpu_ptime", "cpu_time_eqos_len"] + [f"eqos{i}" for i in range(7)] + [
          "cpu_instructions", "cpu_cycles", "fs_metadata_writes", "pm_writes", "cpu_pinstructions", "cpu_pcycles",
          "conclave_mem", "ane_mach_time", "ane_energy_nj", "gpu_energy_nj", "gpu_energy_nj_billed_to_me",
          "gpu_energy_nj_billed_to_others", "pad1", "pad2", "pad3", "pad4"]

class CRU(ctypes.Structure):
    _fields_ = [(f, ctypes.c_uint64) for f in FIELDS]

class PidCoalition(ctypes.Structure):
    _fields_ = [("ids", ctypes.c_uint64 * 2), ("r1", ctypes.c_uint64), ("r2", ctypes.c_uint64), ("r3", ctypes.c_uint64)]

class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]
tb = Timebase(); libc.mach_timebase_info(ctypes.byref(tb)); TICK = tb.numer / tb.denom

def coalition_id(pid):
    info = PidCoalition()
    n = libc.proc_pidinfo(pid, 20, 0, ctypes.byref(info), ctypes.sizeof(info))
    return info.ids[0] if n > 0 else None

def read(cid):
    cru = CRU()
    if libc.coalition_info_resource_usage(ctypes.c_uint64(cid), ctypes.byref(cru), ctypes.sizeof(cru)) != 0:
        return None
    return {f: getattr(cru, f) for f in FIELDS}

def main():
    seconds = float(sys.argv[1]); step = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    pid = int(subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0])
    cid = coalition_id(pid)
    prev = read(cid); t0 = pt = time.time()
    print(f"coalition {cid}")
    while time.time() - t0 < seconds:
        time.sleep(step)
        cur = read(cid); t = time.time(); dt = t - pt
        d = {k: (cur[k] - prev[k]) / dt for k in cur}
        cpu = d["cpu_time"] * TICK / 1e9 * 100
        billed = d["cpu_time_billed_to_me"] * TICK / 1e9 * 100
        wake = d["platform_idle_wakeups"]; iw = d["interrupt_wakeups"]
        gpu = d["gpu_time"] * TICK / 1e9 * 100
        est = cpu + 100 * 0.0002 * wake
        mw = d['energy'] / 1e6; gmw = d['gpu_energy_nj'] / 1e6; bmw = d['energy_billed_to_me'] / 1e6
        gbmw = d['gpu_energy_nj_billed_to_me'] / 1e6
        ane = d['ane_energy_nj'] / 1e6; gt = d['gpu_time'] * TICK / 1e6
        print(f"{t - t0:6.1f}s cpu {cpu:6.2f}% billed-cpu {billed:5.2f}% wake/s {wake:5.1f} | mW energy {mw:7.2f} gpu {gmw:7.2f} "
              f"billed {bmw:7.2f} gpu-billed {gbmw:7.2f} ane {ane:6.2f} gpu-ms {gt:6.2f} | AM≈ {est:6.2f}", flush=True)
        prev, pt = cur, t

if __name__ == "__main__":
    main()
