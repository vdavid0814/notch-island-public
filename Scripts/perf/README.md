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
