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

- **Stress with a hand's input, not a tool's**: `stress.py` (hover in and out, cold openings,
  Settings from the gear, Customize) drives one long-lived `ws/moused`. A new event-posting process
  per step is checked by TCC, trustd and syspolicyd and the system bills it to the app that gets the
  events (~100 mJ each). Check "billed" in the output and, when it is large, who serviced it
  (`proc_pid_rusage` v4's `ri_serviced_energy` over all processes).
- **Do the work in the wait the user already has**: the hover delay (0.2 s) builds what the opening
  will show, in a turn of its own at background quality of service (`prewarmPanel`). The pointer
  event's own turn runs at the event's priority: hand the work to a run-loop timer, after
  `MainThrift.lowPower`.
- **A changing scale over CPU-rendered content redraws it every frame** (`drawingGroup`, `Canvas`,
  RenderBox effects under `RB_DISABLE_GPU`): show a picture drawn once while the scale moves
  (`SharpZoom.still`), the live view once it has settled. Find it by ablation: switch the animation
  off (`NI_EXP_…`), measure the cycle, then one scale at a time.

- **Ask who the system bills you for**: when a scenario's "billed" is large (`stress.py`, `parts.py`),
  run `serviced.py` beside it, then read that daemon's log (`/usr/bin/log stream --predicate
  'process == "…"' --info --debug`) and `sample` the app for the framework call that set it off.
  macOS 27's AppKit offered the island's windows to Spotlight at every opening (three items, ~90 mJ
  billed each time) and started the AutoFill helper process at the first text field (~480 mJ once
  per launch): both have a switch of AppKit's own (`NSEnableWindowTabIndexing`,
  `NSAutoFillHeuristicsEnabled`; found among AppKit's strings and its disassembly), registered as
  the app's defaults before it starts (`main.swift`). Look again after every macOS update.
- **A click's own turn runs on a performance core whatever the thread's quality of service is**, and
  a long burst there is 2.6–4.5 mJ a millisecond (`qos_burst.c`). What nobody watches the first
  frame of (a close) can be resolved in a turn of its own at background quality of service, the
  thread's priority back after that turn's commit (`MainThrift.lowPowerTurn`): a ninth of the
  energy for 2–3.5× the time. Animation frames at background came out 10–17× longer: never for
  motion. Utility, throughput tiers and work intervals all ran as user-interactive does.
- **A picture that is only ever a mask** keeps one byte a pixel (`CGImageAlphaInfo.alphaOnly`), and
  Core Animation's copy of it too: the fade style's shade for Settings was 2 × 14 MB.
- **`NI_TRACE=1` logs each long turn with its quality of service** (33 user-interactive, 9
  background): which turns of a transition are the performance-core ones. `stress.py` with
  `SECONDS_ROW=1` prints every second's performance-core ms beside its energy.
- **Never read energy under `sample`**: the sampled main thread stays on the efficiency cores (a
  switch that costs 2700 mJ read 145).

- **A scroll view of SwiftUI's lays its window's whole view tree out at every frame of a scroll**
  (it is an `NSScrollView`, `HostingScrollView`, whose offset is SwiftUI state). Where the content
  is simple, an `NSScrollView` of our own with layers drawn once costs a fifth (the Timer's ruler,
  `RulerScrollView`). To keep the look: read what SwiftUI made (`NI_LAYER_DETAIL=1` with
  `demo/state`: every layer's exact frame, corner, colour) and make the same layers; to keep the
  motion: trace both with the same gestures (the clip's origin at every change) and hook the
  same AppKit call SwiftUI does — list a class's methods and protocols at run time
  (`class_copyMethodList`, `objc_copyProtocolList`) to find it.
- **Motion that follows the pointer or the clock goes on layers of its own**: Fan Control's graph
  once showed the moment pointed at through SwiftUI state, and on the island (one glass container)
  the moves came to the screen in bursts — a screen recording frame by frame showed the line
  standing two or three frames, then jumping 200 px, while the cursor moved every frame. Moving
  `CALayer`s from the hover handler with actions off (no state) cost 0.04–0.16 ms a move against
  2.6 ms for the graph drawn again (that feature was dropped later). An `NSTrackingArea` of the
  layers' own view did not work on the island: the panel takes no mouse-moved events and the area
  sat wrong in the scaled view; SwiftUI's own hover gives the right points. The same graph now
  slides between readings: drawn once a reading into a layer, a linear `CABasicAnimation` carries
  it to where the next one comes in (`FanGraphLayerView`) — nothing on the main thread between.
- **A model value that changes sixty times a second must be read by leaves only**: a small view or
  modifier for each place it is shown. Read in a widget's body (or by an `onChange` there), the
  whole widget is built again at every change.
- **In a scaled view AppKit and SwiftUI disagree by a fraction of a point**: AppKit keeps a clip
  on device pixels, SwiftUI rounds in the view's own points. Compare screenshots on the part's own
  rectangle only (the island is see-through: whatever moves behind it differs too).
- **Check that the part under test is really live before a synthetic gesture**: hover often goes
  unreported to SwiftUI when the pointer is put somewhere (come in from a neighbouring view, and
  check), and scrolls are not delivered for ~30 s after a launch.
- **Kept views that take themselves out of the window** (`pausesWithSettings`) must come back only
  where they are seen: put back by a notification, every one of every page came back at each
  opening.
- **Another daemon's CPU changes every number** (`mediaanalysisd` at 200 % for an hour): look at
  `ps -Ao pcpu,comm -r | head` before a run and compare only runs made in the same state.

- **Memory that does not come back is usually a strong reference, not the allocator**: `heap <pid>`
  (count the app's own classes: one `SettingsSurfaceView` after Settings was "given up"), then
  `leaks <pid> --traceTree=<address of it>` (from `heap <pid> -addresses=<Class>`) — the roots that
  are statics or our own objects are the leak (`GlassSlide.lastPress`, Oct 13); the many "Swift
  Metadata" roots are conservative-scan noise. For large blocks without a type, launch with
  `MallocStackLogging=lite` and read `malloc_history <pid> <address>` (the wallpaper pictures).
- **A background turn is followed by AppKit's display cycle at full priority**: what the turn
  changed is laid out and drawn in the next frames, from the display link's source, at the thread's
  own priority. Keep the thread at background until those have run
  (`MainThrift.lowPowerTurn(holding:)`), and count the hold from the end of the work.
- **Simulate the power source and the user's absence** instead of unplugging or locking:
  `NI_POWER=battery|charger`, `demo/power`, `demo/away`, `demo/memorypressure`. Never lock the
  screen in a night run (it may need a password nobody can type).

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
from ~650 to 2200–2900: the main thread's work moved to the performance cores). Settings' live pictures hidden
instead of taken out of the window while it is closed (Settings itself cheaper, every track change
~28 → ~42: the hidden previews followed the music).

October 10 2026: the island's stage grown to the panel's frame already in the hover delay (equal on
warm openings); Settings opened in a turn after the click's (no difference: warm openings already
run on the efficiency cores); Settings' permission and Login Items reads only after a visit to
System Settings (the billing at an opening is Spotlight's, for the app's activation).

October 11 2026: Settings' pictures left in the window while it is closed (the close turn 105 → 95 ms
only); Settings' opening and the Widgets stage's mode switch in a low-priority turn (the opening
+0.1 s for −15 %; the switch 0.5–1.1 s with nothing shown); `autorecalculatesKeyViewLoop` on
Settings' window (Tab then loses the keyboard from the search field; the unfold's energy the same);
the unseen Top Bar page out of the mode deck (no change). See `ENERGY-LOG.md` for Size mode's unfold
(2–3 J: the page laid out at every frame) and the branch `wip-unfold-in-place`.

October 13 2026: SwiftUI's key view loop rebuilt once after a batch, or only when Tab is
pressed, instead of for every hosting view entering the window: what Tab reaches changed (kept:
skipping it for pictures only, which Tab cannot reach). Settings' paused pictures hidden in place
instead of taken out of the window (close worse); background turns started a frame later (no
change). Check that an `NI_EXP_…` switch really reached the app (`ps eww <pid>`): in zsh,
`set -- $v` does not split a string.

October 11 2026 (afternoon): a scroll gesture's later events sent straight to the view that took
its first, past AppKit's own routing (`NSWindow.sendEvent`): a sixth of a swipe saved, but AppKit's
routing does more than find the view — it keeps the system's momentum events from a scroll view
that animates its own momentum, so the ruler was moved twice — taken out the same day.

## 6. Keep the look and the motion identical

- **Synthetic swipes are straighter than fingers**: a real two-finger swipe always carries some
  of the other direction, a rest before lifting, and momentum of its own. What only a hand shows
  (the ruler's ticks sliding down out of it, a short swipe running to the end) the user's screen
  recording did: frames with `AVAssetImageGenerator` every 0.05 s, cropped to the part. Record
  with `screencapture -V <s> -R x,y,w,h` to see the island in one's own test (a recording started
  from the island's widget leaves the island's windows out).

- **Screenshots, old and new, same state**: `screencapture -x`, then `image-diff.swift` (a live
  clock or reading changes ~0.1–0.3 % of the pixels; more means a real change).
- **Mid-motion**: screenshot during the scroll or animation (no blank parts, scroller shown) and
  sample a curve at several delays across repeated runs.
- **Where a scroll really is**: `ws/axscroll <pid>` (Accessibility), in any build.
- **One window, no desktop behind it**: `screencapture -x -o -l <window id>` (the ids from
  `CGWindowListCopyWindowInfo` for the owner "NotchIsland") captures the island's or Settings' own
  window with its transparency, so old and new compare exactly whatever is on the screen.
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
