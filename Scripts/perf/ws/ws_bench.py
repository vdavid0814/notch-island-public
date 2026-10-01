#!/usr/bin/python3
"""What NotchIsland costs, the app and the window server together (October 1, 2026).

    ws_bench.py <label> <app|none|keep:app> <scenario ...>     scenarios: idle opens settings general widgets

Launches <app> fresh (`none`: quits NotchIsland and measures without it; `keep:<app>`: measures the
running one), plays music through the island, waits SETTLE seconds (default 45), then samples every
DT seconds (default 1) the resource coalitions of NotchIsland, WindowServer and coreaudiod: energy
(CPU + GPU + what other processes billed to it), CPU %, wake-ups. One JSON line per scenario goes to
`ws_results.jsonl` next to this file; the window server's per-sample series is in it.

The pointer is real (CGEvent, `mouse`), as a person uses the island: hover onto the notch at the
screen's top centre, clicks on Settings' gear, sidebar and close button, line scrolls. The points are
for a 1280 × 832 pt screen with the default island size: adjust SIDEBAR/GEAR/CLOSE for another.
The Claude desktop app is hidden while measuring (its own animations are window-server work too).

Build the helpers first:  swiftc -O mouse.swift -o mouse;  swiftc -O hideapp.swift -o hideapp
The window server's energy reading is noisy below ~20 mW: compare builds A B A B, and read its CPU %.
"""
import json, os, statistics, subprocess, sys, threading, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from coalition import coalition_id, read, TICK

MOUSE = os.path.join(HERE, "mouse")
HIDE = os.path.join(HERE, "hideapp")
CLAUDE = "com.anthropic.claudefordesktop"
AWAY = (900, 420)
NOTCH = (640, 8)
GEAR = (855, 14)
CLOSE = (1206, 13)
SIDEBAR = {"general": 129, "widgets": 173, "activities": 230, "siri": 274, "about": 331}
PAGE = (768, 448)
APP = None
MARKS = []


