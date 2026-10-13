#!/usr/bin/python3
import os, subprocess, sys, time
P = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, P)
from stress import move, click, send, key
AX = os.path.join(P, "ws", "axfocus")
pid = subprocess.run(["pgrep", "-x", "NotchIsland"], capture_output=True, text=True).stdout.split()[0]
def focus(label): print(f"{label:28} {subprocess.run([AX, pid], capture_output=True, text=True).stdout.strip()}", flush=True)
def tab(n, shift=False, gap=0.35, label="tab"):
    for i in range(n):
        if shift: send("flags shift"); key(48, "shift"); send("flags")
        else: key(48)
        time.sleep(gap); focus(f"{label}{i+1}")
def at(x, y, after=0.6):
    move(x, y, 8, 8); time.sleep(0.15); click(x, y, hold=0.08); time.sleep(after)
SEARCH = (1100, 487)
at(400, 300, 1.2); at(955, 243, 1.2); at(400, 300, 1.2); at(144, 129, 1.2); at(146, 173, 1.5)
at(*SEARCH); focus("search after changes")
tab(4); tab(2, shift=True, label="shift-tab")
time.sleep(16)
at(955, 243, 1.2); focus("picked after lapse"); tab(3, label="inspector tab")
at(400, 300, 1.2); at(1083, 357, 1.5); at(1004, 357, 1.5)
at(*SEARCH, 0.3); focus("search 2"); tab(3, label="tab2"); tab(1, shift=True, label="shift2")
key(53); time.sleep(0.5)
