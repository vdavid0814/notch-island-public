#!/usr/bin/python3
"""NotchIsland animation/idle benchmark.

bench.py <label> <seconds> [scenario]
Samples every second: CPU % (rusage), GPU % (IOKit accumulatedGPUTime), phys footprint (MB),
Energy Impact (top POWER). Drives the scenario through notchisland:// URLs meanwhile.
Writes <label>.csv and prints a summary.
"""
import ctypes, ctypes.util, os, re, subprocess, sys, threading, time, statistics, json

APP = os.environ.get("NI_APP", os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../build/NotchIsland.app"))
OUT = os.path.dirname(os.path.abspath(__file__))

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

tb = Timebase(); libc.mach_timebase_info(ctypes.byref(tb))
TICK_NS = tb.numer / tb.denom

def pid():
    out = subprocess.run(["pgrep", "-f", APP + "/Contents/MacOS/NotchIsland"], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None

def rusage(p):
    info = RUsageV4()
    if libc.proc_pid_rusage(p, 4, ctypes.byref(info)) != 0:
        return None
    cpu_ns = (info.user_time + info.system_time) * TICK_NS
    return cpu_ns, info.phys_footprint / 1048576, info.pkg_idle_wkups

def gpu_ns(p):
    out = subprocess.run(["ioreg", "-l", "-w0", "-r", "-c", "AGXDeviceUserClient"], capture_output=True, text=True).stdout
    total = 0
    for block in out.split("+-o AGXDeviceUserClient")[1:]:
        if f'"pid {p},' not in block:
            continue
        for m in re.finditer(r'"accumulatedGPUTime"=(\d+)', block):
            total += int(m.group(1))
    return total

power = {}
def top_reader(p, seconds):
    proc = subprocess.Popen(["top", "-pid", str(p), "-l", str(seconds + 3), "-s", "1", "-stats", "pid,power"],
                            stdout=subprocess.PIPE, text=True)
    for line in proc.stdout:
        parts = line.split()
        if len(parts) == 2 and parts[0] == str(p):
            try:
                power[int(time.time())] = float(parts[1])
            except ValueError:
                pass

def url(u):
    subprocess.run(["open", "-g", "-a", APP, "notchisland://" + u])

def scenario(name, seconds, events):
    t0 = time.time()
    if name == "idle":
        return
    step = 0
    while time.time() - t0 < seconds - 4:
        if name == "settings":
            for u, wait in [("settings/widgets", 4), ("close", 4)]:
                events.append((time.time(), u)); url(u); time.sleep(wait)
            continue
        if name == "opens":
            cycle = [("open?page=home", 2.5), ("close", 3.5)]
            for u, wait in cycle:
                events.append((time.time(), u)); url(u); time.sleep(wait)
            step += 1
            continue
        cycle = [
            ("open?page=home", 2.5), ("close", 3.5),
            ("open?page=timer", 2.5), ("close", 3.5),
            ("siri", 2.5), ("close", 3.5),
        ]
        if name == "full" and step % 3 == 2:
            cycle += [("settings/general", 4), ("close", 4), ("settings/widgets", 4), ("close", 4)]
        for u, wait in cycle:
            if time.time() - t0 > seconds - 4:
                break
            events.append((time.time(), u))
            url(u)
            time.sleep(wait)
        step += 1

def main():
    label, seconds = sys.argv[1], int(sys.argv[2])
    name = sys.argv[3] if len(sys.argv) > 3 else "full"
    p = pid()
    assert p, "NotchIsland is not running"
    threading.Thread(target=top_reader, args=(p, seconds), daemon=True).start()
    events = []
    driver = threading.Thread(target=scenario, args=(name, seconds, events), daemon=True)
    rows = []
    prev = rusage(p); prev_g = gpu_ns(p); prev_t = time.time()
    driver.start()
    for _ in range(seconds):
        time.sleep(1)
        now = time.time(); r = rusage(p); g = gpu_ns(p)
        dt = now - prev_t
        rows.append({"t": now, "cpu": (r[0] - prev[0]) / 1e9 / dt * 100, "gpu": (g - prev_g) / 1e9 / dt * 100,
                     "mb": r[1], "wake": (r[2] - prev[2]) / dt, "power": power.get(int(now), power.get(int(now) - 1))})
        prev, prev_g, prev_t = r, g, now
    with open(os.path.join(OUT, label + ".json"), "w") as f:
        json.dump({"rows": rows, "events": events}, f)
    summarize(rows, events, label)

def summarize(rows, events, label):
    cpu = [r["cpu"] for r in rows]; gpu = [r["gpu"] for r in rows]; mb = [r["mb"] for r in rows]
    pw = [r["power"] for r in rows if r["power"] is not None]
    # Recovery: seconds after each "close" until CPU < 0.5 %.
    rec = []
    for t, u in events:
        if u != "close":
            continue
        after = [r for r in rows if r["t"] > t]
        for i, r in enumerate(after):
            if r["cpu"] < 0.5:
                rec.append(i + 1); break
    def pct(v, q):
        s = sorted(v); return s[min(len(s) - 1, int(len(s) * q))]
    print(f"== {label}: {len(rows)} s, {len(events)} events")
    print(f"CPU %  mean {statistics.mean(cpu):5.2f}  p50 {pct(cpu,.5):5.2f}  p90 {pct(cpu,.9):5.2f}  max {max(cpu):5.2f}")
    print(f"GPU %  mean {statistics.mean(gpu):5.2f}  p50 {pct(gpu,.5):5.2f}  p90 {pct(gpu,.9):5.2f}  max {max(gpu):5.2f}")
    if pw:
        print(f"Energy mean {statistics.mean(pw):5.2f}  p90 {pct(pw,.9):5.2f}  max {max(pw):5.2f}")
    print(f"MB     min {min(mb):6.1f}  mean {statistics.mean(mb):6.1f}  max {max(mb):6.1f}  last {mb[-1]:6.1f}")
    if rec:
        print(f"back to idle after close: mean {statistics.mean(rec):.1f} s, max {max(rec)} s")

if __name__ == "__main__":
    main()
