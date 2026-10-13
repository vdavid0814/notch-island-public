#!/usr/bin/python3
# tabtest.py: Tab / ⇧Tab through Settings ▸ Widgets, printing the focused element after each step.
import os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from stress import move, click, send, key
# Build: swiftc -O ws/axfocus.swift -o ws/axfocus. Open Settings ▸ Widgets first (1280 × 832 pt points).
AX = os.path.join(HERE, "ws", "axfocus")
pid = subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0]
def focus(label):
    out = subprocess.run([AX, pid], capture_output=True, text=True).stdout.strip()
    print(f"{label:28} {out}", flush=True)
def tab(n, shift=False, gap=0.35, label="tab"):
    for i in range(n):
        if shift: send("flags shift"); key(48, "shift"); send("flags")
        else: key(48)
        time.sleep(gap); focus(f"{label}{i+1}")
def at(x, y, after=0.6):
    move(x, y, 8, 8); time.sleep(0.15); click(x, y, hold=0.08); time.sleep(after)
SEARCH = (1100, 487)
at(400, 300, 1.5)                       # nothing picked
at(*SEARCH); focus("search clicked")
tab(4); tab(2, shift=True, label="shift-tab")
at(955, 243, 1.5); focus("picked system")
tab(2, label="tab-in-inspector")
at(400, 300, 1.5); focus("unpicked")
at(*SEARCH, 0.2); focus("search (fast)")
tab(1, gap=0.1, label="fast tab"); tab(2)
at(144, 129, 1.5); at(146, 173, 1.5)     # General, back to Widgets
at(*SEARCH, 0.25); tab(3, gap=0.25, label="after page switch tab")
key(53); time.sleep(0.5)
