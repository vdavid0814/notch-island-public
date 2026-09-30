# Performance tools and glass experiments

| File | What |
|---|---|
| `bench.py <label> <seconds> [full\|opens\|settings\|idle]` | Drives the island through `notchisland://` URLs and samples CPU %, GPU %, footprint and Energy Impact (top's POWER) every second. `NI_APP` picks the app bundle. |
| `ab.py <out.tsv> <label=app> … -- [scenario …]` | Back-to-back comparison of builds with `anim.py` (A B A B …), one row per scenario and round, then the medians. Refuses a build that still sends diagnostics. |
| `per_event.py <label>.json` | CPU ms, peak % and peak energy per event type of a `bench.py` run. |
| `states.py <label> [seconds]` | Steady-state cost of each island state (rest, panels, Siri, Settings pages). |
| `cpu.py <pid> <seconds>` | CPU % and footprint of any process over a window. |
| `hot.py`, `tree.py` | Summaries of a `sample` report's main thread. |
| `glass-freeze-test.swift` | Glass experiments over a checkerboard: `freeze` (a Core Animation resize stopped halfway), `static` (the reference), `mask` (full-size glass under an animated mask), `swiftui` (SwiftUI's glass), `full`/`hybrid`/`hybridIn` (island-like content inside SwiftUI glass, above an AppKit glass, inside an AppKit glass). |
| `glass-drive-test.swift` | An AppKit glass resized every frame by our own display link along SwiftUI's spring, with SwiftUI content kept still. |
| `image-diff.swift` | Pixel difference of two screenshots. |
| `night.py cycle\|rest\|only <label> …` | The overnight soak: every animation and opening (panels, hover, Siri and its galleries, level/battery/AirPods/timer/drop banners, a track change, every Settings page, music paused and playing), sampled four times a second, then a rest reported per minute to catch leaks. Rows in `night/` (not committed). |

Findings (September 2026, macOS 27, MacBook Air M5):
- SwiftUI's `.glassEffect(.clear.tint(.black.opacity(0.62)))` and `NSGlassEffectView(.clear, tint)` render identically (0 pixel difference).
- Content as the AppKit glass's `contentView` renders as inside SwiftUI's glass (no pixel over 8/255 apart); as a sibling above it, 0.78 % of pixels differ.
- A Core Animation resize of `NSGlassEffectView` does not redraw the glass at in-between sizes (its inner layers stay at the final size); a full-size glass under an animated mask differs from the true in-between glass in 2.3 % of pixels (edge light and tint).
- Resizing `NSGlassEffectView` every frame runs its own internal SwiftUI update (`View.materialEffect`): ~120 ms of CPU per 0.4 s transition, about a third of today's per-frame cost, while the fixed ~165 ms per transition stays.

## Frame-by-frame comparison (`frames/`)

`notchisland://demo/freeze?t=<seconds>` holds every island spring that many seconds after its start (`demo/freeze` alone lets them run again; the stage stays large meanwhile), so a single frame of a transition can be screenshotted.

| File | What |
|---|---|
| `frames/backdrop.swift` | A still checkerboard over the top of the screen, just under the island, so screenshots compare exactly. |
| `frames/pixels.swift` | `stats`, `heat`, `top`, `cut`: difference of two screenshots, a heat map, the most different pixels, a zoomed crop. |
| `frames/ab.py` | Freezes a transition at given times and screenshots it (edit the `demo/…` switch it toggles for whatever two variants are compared). |

Build the tools with `swiftc -O backdrop.swift -o backdrop` and `swiftc -O pixels.swift -o pixels`.

Findings (September 2026), the AppKit glass surface (`NSGlassEffectView` under the SwiftUI island, its outline still animated by SwiftUI):
- It can match SwiftUI's glass within 2/255, but only if the content still sits in a SwiftUI glass effect of the same material (in an empty shape: SwiftUI resolves system colours by the glass behind them) and the AppKit glass is rounded at every corner and reaches far above the screen edge (square top corners via `cornerConfiguration` bend light differently along the bottom edge, up to 79/255).
- The glass buttons' rim light stays brighter on SwiftUI's glass (up to ~40/255): inside the island's clipped glass container they are lit as if the island's glass were not behind them. Content as the AppKit glass's `contentView`, a portal layer, and the AppKit glass inside the clipped container all left it at the darker value.
- It cost more, not less: 273 ms of CPU per open and 290 ms per close, against 228–269 and 232–258 ms with SwiftUI's glass, Energy Impact peaks ~20 against ~16.
- Where an open's ~220 ms go (ablations): building and first drawing the page 60–90 ms, the island's motion and glass ~70 ms, the content's work during the motion (the glass container re-resolving every glass control each frame) ~40 ms, URL handling and staging 15–25 ms. Switching off the glass shape's change, the reveal fade and blur, or the outline clip changed nothing measurable; no single SwiftUI update is more than ~4 % of an open.

## Overnight soak (September 26, 2026, release build, `night.py`)

Where the memory went, and what took it back (footprint = Activity Monitor's Memory column):

| | before | after |
|---|---|---|
| At rest (fresh launch, music playing) | 26–28 MB | 19–20 MB |
| At rest after a tour of Settings | 82–91 MB | 42–46 MB |
| Volume / brightness banner (peak) | 72 MB, 122 after Settings | 21–30 MB |
| AirPods / timer-done banner (peak) | 73–94 MB | 31–32 MB |
| Opening Settings (peak) | 158–197 MB | 74–77 MB |
| Settings ▸ General open | 95 MB | 53–57 MB |
| Siri's app gallery (peak) | 60 MB | 42–43 MB |
| At rest with music: CPU / Energy Impact | 1.0–1.25 % / 1.7 | 0.9–1.0 % / 1.3–1.4 |

- **RenderBox's Metal context (~40 MB).** SwiftUI draws symbol effects (`.symbolEffect`,
  `.contentTransition(.symbolEffect(.replace))`) and the Liquid Glass knobs of native controls
  (Slider, Toggle, pickers) with its own renderer, which on the GPU set up ~40 MB of graphics
  memory ("Owned physical footprint (unmapped) (graphics)") for a second or two each time. An
  `NSImageView` with AppKit's symbol effects did the same. `RB_DISABLE_GPU=1` has it draw on the
  CPU: screenshots of every Settings page, the banners and the pressed slider match, the CPU for
  those moments is the same or lower. Set in `LSEnvironment` and by `main.swift`.
- **The allocator.** `malloc_zone_pressure_relief` released nothing on macOS 27 (xzone malloc);
  after Settings ~28 MB of the small-allocation pages were free but dirty. `MallocSpaceEfficient=1`
  returns them: everything above is measured with it. `MallocAggressiveMadvise`,
  `MallocXzoneDeferSmall` and `MallocSecureAllocator=0` changed nothing measurable.
- **Wallpapers in Settings.** Core Animation copied every ImageIO/AVFoundation image it showed
  into its own sRGB copy (~9 MB per wallpaper, "CoreAnimation" category), even from Display P3:
  pictures are now converted by vImage to 8-bit BGRA sRGB once. The 150 pt pictures of each
  setting use a 960 px copy (480 px drew the thin lines visibly softer), the picker's swatches
  160 px. Core Graphics' image cache keeps the bytes of any image it has drawn — ImageIO's own
  thumbnails draw — so one ~9 MB decode may stay behind in the purgeable zone (not counted).
  Decoding with `CGImageSourceCreateImageAtIndex` and scaling in vImage instead left 34–63 MB of
  large allocations behind: reverted.
- **Freed large blocks** show as "Malloc Large (empty)" dirty in `vmmap` but as reclaimable in
  `footprint`: they are not in the app's footprint.
- **The spectrum tap** ran its aggregate device at 512 frames (four I/O cycles per analysis at
  48 kHz); its buffer is now one analysis hop (2048 at 48 kHz): half the wake-ups.
- No leaks: every 5- and 10-minute rest held its footprint flat to 0.1 MB (a new track's cover
  adds ~2 MB once).
- Energy Impact peaks over the whole soak: opening the panel 27–30, Siri's app gallery 40–47
  (the icons' colour conversion), Settings 30–35; nothing near 60.

## Where the energy goes (September 27, 2026, battery, coalition energy)

- **Performance cores.** Energy is ~0.9 mJ per ms of main-thread work on a performance core and
  ~0.15–0.2 on an efficiency core. A main-thread burst of up to ~20 ms stays on the efficiency
  cores; 80 ms in one turn costs 42 mJ, 160 ms 253 mJ. The same 80 ms in sixteen 5 ms pieces
  16 ms apart cost 8 mJ. At background quality of service a 100 ms burst cost 12 mJ instead of 72
  (utility changed nothing). `MainThrift` (System/Thrifty.swift) uses that for updates nobody waits
  on within the frame; a dispatch job's end restores the thread's quality of service, so it
  sets it from a run-loop block (`lowPower`).
- **Below ~30 % battery** the system kept NotchIsland (and v0.4.2 alike) entirely on the
  efficiency cores: no performance-core time at all, everything 3–5× slower (a Settings page
  ~1 s). Compare builds only back to back, in the same state.
- **While the session is locked** the app is suspended (island ordered out) and, with the
  display asleep, nothing is rendered: measurements then mean little, screenshots are black.
- **Wins:** the closed panel kept 10 s (fast re-opens, spam-open 74 → 19), the fade glass parked
  instead of switched off (~20 ms per close), the panel and Settings resting on their transition
  frame, Siri's first opening read ahead (130 → 57), Settings' pages built unseen during the growth
  at background quality of service (General 156 → 65).
- **Tried and dropped:** keeping Settings' pages alive between visits (+77 MB, no gain: the cost is
  laying them out and drawing them in the window, not building their graph); building a form one
  section per frame (more work in total); GPU rendering (`RB_DISABLE_GPU=0`, ~15 % less on
  Settings for +40–60 MB); moving the hidden panel off screen (lazy stacks rebuilt at each open);
  switching its hit testing or accessibility (~15 ms per open each); the whole process at
  background policy (`taskpolicy -b`, 7× the CPU).
- `NI_TRACE=1` logs main run-loop turns over 2 ms (`TURN`) and URL commands (`MARK`) in the window
  category.

## The night of September 29, 2026 (v0.4.9 → next, MacBook Air M5, on the charger)

New tools: `levels_bench.py` (volume changes made elsewhere: the island's cover or the liquid card),
`events_bench.py` (every demo event on its own: CPU ms, Energy Impact peak, MB), `report_bench.py`
(one diagnostics report) — and `coalition.py` for anything that starts processes.

| | before | after |
|---|---|---|
| Liquid card, per volume change (CPU / EI peak) | 1474 ms / 72 | 51 ms / 3 |
| Diagnostics report with its tools (coalition) | ~21 J | hourly: ~0.02 J (light); full every 6 h |
| AirPods card (EI peak) | 33 | 20 |
| At rest (coalition) | — | 0.02–0.04 mW, no wakeups |

- **The liquid card** drew its blur-and-threshold `Canvas` on the CPU every frame (RenderBox runs on
  the CPU here, `RB_DISABLE_GPU`). Its outline is now a smooth minimum of signed distances traced by
  marching squares for every 1/120 s of a move (~1.5 ms a frame in release), played as a Core
  Animation keyframe path, and worked out ahead at background priority (after launch, when full
  screen changes, once the card came up somewhere new).
- **Watching macOS's card**: one window-list read is 0.5 ms, but at 20 ms it was a third of the main
  thread's work per change: off the main thread now, every 25 ms for the first 0.6 s, 60 ms after.
- **Diagnostics**: `log show` is the expensive part (6 h: 1.8 s of CPU plus logd's work billed to the
  app), then `top -l 2` (0.35 s). Reading even the process's own log through `OSLogStore`
  (`.currentProcessIdentifier`) waits ~1.3 s on logd, billed to the app: the light report has no log.
- Timer page at rest 0.01 % (a 1 % reading earlier was one sample); panel with media playing 0.58 %.
- **A full report** (by hand, 6 h of log): 19.6 J with a coalition Energy Impact peak of 99.5 → 3.1 J,
  peak 42. Its tools run at background priority (efficiency cores, ~4× less energy) and `log show` and
  `system_profiler` are paused and resumed so they take 40 % of a core (`DiagnosticsProbes.Throttle`);
  `top -l 2` (a whole core for a second) is replaced by reading every process's counters in-process;
  the event trail comes from the report's own `log show` instead of `OSLogStore`. Automatic reports read
  the log only back to the previous full report (20 minutes of it: 0.5 s of CPU instead of 2.7 s).
- **Siri's app gallery**: thumbnails drawn in Core Animation's BGRA layout: Energy Impact peak 33 → 23.
- **Rounds a–d**: every scenario under 40, memory flat in every rest (64–69 MB after Settings, 28 MB idle).

## The energy campaign of September 29, 2026 (v0.5 → next)

The before/after tables, what changed and what was left out are in `docs/ENERGY-LOG.md` (it also
ships inside the app). Points for these tools:
- **Activity Monitor's Energy Impact is the coalition's mW**, not `top`'s POWER: opening Settings
  read 245 on screen while POWER peaked at 54. `anim.py`'s worst 1 s / 5 s windows are the number.
- **Energy follows the performance cores' clock**: opening Settings took ~3 mJ per ms of CPU
  (RenderBox drawing shadows with distance filters, blurs and gradients at 16 bits per channel on
  user-interactive threads). An 8-bit island window and the first 0.7 s on the efficiency cores
  took it from ~2.4 J to ~1.4 J.
- Test builds keep their Discord destinations: a launch that lasts 90 s sends a diagnostics report.
  Strip `NIDiagnosticsConfig` from a measuring copy's Info.plist and sign it again.
- A test run can hang loading its bundle (system policy) in the shared `.build`: `Scripts/test.sh
  --scratch-path <elsewhere>` runs.

## v0.6 (September 30, 2026)

Tables and changes in `docs/ENERGY-LOG.md`. Points for these tools:
- **The order of the scenarios changes the numbers**: the first opening of the panel or Siri after a
  launch costs a third more than later ones, and spam-open measured 27 when run first and 38 after
  the other scenarios. `ab.py` keeps the order fixed, so compare only runs with the same list.
- **Energy can rise with the same CPU time**: spam-open's 33 → 38 came with 1120 → 1126 ms. Look for
  work moved to the render server or bunched into shorter, faster bursts, not only for more CPU.
- **Undo one change at a time**: a copy of the tree with one file put back, built in release (about
  40 s incrementally with a cloned `.build`), its binary swapped into a signed copy of the app and
  measured back to back. That is how the glow and the widget corners were cleared.
