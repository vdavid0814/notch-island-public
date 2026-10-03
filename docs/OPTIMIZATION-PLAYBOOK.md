# How NotchIsland gets optimized

The method behind the October 2026 rounds (Settings 500 → 15–23, Settings ▸ Widgets scrolling
1400 → 12 in Activity Monitor): what to measure, how to find the cause, which tactics worked and
which did not, and how to keep the look identical. The numbers are in `ENERGY-LOG.md`, the tools in
`Scripts/perf/README.md`.

## 1. Measure what the user sees

- **Activity Monitor's Energy Impact** (Energy tab, search "notch") is the number the user judges.
  Read it while the scenario runs, every few seconds. In "Applications in Last 12 Hours" the row
  can stay on an instance that exited; switch to *View ▸ All Processes* and back afterwards.
- **The same in a script**: `coalition.py` (CPU %, mW of the app's coalition), `anim.py` (worst 1 s /
  5 s windows ≈ Activity Monitor), `parts.py` (CPU / GPU / billed by other processes),
  `ws/ws_bench.py` (WindowServer — most of the island's cost is its frames).
- **Release builds only** (a debug build costs ~3× in Settings). **Back to back**, old and new in
  turn (`ab.py`, or the same script twice), each from a fresh launch with 20–30 s to settle.
- **Power state**: under ~30 % battery macOS keeps the app on the efficiency cores; compare only
  runs made in the same state, best on the charger.
- **One instance**: `drive.py` and `bench.url` open `NI_APP`; without it set they launch the
  installed app next to the test build. `pgrep -lx NotchIsland` before reading anything.

## 2. Reproduce it the same way every time

- Synthetic input, never a hand: `ws/smooth` (trackpad scroll with phases; momentum tail;
  `HOLD=1` keeps the fingers down), `ws/mouse` (move, click), `ws/key`, `drive.py` (the app's
  `notchisland://` URLs: `settings/widgets`, `close`, …).
- `scroll_bench.sh <app> [page]` scrolls a Settings page and prints CPU / mW; `WATCH=1` only
  scrolls (~40 s) for reading Activity Monitor.
- Test copies of a build: `swift build -c release --product NotchIsland` then
  `mkapp.sh .build/release/NotchIsland Scripts/perf/apps/<name>.app` (signed, no diagnostics).

## 3. Find the cause, not just the hot function

1. **`sample NotchIsland 4 1`** while it runs, then `selftime.py` (busy time per thread, hottest
   self time), `subtree.py` (what a node spends), `chain.py` (who calls it). Check the sample's
   length before turning samples into percentages.
2. **Who asks for the work**: put a temporary override at the point where the work is requested
   (e.g. `needsLayout`'s setter on the hosting view) and log `Thread.callStackSymbols` for the first
   N calls while the scenario runs. Group the stacks (`sort | uniq -c`). This is how the scrolling
   cost was found: 69 of the layouts came from `NSHostingView.geometryInWindowDidChange`.
3. **Is a framework path avoidable?** `lldb --batch -o "target create .build/release/NotchIsland"
   -o "image lookup -r -s '<name>'" -o "disassemble -s <address> -c 120"` (no attaching, no
   password prompt). It showed the geometry observation is unconditional — so the fix had to stop
   the geometry from changing, not the reaction to it.
4. **Cost per event against the frame**: time one step (e.g. `layoutSubtreeIfNeeded()` right after
   the change, logged). 20–24 ms in one step is a dropped frame at 60 Hz and two at 120 Hz.
5. `NI_TRACE=1`: every main run-loop turn over 2 ms in the log ("TURN"). In zsh `log` is a
   builtin: use `/usr/bin/log stream`.
6. **Moment by moment**: `timeline.py <scenario>` prints the coalition's energy every 50 ms, split
   into the app's own, GPU and billed by other processes (Spotlight, Contacts…), with the P-core
   milliseconds; `launch.py <app>` does the same for a launch and what is prepared after it. With
   Activity Monitor at *Very often (1 s)*, its number is `anim.py`'s "worst 1 s".
7. **What a sample's time goes through**: `fold.py <sample> "Main Thread" --by <regex> …` groups
   the busy samples by the first of several frames (layout, graph update, commit, ours).
8. Test programs that touch the Desktop, Documents… run unsigned trip the privacy prompt and hang
   (and leave the prompt on screen): measure inside the app instead (a temporary env switch).

## 4. Tactics that worked

- **Per frame on the render server, the model once**: a scroll moves only the clip view's layer
  (`sublayerTransform`) and the scroller's knob; the real scroll happens when it stops
  (`ScrollCoalescer`). Anything that moves `NSView`s with SwiftUI inside them at every frame
  invalidates every hosting view in them.
- **Imitate the system where it is measured**: the rubber band was redone on the layer with AppKit's
  curves fitted from screenshots (held gesture, then release, then a fling), within half a point.
- **Build ahead and keep**: Settings is built once, unseen, in a window of its own; hidden pages lay
  nothing out (`DeferringHostingView`); pages built whole (non-lazy `GalleryGrid`, `SwatchGrid`).
- **Freeze what is not seen**: pictures, clocks and level readings stand still while Settings is
  closed (`SettingsPresence`, `PictureReadings`, `pausesWithSettings`).
- **Skip what nobody sees**: Settings does not take the keyboard as it opens (80 % of the opening),
  only with the first click; scroll events go straight to the scroll view; cursor hit tests stop at
  the page while it scrolls.
- **Wake up less**: polling that slows down when nothing happens (clipboard every 5 s after a minute
  idle); nothing at rest (~0 wake-ups/s).
- **Read ahead, at low priority**: Siri's lists and apps at `.utility` / `.background`, kept for
  30 minutes.
- **Draw once per size, keep the picture**: the fade style's blurred, shaded black was drawn on the
  CPU at every opening (`RB_DISABLE_GPU`: SwiftUI's `drawingGroup` renders on the CPU) — now a
  picture per size (`FadeShadeCache`). Look in a sample for `CABackingStoreUpdate_` / `ripc_` /
  `vImage` under the commit: that is drawing, and drawing the same thing again is avoidable.
- **Memory instead of a service**: Siri's apps come from the list it keeps (with Spotlight's other
  names) instead of a Spotlight query per keystroke; Spotlight's files, the dictionary and Contacts
  only after a 0.15 s pause in the typing, one search at a time. A service's work is billed to the
  app ("billed" in `timeline.py`): 20–300 mJ per Spotlight query.
- **Keep what is built, hidden**: the Customize editor (its native controls cost ~150 ms to build)
  stays in its window hidden between openings (`DeferringHostingView` lays nothing out hidden).

## 5. Tried and dropped (measured equal or worse)

- **The main thread's quality of service for long work** (October 3): a burst on the main thread
  longer than ~40 ms ran on the performance cores even with `pthread_set_qos_class_self_np`
  background (logged: `qos_class_self()` 9, yet 75 % of a 130 ms Settings preparation step on the
  P cores), set before or after the task's `await`, with the task itself at `.background`. A test
  program's main thread stayed on the E cores, so something in the app raises it. `PRIO_DARWIN_BG`
  kept most of it off the P cores but made steps 2–8× slower (the island blocked up to a second)
  and still showed P bursts. Short pieces (< ~30 ms) stay on the E cores by themselves: split work,
  or avoid it, rather than relying on `MainThrift` for long bursts.
- **Splitting Siri's Home Folder scope** into its subfolders (to leave ~/Library out of Spotlight's
  search): opening ~/Pictures, ~/Music… for the scope asks the privacy prompt and blocks.
- **Keeping the closed panel longer** (`keepDuration` 600 s): opening it from idle cost the same,
  because the whole content stack leaves the hierarchy at idle; the kept page only helps
  panel → banner → panel.

An AppKit `NSScrollView` around a SwiftUI page, responsive scrolling, AppKit hover tracking instead
of `.onHover`, one `onContinuousHover` for the gallery, scrolling the clip view's bounds by hand,
committing the layer scroll every 0.12 s (each commit was 20–24 ms), handing the scroll ends to
AppKit (Activity Monitor 200 there), moving hosting views between superviews or windows, keeping
Settings inside the island's window.

## 6. Keep the look and the motion identical

- **Screenshots, old and new, same state**: `screencapture -x`, then `image-diff.swift` (a live
  clock or reading changes ~0.1–0.3 % of the pixels; more means a real change).
- **Mid-motion**: screenshot during the scroll or animation (no blank parts, scroller shown) and
  sample a curve at several delays across repeated runs.
- **Where a scroll really is**: `ws/axscroll <pid>` (Accessibility), in any build.
- **After every UI drive**: `pgrep -x NotchIsland` and `~/Library/Logs/DiagnosticReports` — a new
  layout crashed once on an infinite width proposal and only this showed it.
- Synthetic gestures that end at speed without momentum make AppKit coast on; a real trackpad sends
  momentum instead. Compare like with like.

## 7. Ship it

`Scripts/test.sh` (the timing-sensitive tests can fail under the full suite's load — run them alone
with `swift test --filter`); a line in `ENERGY-LOG.md` (before → after, Activity Monitor and
CPU) and `PERFORMANCE-TESTS.md`; commit; `Scripts/run.sh` (release); a last Activity Monitor reading
on the installed build.

## The request that starts a round

> Optimize NotchIsland's energy and frame rate for **[scenario, e.g. scrolling Settings ▸ Widgets]**
> following `docs/OPTIMIZATION-PLAYBOOK.md`. Activity Monitor showed **[number]** there; the target is
> **[number]**. Nothing may change in the look or the motion. Measure in Activity Monitor and with
> the scripts, old and new back to back, find who asks for the work before changing anything,
> check screenshots old against new, then commit, install with `Scripts/run.sh` and report the
> before → after numbers.
