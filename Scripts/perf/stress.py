#!/usr/bin/python3
"""Stress tests with the real pointer, as someone uses the island: Activity Monitor's Energy Impact
(the coalition's mW, own + GPU + billed to it) for every second, the worst 1 s and 5 s windows,
CPU and performance-core ms.

    stress.py <scenario> [rounds]       scenarios below; NOTCH=x,y overrides the notch's centre

A URL-driven run (anim.py) also bills the app for LaunchServices delivering each URL, and a new
`ws/mouse` process per step for TCC, trustd and syspolicyd checking it (~100 mJ a spawn, billed to
the app that gets the events). Here one long-lived driver (`ws/moused`) makes every move and
click, checked once before the measurement starts: the numbers are those of a hand.
"""
import os, subprocess, sys, threading, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coalition import coalition_id, read, TICK

MOUSED = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ws", "moused")
_driver = None

def send(command):
    """One command to the long-lived pointer driver (ws/moused), waiting for it to finish."""
    global _driver
    if _driver is None:
        _driver = subprocess.Popen([MOUSED], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
    _driver.stdin.write(command + "\n"); _driver.stdin.flush()
    return _driver.stdout.readline().strip()
NX, NY = (float(v) for v in os.environ.get("NOTCH", "640,6").split(","))
AWAY = (NX, 420.0)

def move(x, y, steps=8, ms=8):
    send(f"move {x} {y} {steps} {ms}")

def click(x, y, hold=0.0):
    if hold:
        # A held press: some buttons (Customize's Done) let a 50 ms click pass unnoticed.
        send(f"down {x} {y}"); time.sleep(hold); send(f"up {x} {y}")
    else:
        send(f"click {x} {y}")

def hover_cycle(dwell, away):
    def run():
        move(NX, NY); time.sleep(dwell)
        move(*AWAY); time.sleep(away)
    return run

GEAR = tuple(float(v) for v in os.environ.get("GEAR", "887,14").split(","))

def settings_cycle():
    # Hover the panel open, click its gear: Settings grows; a click outside closes it.
    move(NX, NY); time.sleep(0.9)
    move(*GEAR, 6, 8); click(*GEAR); time.sleep(3.0)
    click(NX, 600); time.sleep(0.4)
    move(*AWAY); time.sleep(2.5)

CUSTOMIZE = tuple(float(v) for v in os.environ.get("CUSTOMIZE", "1122,431").split(","))
DONE = tuple(float(v) for v in os.environ.get("DONE", "851,62").split(","))

def customize_cycle():
    # Settings ▸ Widgets with a widget picked: its Customize… button, then the editor's Done.
    move(*CUSTOMIZE, 6, 8); click(*CUSTOMIZE, hold=0.12); time.sleep(3.0)
    move(*DONE, 6, 8); click(*DONE, hold=0.12); time.sleep(3.0)

def key(code, *flags):
    send("key " + " ".join([str(code), *flags]))

SCENARIOS = {

    # Customize opened and closed by its buttons (Settings ▸ Widgets, a widget picked).
    "customize": (customize_cycle, 2),
    # Settings opened from the panel's gear and closed by a click outside, as a hand does.
    "settings-gear": (settings_cycle, 3),
    # Hover in, the panel opens (hover delay), out again, closes: fast and slow.
    "hover-spam": (hover_cycle(0.55, 0.45), 12),
    "hover-slow": (hover_cycle(1.2, 1.0), 8),
    # Openings as most are: the panel last open over 10 s ago (its page no longer kept).
    "hover-cold": (hover_cycle(1.5, 11.5), 3),
    # One hover open and close, then rest.
    "hover-once": (hover_cycle(1.5, 3.0), 1),
    # Moving across the top of the screen past the notch (no dwell): what passing by costs.
    "pass-by": (lambda: (move(NX - 300, NY + 2, 20, 8), move(NX + 300, NY + 2, 40, 8)), 10),
    # Moving the mouse around the screen, away from the notch.
    "move-around": (lambda: (move(200, 600, 30, 8), move(1100, 300, 30, 8)), 10),
}

def main():
    name = sys.argv[1]
    action, rounds = SCENARIOS[name]
    if len(sys.argv) > 2: rounds = int(sys.argv[2])
    pid = int(subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0])
    cid = coalition_id(pid)
    move(*AWAY); time.sleep(2.5)
    samples = []; stop = False
    def sampler():
        prev = read(cid); pt = time.time()
        while not stop:
            time.sleep(0.1)
            cur = read(cid); t = time.time()
            e = sum(cur[k] - prev[k] for k in ("energy", "gpu_energy_nj", "energy_billed_to_me", "gpu_energy_nj_billed_to_me"))
            samples.append((t, (cur["cpu_time"] - prev["cpu_time"]) * TICK / 1e9, e / 1e9, t - pt,
                            (cur["cpu_ptime"] - prev["cpu_ptime"]) * TICK / 1e9,
                            (cur["energy_billed_to_me"] - prev["energy_billed_to_me"]) / 1e9,
                            (cur["gpu_energy_nj"] - prev["gpu_energy_nj"]) / 1e9,
                            cur["interrupt_wakeups"] - prev["interrupt_wakeups"]))
            prev, pt = cur, t
    th = threading.Thread(target=sampler, daemon=True); th.start()
    time.sleep(0.5)
    for _ in range(rounds): action()
    time.sleep(2.0)
    stop = True; th.join()
    def worst(span):
        best = 0.0
        for i in range(len(samples)):
            window = [s for s in samples[i:] if s[0] - samples[i][0] < span]
            dt = sum(s[3] for s in window)
            if dt < span * 0.9: break
            best = max(best, 1000 * sum(s[2] for s in window) / dt)
        return best
    t0 = samples[0][0]; secs = {}
    for s in samples: secs.setdefault(int(s[0] - t0), []).append(s)
    per = [1000 * sum(x[2] for x in v) / max(sum(x[3] for x in v), 1e-6) for k, v in sorted(secs.items())]
    total = sum(s[2] for s in samples) * 1000
    dur = samples[-1][0] - t0
    print(f"{name:12} worst 1 s {worst(1.0):6.1f}  worst 5 s {worst(5.0):6.1f}  mean {total / dur:6.1f}  "
          f"CPU {sum(s[1] for s in samples) * 1000:5.0f} ms  P {sum(s[4] for s in samples) * 1000:4.0f} ms  "
          f"energy {total:6.0f} mJ (billed {sum(s[5] for s in samples) * 1000:5.0f}, gpu {sum(s[6] for s in samples) * 1000:4.0f})  "
          f"wakeups {sum(s[7] for s in samples)}", flush=True)
    if os.environ.get("SECONDS_ROW"): print("  per s: " + " ".join(f"{v:.0f}" for v in per))

if __name__ == "__main__":
    main()