def pgrep(name):
    out = subprocess.run(["pgrep", "-x", name], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None


def mouse(*args):
    if args[0] in ("click", "scroll"):
        MARKS.append((time.time(), " ".join(map(str, args))))
    subprocess.run([MOUSE, *map(str, args)])


def url(route):
    subprocess.run(["open", "-g", "-a", APP, "notchisland://" + route])


def launch(app):
    subprocess.run(["pkill", "-x", "NotchIsland"])
    for _ in range(50):
        if not pgrep("NotchIsland"):
            break
        time.sleep(0.2)
    subprocess.run(["open", "-g", "-a", app])
    for _ in range(50):
        if pgrep("NotchIsland"):
            break
        time.sleep(0.2)
    time.sleep(3)


def hover_in(): mouse("move", *NOTCH, 20, 12)
def hover_out(): mouse("move", *AWAY, 20, 12)


def open_settings():
    hover_in(); time.sleep(1.2); mouse("click", *GEAR); mouse("move", *AWAY, 10, 10); time.sleep(2)


def idle():
    """Rest, the pointer away (IDLE seconds, default 120)."""
    mouse("move", *AWAY, 5, 10)
    time.sleep(float(os.environ.get("IDLE", 120)))


def opens():
    """Ten hovers onto the notch: 3 s open, 3 s closed (66 s)."""
    time.sleep(2)
    for _ in range(10):
        hover_in(); time.sleep(3); hover_out(); time.sleep(3)
    time.sleep(4)


def settings():
    """Settings opened from the panel's gear, ten page visits (each page twice: click, 1.5 s,
    eight lines down, 2 s), closed; a 60 s window."""
    start = time.time()
    open_settings(); time.sleep(0.5)
    for pane in list(SIDEBAR) * 2:
        mouse("click", 102, SIDEBAR[pane]); time.sleep(1.5)
        mouse("scroll", *PAGE, 8); time.sleep(2)
    mouse("click", *CLOSE); mouse("move", *AWAY, 10, 10)
    time.sleep(max(0, 60 - (time.time() - start)))


def general():
    """Settings ▸ General at rest (opened before sampling, closed after)."""
    time.sleep(12)


def widgets():
    """General and Widgets in turn, Widgets scrolled."""
    open_settings(); mouse("click", 102, SIDEBAR["general"]); time.sleep(3)
    for _ in range(2):
        mouse("click", 102, SIDEBAR["widgets"]); time.sleep(4); mouse("scroll", *PAGE, 8); time.sleep(4)
        mouse("click", 102, SIDEBAR["general"]); time.sleep(4)
    mouse("click", *CLOSE); mouse("move", *AWAY, 10, 10); time.sleep(3)


SCENARIOS = {"idle": idle, "opens": opens, "settings": settings, "general": general, "widgets": widgets}


def run(label, name):
    procs = {"app": pgrep("NotchIsland") or pgrep("launchd"), "ws": pgrep("WindowServer"), "audio": pgrep("coreaudiod")}
    coalitions = {k: coalition_id(p) for k, p in procs.items()}
    samples, stop = [], [False]
    step = float(os.environ.get("DT", 1.0))
    fields = ("energy", "gpu_energy_nj", "energy_billed_to_me", "gpu_energy_nj_billed_to_me", "cpu_time",
              "platform_idle_wakeups", "interrupt_wakeups")

    def sampler():
        prev = {k: read(c) for k, c in coalitions.items()}
        then = time.time()
        while not stop[0]:
            time.sleep(step)
            cur = {k: read(c) for k, c in coalitions.items()}
            now = time.time(); dt = now - then
            row = {"t": now, "dt": dt}
            for k in coalitions:
                d = {f: cur[k][f] - prev[k][f] for f in fields}
                row[k] = {"mw": (d["energy"] + d["energy_billed_to_me"] + d["gpu_energy_nj"] + d["gpu_energy_nj_billed_to_me"]) / 1e6 / dt,
                          "cpu": d["cpu_time"] * TICK / 1e9 / dt * 100,
                          "wake": (d["platform_idle_wakeups"] + d["interrupt_wakeups"]) / dt}
            samples.append(row)
            prev, then = cur, now

    if name == "general":
        open_settings(); mouse("click", 102, SIDEBAR["general"]); time.sleep(3)
    thread = threading.Thread(target=sampler, daemon=True); thread.start()
    SCENARIOS[name]()
    stop[0] = True; thread.join()
    if name == "general":
        mouse("click", *CLOSE); mouse("move", *AWAY, 10, 10)
    footprint = subprocess.run(["footprint", "-p", str(procs["app"])], capture_output=True, text=True).stdout
    memory = next((l.split("Footprint:")[1].split("(")[0].strip() for l in footprint.splitlines() if "Footprint:" in l), "?")
    result = {"label": label, "scenario": name, "time": time.strftime("%H:%M:%S"),
              "seconds": sum(s["dt"] for s in samples), "memory": memory, "marks": MARKS[:]}
    MARKS.clear()
    for k in coalitions:
        mw = [s[k]["mw"] for s in samples]
        result[k] = {"J": sum(x * s["dt"] for x, s in zip(mw, samples)) / 1000, "mean_mw": statistics.mean(mw),
                     "median_mw": statistics.median(mw), "peak_mw": max(mw),
                     "cpu": statistics.mean(s[k]["cpu"] for s in samples), "wake": statistics.mean(s[k]["wake"] for s in samples)}
    result["series"] = [[round(s["app"]["mw"], 2), round(s["ws"]["mw"], 1), round(s["t"], 2), round(s["ws"]["cpu"], 1)] for s in samples]
    with open(os.path.join(HERE, "ws_results.jsonl"), "a") as f:
        f.write(json.dumps(result) + "\n")
    a, w = result["app"], result["ws"]
    print(f"{label:10} {name:9} app {a['J']:6.2f} J mean {a['mean_mw']:7.2f} med {a['median_mw']:6.2f} peak {a['peak_mw']:7.1f} "
          f"cpu {a['cpu']:5.2f}% wake {a['wake']:5.1f} | WS {w['mean_mw']:6.1f} mW {w['J']:6.2f} J cpu {w['cpu']:5.1f}% | "
          f"audio {result['audio']['mean_mw']:5.1f} mW | {memory}", flush=True)


def main():
    global APP
    label, APP = sys.argv[1], sys.argv[2]
    subprocess.run([HIDE, "hide", CLAUDE])
    try:
        if APP.startswith("keep:"):
            APP = APP[5:]
        elif APP == "none":
            subprocess.run(["pkill", "-x", "NotchIsland"]); mouse("move", *AWAY, 5, 10); time.sleep(10)
        else:
            launch(APP); url("media/play"); mouse("move", *AWAY, 5, 10)
            time.sleep(float(os.environ.get("SETTLE", 45)))
        for name in sys.argv[3:]:
            run(label, name)
            time.sleep(5)
    finally:
        subprocess.run([HIDE, "show", CLAUDE])


if __name__ == "__main__":
    main()
