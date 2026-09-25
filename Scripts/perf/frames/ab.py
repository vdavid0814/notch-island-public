#!/usr/bin/python3
"""ab.py <label> <route> [t ...]: for each t, holds the island's springs t seconds into <route>
(demo/freeze), screenshots that frame with the glass drawn by AppKit, by SwiftUI and by AppKit again
(the noise floor), and prints how far apart they are. BEFORE=<route> is run (settled) first.
Needs the backdrop (./backdrop) running. Images go to $OUT (default: /tmp/ni-frames)."""
import subprocess, sys, time, os
APP = os.environ.get("NI_APP", os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../build/NotchIsland.app"))
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.environ.get("OUT", "/tmp/ni-frames"); os.makedirs(OUT, exist_ok=True)
REGION = os.environ.get("REGION", "140,0,1000,780")
def url(u): subprocess.run(["open", "-g", "-a", APP, "notchisland://" + u]); time.sleep(0.05)
def shot(name): subprocess.run(["screencapture", "-x", "-R", REGION, os.path.join(OUT, name + ".png")])
def stats(a, b): return subprocess.run([os.path.join(HERE, "pixels"), "stats", os.path.join(OUT, a + ".png"), os.path.join(OUT, b + ".png")], capture_output=True, text=True).stdout.strip()
label, route = sys.argv[1], sys.argv[2]
times = [float(x) for x in sys.argv[3:]] or [0.0]
for t in times:
    url("demo/freeze"); url("close"); time.sleep(1.2)
    if os.environ.get("BEFORE"): url(os.environ["BEFORE"]); time.sleep(1.2)
    url(f"demo/freeze?t={t}"); url(route); time.sleep(1.0)
    n = f"{label}-{t}"
    url("demo/glass?impl=appkit"); time.sleep(0.4); shot(n + "-ak")
    url("demo/glass?impl=swiftui"); time.sleep(0.4); shot(n + "-sui")
    url("demo/glass?impl=appkit"); time.sleep(0.4); shot(n + "-ak2")
    print(f"{n}: {stats(n + '-sui', n + '-ak')}   [noise: {stats(n + '-ak', n + '-ak2')}]", flush=True)
url("demo/freeze"); url("close")
