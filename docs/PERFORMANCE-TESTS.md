# NotchIsland performance tests

This file lists the tests run on the app to judge its performance and gives their results, so
anyone can repeat them on their own Mac and compare. It comes with every copy: in the repository
(`docs/`), inside the app (`NotchIsland.app/Contents/Resources/`) and next to the app in the `.dmg`.
The detailed before/after tables, and what was changed, are in `ENERGY-LOG.md` next to it.

## The October 2, 2026 run (after v0.7.2): Settings kept, Siri read ahead

**Setup.** The same MacBook Air M5, macOS 27, on battery (75 → 58 %). Release builds of v0.7.2 (26)
and this work, diagnostics reports removed from both.

**What was run**
1. **Every animation, back to back** (`Scripts/perf/ab.py` → `anim.py`, which now counts GPU energy
   and the energy billed to the app): two rounds, before and after alternating, a fresh launch and
   35 s of rest before each. Scenarios: settings-tour (new: every Settings page twice) twice, siri,
   siri-search, siri again, siri-apps, open-home, hover, spam-open, spam-pages, volume, airpods,
   battery, timer-done.
2. **The window server** (`ws_bench.py`, real pointer): rest, a Settings tour, Settings ▸ General
   at rest, ten hover opens.
3. **Where the time goes**: `sample` with `selftime.py`, `chain.py` and `subtree.py` (new); the
   energy of a scenario split by `parts.py` (new): CPU, GPU, billed by other processes.
4. **It still works and looks the same**: screenshots of Settings' pages, the Customize editor,
   Settings closing mid-way, the gallery scrolled, the panel's page switch; real clicks, typing
   and Esc in Settings (`ws/mouse`, `ws/key`).
5. **Unit tests** (`Scripts/test.sh`): 887 tests.

**Results** (Energy Impact, worst 5 s, before → after): a Settings tour 591 → 41 the first time after
a launch, 401 → 41 later; Siri's first opening 79 → 71, typing a word the first time 377 → 286; a
burst of page switches 47 → 75 (the new slide); opening the panel 13 → 15, a timer finishing
9.8 → 11.6. Longest main-thread turn while Settings opens and changes pages: 245–410 ms → ≤ 70 ms.
Details: `ENERGY-LOG.md`.

## The October 1, 2026 run (v0.7.1, build 25): the window server

**Setup.** The same MacBook Air M5, macOS 27, on battery, music playing. Release builds of v0.7 (24)
and v0.7.1 (25), diagnostics reports removed from both.

**What was run** (`Scripts/perf/ws/ws_bench.py`, which also counts the window server and coreaudiod)
1. **Rest** 120 s with music, the pointer away; once without NotchIsland at all (the window server's
   own baseline, 2–3 mW).
2. **10 opens and closes** by hovering the real pointer onto the notch: 3 s open, 3 s closed.
3. **A Settings tour**: opened from the panel's gear, each of the five pages twice (click, 1.5 s,
   eight lines down, 2 s), closed; a 60 s window.
4. **Steady pages**: each Settings page at rest, at its top and scrolled down; the open panel on a
   playing track.
