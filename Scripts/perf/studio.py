#!/usr/bin/python3
"""Settings ▸ Widgets by real clicks: a widget picked on the stage and let go, the stage's modes
(Top Bar, Size and back), Customize opened and closed. Open the page first
(`drive.py settings/widgets 4`, with `NI_APP` set), on the home page with nothing picked.

    studio.py [rounds] [picks|modes|customize …]

The points are for a 1280 × 832 pt screen with the default panel; each can be set in the
environment as "x,y": TIMER, SYSTEM (two widgets on the stage), EMPTY (the stage's desktop),
TOPBAR, SIZE, WIDGETS (the mode bar), WIDGETS_IN_SIZE (the same button while Size is shown: the
stage is taller), CUSTOMIZE (the picked widget's Customize…), DONE (Customize's Done).
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meter import run, move, click

def point(name, default):
    return tuple(float(v) for v in os.environ.get(name, default).split(","))

TIMER, SYSTEM, EMPTY = point("TIMER", "912,185"), point("SYSTEM", "955,243"), point("EMPTY", "400,300")
TOPBAR, SIZE, WIDGETS = point("TOPBAR", "1083,357"), point("SIZE", "1161,357"), point("WIDGETS", "1004,357")
WIDGETS_IN_SIZE = point("WIDGETS_IN_SIZE", "1004,555")
CUSTOMIZE, DONE = point("CUSTOMIZE", "1131,446"), point("DONE", "851,62")

def press(at, after=2.5):
    def step():
        move(*at, 8, 8); time.sleep(0.3)
        # Held: some buttons let a 50 ms click pass unnoticed.
        click(*at, hold=0.1); time.sleep(after)
    return step

GROUPS = {
    "picks": [("pick-timer", press(TIMER)), ("pick-system", press(SYSTEM)), ("unpick", press(EMPTY))],
    "modes": [("mode-topbar", press(TOPBAR)), ("mode-widgets", press(WIDGETS)), ("mode-size", press(SIZE)),
              ("mode-back", press(WIDGETS_IN_SIZE))],
    "customize": [("pick-system", press(SYSTEM)), ("customize", press(CUSTOMIZE, 3.0)), ("done", press(DONE, 3.0)),
                  ("unpick", press(EMPTY))],
}

def main():
    arguments = sys.argv[1:]
    rounds = int(arguments.pop(0)) if arguments and arguments[0].isdigit() else 2
    names = arguments or list(GROUPS)
    steps = [(f"{name}{r + 1}", step) for r in range(rounds) for group in names for name, step in GROUPS[group]]
    run(steps)

if __name__ == "__main__":
    main()
