#!/usr/bin/python3
"""The island on a busy Mac: does its main thread stand still?

    hang.py [variant …]      variants: guarded (the build as it is), unguarded (NI_THRIFT_UNGUARDED=1,
                             the lowering as before the watch and the gate), nothrift (NI_NO_THRIFT=1)
    LOAD=10:utility          cores taken meanwhile and at which quality of service (utility, default,
                             initiated; 0 for none). A build's compilers run at utility or default.
    MEMORY=warn|critical     macOS's own memory_pressure tool beside it (takes memory until that level)
    ROUNDS=2  TOUR=urls|pointer
    WARM=3                   seconds of load before the launch: 3, the load has just begun (the load
                             average knows nothing yet); 90, the Mac has been busy for a while
    CALM=3                   wait for a one-minute load average under this first (0: start at once)

Each variant from a fresh launch with the load already running: the launch and Settings' preparation,
the panel opened and its pages switched, Settings opened on three pages and closed, Siri. Read from
`NI_TRACE`'s turns: the longest turn of each phase, how many were over 100 ms, 250 ms, 1 s, and how
often `ThriftWatch` gave the priority back. A turn over 250 ms is a visible stop; 2 s is what the
hang reports count.
"""
import os, re, subprocess, sys, time, datetime
HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.environ.get("NI_APP", os.path.normpath(os.path.join(HERE, "../../build/NotchIsland.app")))
BINARY = APP + "/Contents/MacOS/NotchIsland"
HOG = os.path.join(HERE, "hog")
LOAD = os.environ.get("LOAD", "10:utility")
MEMORY = os.environ.get("MEMORY", "")
ROUNDS = int(os.environ.get("ROUNDS", "2"))
TOUR = os.environ.get("TOUR", "urls")
SWITCHES = {"guarded": {}, "unguarded": {"NI_THRIFT_UNGUARDED": "1"}, "nothrift": {"NI_NO_THRIFT": "1"}}

def pids():
    return subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()

def quit_app():
    subprocess.run(["pkill", "-9", "-x", "NotchIsland"])
    for _ in range(30):
        if not pids(): return
        time.sleep(0.1)

def launch(switches):
    args = ["open", "-n", "-g", "-a", APP]
    for name, value in {"NI_TRACE": "1", "NI_TRACE_MIN": "30", **switches}.items():
        args += ["--env", f"{name}={value}"]
    subprocess.run(args)
    for _ in range(50):
        if pids(): break
        time.sleep(0.1)
    env = subprocess.run(["ps", "eww", "-p", pids()[0]], capture_output=True, text=True).stdout
    for name in switches:
        assert name + "=" in env, f"{name} did not reach the app"

def url(route):
    subprocess.run(["open", "-g", "-a", APP, "notchisland://" + route])

def tour_urls(mark):
    mark("launch + preparation"); time.sleep(float(os.environ.get("SETTLE", "22")))
    mark("panel")
    for page in ("home", "battery", "home", "timer", "home"):
        url("open?page=" + page); time.sleep(1.3)
    url("close"); time.sleep(1.5)
    for _ in range(3):
        url("open"); time.sleep(1.6); url("close"); time.sleep(1.2)
    mark("settings")
    for pane in ("general", "widgets", "appearance", "general"):
        url("settings/" + pane); time.sleep(2.2)
    url("close"); time.sleep(2.5)
    url("settings/widgets"); time.sleep(2.5); url("close"); time.sleep(3.0)
    mark("siri")
    url("assistant"); time.sleep(2.0); url("demo/siriapps"); time.sleep(2.5); url("close"); time.sleep(2.0)
    mark("after")
    time.sleep(4)

def tour_pointer(mark):
    sys.path.insert(0, HERE)
    import stress
    mark("launch + preparation, the pointer coming meanwhile")
    time.sleep(6.5)
    for _ in range(6):
        stress.move(stress.NX, stress.NY); time.sleep(1.2); stress.move(*stress.AWAY); time.sleep(1.4)
    mark("hover")
    for _ in range(8):
        stress.move(stress.NX, stress.NY); time.sleep(0.9); stress.move(*stress.AWAY); time.sleep(0.8)
    mark("settings by the gear")
    for _ in range(3): stress.settings_cycle()
    mark("after")
    time.sleep(3)