5. **Ablations**: one piece switched off at a time (the halo, the fade's blur, the glass, the glass
   container, the outline clip, the backdrop blur, the sidebar's glass, each animation picture),
   to find what the window server pays for; and the island's layer tree (`demo/state`).
6. **Looks unchanged**: screenshots over a still checkerboard (`frames/backdrop`) compared pixel by
   pixel; Settings' colours sampled on screen before and after.
7. **Unit tests** (`Scripts/test.sh`).

**Results** (two rounds, before → after): window server at rest 16.4 → 14.2 mW; 10 opens 7.8 → 4.4 J
(app 0.46 → 0.56 J); Settings tour 13.1 → 4.3 J (app 7.2 → 6.7 J); Settings ▸ General at rest 785 →
23 mW. Details: `ENERGY-LOG.md`.

## The September 30, 2026 run (v0.6, build 23)

**Setup.** The same MacBook Air M5, macOS 27, on battery the whole time (57 % for the middle pass,
39 → 38 % for the final one), music playing. Release builds of v0.5.1 (22) and v0.6 (23), signed
with the same identity, diagnostics reports removed from both.

**What was run**
1. **Every animation, back to back** (`Scripts/perf/ab.py`, which runs `anim.py`): v0.5.1 and v0.6
   alternating, two rounds each, a fresh launch and 35 s of rest before each round. Scenarios:
   settings, siri, siri-apps, siri-search (new: typing "smile" into Spotlight), open-home,
   open-timer, open-battery (new: the battery page), spam-open, spam-siri, spam-pages, timer-done,
   airpods, volume. Once after the first half of the work, once at the end.
2. **Where the time goes**: `sample` of the app during settings, siri-search, spam-open, spam-siri
   and the first opening after a launch, v0.5.1 against v0.6, compared symbol by symbol.
3. **Suspects switched off one at a time** (a v0.6 build with one change undone, measured back to
   back with v0.6): the glow's new animation, the widgets' concentric corners, the header's new
   picker and battery button.
4. **Offscreen benchmarks** in the unit tests (`NI_BENCH=1`): building the widget board (CPU
   instructions), typing a query through Spotlight's model and view, opening Settings pages.
5. **Looks unchanged**: frozen-frame screenshots (`demo/freeze`) of v0.5.1 and v0.6 compared pixel
   by pixel against two shots of the same build: Siri 0.1 and 0.3 s into opening and settled, the
   app gallery, the panel 0.15 s in and settled, the timer page, Settings ▸ General and Widgets.
6. **Unit tests** (`Scripts/test.sh`): 724 tests in 160 suites, then the 242 widget snapshots
   (exact, in their own process).

**Results** (Energy Impact, worst 5 s, v0.5.1 → v0.6): Settings 501 → 425, Siri's app gallery
48 → 41, the panel's pages 53 → 49, opening the panel 12.8 → 12.4, the battery page 7.5. Above
v0.5.1: the first search after a launch 113 → 133 (the new Spotlight sources), fast repeated
opening of the panel 33 → 38 and of Siri 80 → 91 (after the other scenarios; within noise when run
first), the first panel opening after a launch 34 → 47. Unit tests: everything passes except the
liquid card's hand-tuned lead (the owner's 0.25 → 0.20 change) and timing tests that pass alone.
Full tables and what changed: `ENERGY-LOG.md`.

## Setup of the September 29, 2026 run (v0.5, build 21)

- MacBook Air M5 (Mac17,3), macOS 27, built-in 3024×1964 display.
- On battery the whole time (80 → 77 % before, 59 → 56 % after). Below ~30 % macOS keeps the app on
  its efficiency cores only, so both passes were kept above it.
- Settings on this Mac: glass style Fade, level style banner, Follow the Music on.
- Music playing in Music.app unless a step pauses it.
- Release builds of the old ("before") and new ("after") version, both measured with the same
  scripts in the same order. The "after" build was also compared with the "before" build back to
  back where a result was close.
- Diagnostics reports were switched off in the measured copies (no network traffic while measuring).
- **Activity Monitor was used as the reference**. Its Energy Impact column equals the app's energy
  in mW (its "coalition": the app plus its helper processes). On screen, opening Settings on the old
  build read 245. The scripts below compute the same number.

## The tests, in the order they ran

Each app action is driven through the app's own `notchisland://` commands (the `demo/…` ones show
the banners and cards without the real event), so every run does exactly the same thing.

### 1. Rest (`Scripts/perf/idle.py`, `Scripts/perf/coalition.py`)
- **Music playing, island compact (bars moving), 180 s**: energy every 5 s, CPU %, wake-ups/s,
  memory.
- **Music paused, 90 s** (after the 10 s the pill stays): the same.
- **Repeated back to back, old vs new, 2 × 100 s each**, because the first old run's bars only
  started listening ~70 s in.

### 2. Every single event (`Scripts/perf/events_bench.py`, 5 s each, reset between)
Volume banner, brightness banner, charger connected, charger removed, low battery, finished timer,
file drop, **AirPods connected card**, **AirPods noise-control card** (noise cancellation,
transparency, adaptive, off), a new track, Siri's app gallery, Siri's clipboard.
Measures: CPU ms, idle wake-ups, `top`'s 1 s power peak, memory.

### 3. Liquid volume card (`Scripts/perf/levels_bench.py`)
Changes the Mac's real volume up and down six times, 4 s apart (restored at the end): the card that
runs out to macOS's own volume card. Measures CPU ms per change, wake-ups, power, memory.

### 4. Every animation, as Activity Monitor counts it (`Scripts/perf/anim.py`)
Worst 1 s and worst 5 s energy window and CPU ms for each:

