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
