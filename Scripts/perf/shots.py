#!/usr/bin/python3
"""shots.py <out-dir> <label=app> [<label=app> …] -- [route …]: the island settled in each state,
screenshotted for every build (fresh launch each), then each later build against the first with
frames/pixels stats. Run frames/backdrop first for a still background."""
import os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
REGION = os.environ.get("REGION", "290,0,700,420")
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
args = sys.argv[2:]; split = args.index("--") if "--" in args else len(args)
apps = [a.split("=", 1) for a in args[:split]]
routes = args[split + 1:] or ["open?page=home", "open?page=battery", "demo/volume?level=0.5", "siri", "demo/charging"]
def url(app, u): subprocess.run(["open", "-g", "-a", app, "notchisland://" + u])
for label, app in apps:
    subprocess.run(["pkill", "-x", "NotchIsland"]); time.sleep(1.5)
    subprocess.run(["open", "-g", "-a", app]); time.sleep(float(os.environ.get("SETTLE", "12")))
    for i, r in enumerate(routes):
        url(app, r); time.sleep(float(os.environ.get("WAIT", "1.6")))
        subprocess.run(["screencapture", "-x", "-R", REGION, f"{out}/{label}-{i}.png"])
        url(app, "close"); url(app, "demo/reset"); time.sleep(1.5)
for label, _ in apps[1:]:
    for i, r in enumerate(routes):
        s = subprocess.run([f"{HERE}/frames/pixels", "stats", f"{out}/{apps[0][0]}-{i}.png", f"{out}/{label}-{i}.png"], capture_output=True, text=True).stdout.strip()
        print(f"{r:28} {apps[0][0]} vs {label}: {s}")
