#!/usr/bin/python3
"""The Timer's ruler under trackpad-like swipes (`ws/moused`'s `scroll`), the panel opened by a hover:
each swipe's energy as Activity Monitor counts it, its worst 1 s, CPU and performance-core ms.

    ruler.py [rounds] [fast|slow|drag …]

RULER=x,y is a point on the ruler (default: the user's board on a 1280 × 832 pt screen, small
panel), OTHER=x,y a point on another widget, NOTCH=x,y the notch. A timer must not be running.
Wait ~40 s after a launch: scrolls over the island are not taken before.
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meter import run, move, send, wait

RULER = tuple(float(v) for v in os.environ.get("RULER", "790,55").split(","))
NOTCH = tuple(float(v) for v in os.environ.get("NOTCH", "640,6").split(","))

def swipe(dx, frames, momentum, after=1.6):
    def step():
        send(f"scroll {dx} 0 {frames} {momentum}"); time.sleep(after)
    return step

def drag(dx):
    def step():
        x, y = RULER
        send(f"down {x} {y}"); time.sleep(0.05)
        send(f"drag {x + dx} {y} 30 8")
        send(f"up {x + dx} {y}"); time.sleep(1.0)
        move(x, y, 4, 8); time.sleep(0.6)
    return step

OTHER = tuple(float(v) for v in os.environ.get("OTHER", "520,110").split(","))
TRACE = os.environ.get("RULER_TRACE")

def live():
    """Whether the ruler's scroll view is there (a test build's `NI_EXP_RULER_TRACE` file)."""
    state = False
    for line in open(TRACE):
        if " live " in line: state = True
        if " dead " in line: state = False
    return state

def open_panel():
    # Onto the ruler from another widget: the pointer brought straight down from the notch often
    # leaves the ruler's hover unreported (the scale stays a picture and the swipe turns the page).
    move(*NOTCH); time.sleep(1.2)
    for _ in range(6):
        move(*OTHER, 20, 12); time.sleep(0.6)
        move(*RULER, 20, 12); time.sleep(0.8)
        if not TRACE or live(): break
    time.sleep(0.8)

def main():
    args = sys.argv[1:]
    rounds = int(args.pop(0)) if args and args[0].isdigit() else 2
    kinds = args or ["fast", "slow"]
    steps = [("open", open_panel)]
    for _ in range(rounds):
        if "fast" in kinds:
            steps += [("fast up", swipe(8, 40, 80)), ("fast down", swipe(-8, 40, 80))]
        if "slow" in kinds:
            steps += [("slow up", swipe(2, 120, 0)), ("slow down", swipe(-2, 120, 0))]
        if "drag" in kinds:
            steps += [("drag up", drag(-120)), ("drag down", drag(120))]
    steps += [("rest", wait(2.0))]
    run(steps)
    move(NOTCH[0], 420); time.sleep(0.5)

if __name__ == "__main__":
    main()