| scenario | what it does |
|---|---|
| open-home / open-timer / open-shelf / open-battery | opens the panel on that page, closes it |
| hover | pointer onto the notch and off |
| siri | opens Siri, closes it |
| siri-apps / siri-clipboard | opens Siri's app gallery / clipboard, closes it |
| siri-search | types "smile" into Spotlight, a letter every 0.12 s, closes it |
| volume | three volume steps in 1 s |
| battery | charger connected banner |
| airpods | AirPods connected card |
| timer-done | a 3 s timer finishing, bell and sound |
| settings | opens Settings ▸ General, then Widgets, closes |
| spam-open | panel open/close 10 times, 0.25 s apart |
| spam-open-slow | panel open/close 8 times, 0.6 s apart |
| spam-hover | hover in/out 10 times, 0.3 s apart |
| spam-siri | Siri open/close 8 times |
| spam-pages | home → timer → shelf pages, 4 rounds |
| spam-volume | 30 volume changes, 0.12 s apart |

### 5. Steady states (`Scripts/perf/states.py`, 20 s each)
Compact at rest, panel open on home, panel open on the timer, Siri's field, Settings ▸ General,
Settings ▸ Widgets, Settings ▸ Live Activities. Measures CPU %, power mean and peak, wake-ups/s,
memory.

### 6. The soak (`Scripts/perf/night.py cycle <label> 120`, sampled 4 times a second)
Rest with music; panel home ×5, timer ×3, shelf ×3; hover ×4; Siri ×3; app gallery ×2;
clipboard ×2; volume steps; charger, unplug and low battery banners; AirPods card; finished timer;
file drop; next track; Settings (General, Widgets, Live Activities); after Settings; rest paused;
panel with music paused ×3; music again; two 1-minute rests (to catch memory that does not come
back). Measures CPU %, GPU %, power, memory, wake-ups per scenario.

### 7. Where the time goes (spikes)
For the worst scenarios (opening Settings, the diagnostics report after launch) the app was
sampled with `sample` during the spike to see which code ran. That is how the 16-bit drawing of
Settings' shadows, blurs and gradients on the performance cores was found.

### 8. Looks unchanged
Screenshots over a still background with every animation frozen at a given moment
(`notchisland://demo/freeze?t=…`): Settings 0.1, 0.25 and 0.45 s into opening and settled (General,
Widgets), the panel 0.2 s in and settled, Siri, the volume banner, the finished-timer banner. Old
and new builds were compared pixel by pixel against the difference between two shots of the same
build (`Scripts/perf/frames/pixels.swift`). Result: no pixel of the island differs beyond that
noise.

### 9. Unit tests (`Scripts/test.sh`)
501 tests in 116 suites: **500 pass**. The one failure (`LiquidCardExitTests.eachCardLeavesWithItsOwnLead`)
checks a hand-tuned timing of the noise-control card that was being changed at the time (0.25 →
0.20), not part of the performance work.

## Results in short (the v0.5 run)

Energy Impact as Activity Monitor shows it (worst 5 s), before → after:

| | before | after |
|---|---|---|
| Opening Settings (back-to-back A/B, energy per opening) | ~2.4 J, peak ~370 | ~1.4 J, peak ~172 |
| Opening the panel | 38.2 | 27.9 |
| Siri | 13.8 | 12.1 |
| Siri's app gallery | 62.5 | 48.7 |
| Siri's clipboard | 22.5 | 15.3 |
| Timer page | 12.0 | 8.5 |
| Volume banner | 7.1 | 5.8 |
| Liquid volume card (`top` power peak per change) | 28.0 | 5.4 |
| Rest with music playing | ~0.1 (0.13 mW) | ~0.1 (0.13 mW) |
| Memory at rest after the tour | 69–73 MB | 59–63 MB |

Still above 30: opening Settings, Siri's app gallery, and fast repeated use of Siri, the panel and
its pages. Full tables per scenario: `ENERGY-LOG.md`.

## Running them yourself

Start NotchIsland, play something in Music, then from the repository:

```
python3 Scripts/perf/anim.py
python3 Scripts/perf/ab.py ab.tsv old=/path/Old.app new=/path/New.app -- settings siri open-home
python3 Scripts/perf/events_bench.py mine
python3 Scripts/perf/levels_bench.py mine
python3 Scripts/perf/states.py mine 20
python3 Scripts/perf/night.py cycle mine 120
python3 Scripts/perf/idle.py 180 & python3 Scripts/perf/coalition.py 180 5
```

None needs administrator rights. Keep the Mac otherwise idle, compare runs only at similar battery
levels (both above or both below 30 %), and note that single runs vary by ±20–40 %.
