# NotchIsland performance tests

This file lists the tests run on the app to judge its performance and gives their results, so
anyone can repeat them on their own Mac and compare. It comes with every copy: in the repository
(`docs/`), inside the app (`NotchIsland.app/Contents/Resources/`) and next to the app in the `.dmg`.
The detailed before/after tables, and what was changed, are in `ENERGY-LOG.md` next to it.

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
| open-home / open-timer / open-shelf | opens the panel on that page, closes it |
| hover | pointer onto the notch and off |
| siri | opens Siri, closes it |
| siri-apps / siri-clipboard | opens Siri's app gallery / clipboard, closes it |
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

## Results in short

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
python3 Scripts/perf/events_bench.py mine
python3 Scripts/perf/levels_bench.py mine
python3 Scripts/perf/states.py mine 20
python3 Scripts/perf/night.py cycle mine 120
python3 Scripts/perf/idle.py 180 & python3 Scripts/perf/coalition.py 180 5
```

None needs administrator rights. Keep the Mac otherwise idle, compare runs only at similar battery
levels (both above or both below 30 %), and note that single runs vary by ±20–40 %.
