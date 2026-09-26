# Performance tools and glass experiments

| File | What |
|---|---|
| `bench.py <label> <seconds> [full\|opens\|settings\|idle]` | Drives the island through `notchisland://` URLs and samples CPU %, GPU %, footprint and Energy Impact (top's POWER) every second. `NI_APP` picks the app bundle. |
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
