#!/usr/bin/python3
"""A Settings tour by real clicks, as a hand does it: opened from the panel's gear, every page from
the sidebar, Widgets' stage modes (Top Bar, Size, back), a widget picked and Customize opened and
closed, then Settings closed by its ✕. Each step's energy (meter.py). Points for a 1280 × 832 pt
screen with the default panel.

    tour.py [rounds]
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meter import run, move, click, send
from stress import NX, NY, AWAY, GEAR

PAGES = {"general": (144, 129), "widgets": (145, 173), "activities": (162, 230), "spotlight": (148, 274), "about": (139, 331)}
TOPBAR, SIZE, WIDGETS_IN_SIZE = (1083, 357), (1161, 357), (1004, 555)
SYSTEM, EMPTY, CUSTOMIZE, DONE = (955, 243), (400, 300), (1131, 446), (851, 62)
CLOSE = (1205, 14)

def press(at, after=2.5, hold=0.1):
    def step():
        move(*at, 8, 8); time.sleep(0.3)
        click(*at, hold=hold); time.sleep(after)
    return step

def open_settings():
    move(NX, NY); time.sleep(0.9)
    move(*GEAR, 6, 8); click(*GEAR); time.sleep(3.0)

def scroll_page():
    move(760, 600, 8, 8); time.sleep(0.3)
    send("scroll 0 25 30 40"); time.sleep(1.0)
    send("scroll 0 -25 30 40"); time.sleep(1.5)

def steps(r):
    s = [("open", open_settings)]
    for name in ("general", "activities", "spotlight", "about", "widgets"):
        s.append((name, press(PAGES[name])))
    s += [("scroll", scroll_page), ("topbar", press(TOPBAR)), ("size", press(SIZE)), ("back", press(WIDGETS_IN_SIZE)),
          ("pick", press(SYSTEM)), ("customize", press(CUSTOMIZE, 3.0, 0.12)), ("done", press(DONE, 3.0, 0.12)),
          ("unpick", press(EMPTY)), ("close", press(CLOSE, 2.0)), ("away", lambda: (move(*AWAY), time.sleep(2.0)))]
    return [(f"{n}{r + 1}", f) for n, f in s]

if __name__ == "__main__":
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    run([x for r in range(rounds) for x in steps(r)])
