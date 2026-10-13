#!/usr/bin/python3
"""The app's energy and CPU time for a sequence of steps, variants in turn (A B A B …).

    abcpu.py <rounds> <label>[:NI_X=1,NI_Y=2] … -- <step> …
    WARM="demo/media,2,open,2,close,2"   steps run once after each launch, before measuring
    REPEAT=6                              how many times the steps run in a round

A step is a `notchisland://` route or seconds to wait. Prints, per variant and round and for one
repeat: the coalition's energy (own, GPU and billed, as Activity Monitor counts it), its CPU ms and
how much of that ran on performance cores, and the main thread's turns over 1 ms (`NI_TRACE`).
CPU ms alone misleads where work moves between the efficiency and the performance cores (the same
work is ~3× the ms on an efficiency core for a fraction of the energy): read the energy.
CALM=3 waits for a one-minute load average under that before each launch (the app lowers nothing
on a busy Mac, so a build just before changes every number).
"""
import os, re, subprocess, sys, time, datetime, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import APP, rusage
from coalition import coalition_id, read, TICK

def pids():
    return subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()

def launch(switches):
    calm = float(os.environ.get("CALM", "3"))
    while calm and os.getloadavg()[0] > calm: time.sleep(5)
    subprocess.run(["pkill", "-9", "-x", "NotchIsland"]); time.sleep(0.5)
    args = ["open", "-n", "-g", "-a", APP, "--env", "NI_TRACE=1", "--env", "NI_TRACE_MIN=1", "--env", "NI_NO_PREPARE=1"]
    for switch in switches: args += ["--env", switch]
    subprocess.run(args)
    for _ in range(50):
        if pids(): break
        time.sleep(0.1)
    env = subprocess.run(["ps", "eww", "-p", pids()[0]], capture_output=True, text=True).stdout
    for switch in switches:
        assert switch in env, f"{switch} did not reach the app"
    time.sleep(3.5)
    return int(pids()[0])

def run(steps):
    for step in steps:
        if step.replace(".", "").isdigit(): time.sleep(float(step))
        else: subprocess.run(["open", "-g", "-a", APP, "notchisland://" + step])

def main():
    split = sys.argv.index("--")
    rounds = int(sys.argv[1])
    variants = []
    for spec in sys.argv[2:split]:
        label, _, switches = spec.partition(":")
        variants.append((label, [s for s in switches.split(",") if s]))
    steps = sys.argv[split + 1:]
    warm = [s for s in os.environ.get("WARM", "").split(",") if s]
    repeat = int(os.environ.get("REPEAT", "6"))
    results = {label: [] for label, _ in variants}
    for _ in range(rounds):
        for label, switches in variants:
            pid = launch(switches)
            run(warm)
            start = datetime.datetime.now()
            cid = coalition_id(pid)
            before = read(cid)
            for _ in range(repeat): run(steps)
            after = read(cid)
            cpu = (after["cpu_time"] - before["cpu_time"]) * TICK / 1e6 / repeat
            pcpu = (after["cpu_ptime"] - before["cpu_ptime"]) * TICK / 1e6 / repeat
            energy = sum(after[k] - before[k] for k in ("energy", "gpu_energy_nj", "energy_billed_to_me", "gpu_energy_nj_billed_to_me")) / 1e6 / repeat
            log = subprocess.run(["/usr/bin/log", "show", "--start", start.strftime("%Y-%m-%d %H:%M:%S"), "--style", "compact", "--info",
                                  "--predicate", f'processID == {pid} AND subsystem == "com.davidvarga.notchisland" AND category == "window"'],
                                 capture_output=True, text=True).stdout
            turns = [float(m.group(1)) for m in re.finditer(r"TURN ([\d.]+) at", log)]
            results[label].append((energy, cpu, pcpu, len(turns) / repeat, sum(turns) / repeat))
            print(f"{label:<14} {energy:7.1f} mJ  CPU {cpu:6.1f} ms (P {pcpu:6.1f})  {len(turns) / repeat:5.1f} turns over 1 ms ({sum(turns) / repeat:6.1f} ms)", flush=True)
    subprocess.run(["pkill", "-9", "-x", "NotchIsland"])
    print()
    for label, rows in results.items():
        m = lambda i: statistics.median(r[i] for r in rows)
        print(f"{label:<14} median {m(0):7.1f} mJ  CPU {m(1):6.1f} ms (P {m(2):6.1f})  {m(3):5.1f} turns ({m(4):6.1f} ms)")

if __name__ == "__main__":
    main()
