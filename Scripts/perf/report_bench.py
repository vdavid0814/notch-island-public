#!/usr/bin/python3
"""Cost of collecting and sending one diagnostics report (notchisland://diagnostics/send):
the app's CPU and its helpers' (child processes), wall time, Energy Impact peak."""
import subprocess, sys, time, os, threading
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bench import pid, rusage

def children_cpu(p):
    out = subprocess.run(["ps", "-A", "-o", "ppid=,time="], capture_output=True, text=True).stdout
    return out

def main():
    p = pid(); assert p
    power = []
    top = subprocess.Popen(["top", "-l", "40", "-s", "1", "-stats", "pid,power", "-o", "power"], stdout=subprocess.PIPE, text=True)
    def read():
        for line in top.stdout:
            parts = line.split()
            if len(parts) == 2 and parts[0] == str(p):
                try: power.append(float(parts[1]))
                except ValueError: pass
    threading.Thread(target=read, daemon=True).start()
    time.sleep(2)
    r0 = rusage(p)
    # CPU of the whole coalition (app + children) from `top`'s own sampling is hard; take the children's
    # summed CPU from ps before/after instead.
    def kids():
        total = 0.0
        for line in subprocess.run(["ps", "-A", "-o", "ppid=,cputime="], capture_output=True, text=True).stdout.splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[0] == str(p):
                m, s = parts[1].split(":"); total += int(m) * 60 + float(s)
        return total
    t0 = time.time()
    subprocess.run(["open", "-g", "notchisland://diagnostics/send"])
    # Wait for the log line.
    while time.time() - t0 < 60:
        out = subprocess.run(["/usr/bin/log", "show", "--last", "20s", "--style", "compact", "--predicate",
                              'subsystem == "com.davidvarga.notchisland" AND category == "app"'], capture_output=True, text=True).stdout
        if "diagnostics sent" in out or "diagnostics failed" in out or "not again" in out:
            break
        time.sleep(1)
    dt = time.time() - t0
    r1 = rusage(p)
    print(f"report: {dt:.1f} s wall, app CPU {(r1[0]-r0[0])/1e6:.0f} ms, MB {r1[1]:.1f}")
    time.sleep(3)
    print(f"Energy Impact while collecting: max {max(power or [0]):.1f}")
    print("log:", [l for l in out.splitlines() if "diagnostics" in l][-1:])

if __name__ == "__main__":
    main()
