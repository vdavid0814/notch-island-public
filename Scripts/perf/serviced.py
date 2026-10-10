#!/usr/bin/python3
"""Who works for others: every process's energy "serviced" on behalf of other processes
(`proc_pid_rusage` v4's `ri_serviced_energy`) over a window, largest first. Run it while a scenario
plays to see which daemons the coalition's "billed to me" comes from.

    serviced.py <seconds> [min mJ]
"""
import ctypes, ctypes.util, subprocess, sys, time

libc = ctypes.CDLL(ctypes.util.find_library("c"))

class RUsageV4(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(n, ctypes.c_uint64) for n in (
        "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups", "pageins", "wired_size",
        "resident_size", "phys_footprint", "proc_start_abstime", "proc_exit_abstime",
        "child_user_time", "child_system_time", "child_pkg_idle_wkups", "child_interrupt_wkups",
        "child_pageins", "child_elapsed_abstime", "diskio_bytesread", "diskio_byteswritten",
        "cpu_time_qos_default", "cpu_time_qos_maintenance", "cpu_time_qos_background",
        "cpu_time_qos_utility", "cpu_time_qos_legacy", "cpu_time_qos_user_initiated",
        "cpu_time_qos_user_interactive", "billed_system_time", "serviced_system_time",
        "logical_writes", "lifetime_max_phys_footprint", "instructions", "cycles", "billed_energy",
        "serviced_energy", "interval_max_phys_footprint", "runnable_time")]

class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]
tb = Timebase(); libc.mach_timebase_info(ctypes.byref(tb)); TICK = tb.numer / tb.denom

def snapshot():
    out = {}
    listing = subprocess.run(["ps", "-axo", "pid=,comm="], capture_output=True, text=True).stdout
    for line in listing.splitlines():
        pid, _, name = line.strip().partition(" ")
        info = RUsageV4()
        if libc.proc_pid_rusage(int(pid), 4, ctypes.byref(info)) == 0:
            out[int(pid)] = (name.strip().rsplit("/", 1)[-1], info.serviced_energy, info.serviced_system_time,
                             info.user_time + info.system_time)
    return out

def main():
    seconds = float(sys.argv[1]); floor = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5
    before = snapshot(); time.sleep(seconds); after = snapshot()
    rows = []
    for pid, (name, energy, serviced, cpu) in after.items():
        if pid in before:
            mj = (energy - before[pid][1]) / 1e6
            if mj >= floor:
                rows.append((mj, name, pid, (serviced - before[pid][2]) * TICK / 1e6, (cpu - before[pid][3]) * TICK / 1e6))
    for mj, name, pid, serviced_ms, cpu_ms in sorted(rows, reverse=True):
        print(f"{mj:8.1f} mJ serviced  {serviced_ms:7.1f} ms of {cpu_ms:7.1f} ms CPU  {name} [{pid}]")

if __name__ == "__main__":
    main()
