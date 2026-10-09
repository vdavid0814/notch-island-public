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
5. `NI_TRACE=1`: every main run-loop turn over 2 ms in the log ("TURN").

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

- **Measure the real path, not only the URL**: `phases.py` drives the real pointer (`move:x,y`,
  `click:x,y`) as well as `notchisland://` steps. A click carries the event's priority into the
  turn it handles, so its work runs on the performance cores where a URL-driven run (an Apple
  event) shows less: opening Settings from the gear measured 250–300 where `settings/general`
  read 70–85; Customize measured 2600 only by a click.
- **Look at rest while the mouse moves**: global event monitors run a whole main run-loop turn (a
  Core Animation commit included) for every move anywhere on the screen. Rest with a still mouse
  can read 0.0 while normal use reads 6–7. A listen-only `CGEventTap` on a thread of its own that
  hands the main thread only the moves that matter costs a fifth (`BandPointerWatch`).
- **Kept views can keep working**: a `.task` loop in a kept, hidden Settings page ran for as long as
  the app did (TCC reads every 2 s). Look for `.task`, timers and observers under anything that is
  built ahead and kept, and tie them to the page being shown (`settingsPageVisit`).
- **A `drawingGroup` around an animated scale** draws the whole picture again at every frame on the
  CPU (`RB_DISABLE_GPU`). Animate the scale outside the picture.
- **Who invalidates a platform view**: a temporary swizzle of `NSView`'s `needsDisplay` /
  `needsLayout` / `viewWillMove(toWindow:)` that logs the call stack for one class showed that
  SwiftUI takes the panel's native page picker out of the window when the window shrinks to the
  notch, and puts it back (layers, layout, drawing) at every opening.
- **Ablations by environment switch** (`NI_EXP_…` read once, removed afterwards): hide one part,
  measure the CPU and energy of the step, compare. Quicker than reading profiles when the work is
  spread over many small updates.

## 5. Tried and dropped (measured equal or worse)

An AppKit `NSScrollView` around a SwiftUI page, responsive scrolling, AppKit hover tracking instead
of `.onHover`, one `onContinuousHover` for the gallery, scrolling the clip view's bounds by hand,
committing the layer scroll every 0.12 s (each commit was 20–24 ms), handing the scroll ends to
AppKit (Activity Monitor 200 there), moving hosting views between superviews or windows, keeping
Settings inside the island's window.

October 9 2026: the panel's opening at background priority (`MainThrift.lowPower`, half the energy,
but every opening hitched 200 ms instead of 83); the hidden kept panel at a near-zero opacity
instead of 0 (SwiftUI still drops what lies outside the notch-sized window); Customize's steps in
as `visualEffect` instead of `offset`/`opacity` (closing cheaper, opening +150 ms of CPU); Customize's
first ink reading 0.65 s later in a `Task(priority: .background)` on the main actor (the opening went
from ~650 to 2200–2900: the main thread's work moved to the performance cores).

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