def run(variant):
    quit_app()
    start = datetime.datetime.now()
    marks = []
    def mark(name): marks.append((time.time(), name))
    launch(SWITCHES[variant])
    (tour_pointer if TOUR == "pointer" else tour_urls)(mark)
    alive = bool(pids())
    log = subprocess.run(["/usr/bin/log", "show", "--start", start.strftime("%Y-%m-%d %H:%M:%S"), "--style", "compact", "--info",
                          "--predicate", 'subsystem == "com.davidvarga.notchisland" AND category == "window"'],
                         capture_output=True, text=True).stdout
    turns, rescues, notes = [], 0, []
    for line in log.splitlines():
        stamp = re.match(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)", line)
        if not stamp: continue
        at = datetime.datetime.strptime(stamp.group(1), "%Y-%m-%d %H:%M:%S.%f").timestamp()
        turn = re.search(r"TURN ([\d.]+) at [\d.]+ qos (\d+)", line)
        if turn: turns.append((at, float(turn.group(1)), int(turn.group(2))))
        if "priority given back" in line:
            rescues += 1; notes.append(line.split("] ", 1)[-1][:110])
    print(f"\n== {variant}{'' if alive else '  (THE APP DIED)'}: {len(turns)} turns over 30 ms, {rescues} stretches ended by the watch")
    worst = 0
    for index, (begin, name) in enumerate(marks):
        end = marks[index + 1][0] if index + 1 < len(marks) else time.time() + 5
        inside = [t for t in turns if begin <= t[0] < end]
        longest = max((t[1] for t in inside), default=0)
        worst = max(worst, longest)
        low = sum(1 for t in inside if t[2] <= 9)
        print(f"   {name:<34} longest {longest:7.0f} ms   >100: {sum(t[1] > 100 for t in inside):3}  >250: {sum(t[1] > 250 for t in inside):3}  >1000: {sum(t[1] > 1000 for t in inside):2}   ended at background: {low}")
    for note in notes[:4]: print("     " + note)
    return worst

def main():
    variants = [v for v in sys.argv[1:] if v in SWITCHES] or ["guarded", "unguarded"]
    if not os.path.exists(HOG) or os.path.getmtime(HOG) < os.path.getmtime(HOG + ".c"):
        subprocess.run(["cc", "-O1", "-o", HOG, HOG + ".c"], check=True)
    # From a calm Mac: the one-minute load average is what the app's own gate reads, and the load
    # of the run before (or of the build) would switch the lowering off from the start.
    calm = float(os.environ.get("CALM", "3"))
    while calm and os.getloadavg()[0] > calm:
        time.sleep(5)
    threads, _, qos = LOAD.partition(":")
    load = subprocess.Popen([HOG, threads, "3600", qos or "utility"]) if int(threads) else None
    memory = subprocess.Popen(["memory_pressure", "-l", MEMORY], stdout=subprocess.DEVNULL) if MEMORY else None
    print(f"load {LOAD}{', memory ' + MEMORY if MEMORY else ''}; {APP}")
    time.sleep(float(os.environ.get("WARM", "3")))
    results = {v: [] for v in variants}
    try:
        for _ in range(ROUNDS):
            for variant in variants:
                # Each variant against a load that has just begun, as the first one met it.
                if load and float(os.environ.get("WARM", "3")) < 30 and results[variants[0]]:
                    load.kill(); load.wait()
                    while calm and os.getloadavg()[0] > calm: time.sleep(5)
                    load = subprocess.Popen([HOG, threads, "3600", qos or "utility"]); time.sleep(float(os.environ.get("WARM", "3")))
                results[variant].append(run(variant))
    finally:
        if load: load.kill()
        if memory: memory.kill()
        quit_app()
    print()
    for variant, worst in results.items():
        print(f"{variant:<10} longest turn per round: " + ", ".join(f"{w:.0f} ms" for w in worst))

if __name__ == "__main__":
    main()
