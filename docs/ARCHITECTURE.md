# Architecture

## Targets

| Target | What |
|---|---|
| `NotchIsland` (executable) | one line: `NotchIslandApp.main()` |
| `NotchIslandKit` (library) | everything else |
| `NotchIslandKitTests` | Swift Testing suites for every pure piece |

Swift 6 language mode with `defaultIsolation(MainActor)`: everything is on the main
actor unless it says `nonisolated`. Pure value types and the logic worth testing
(resolver, layout, stage geometry, power announcer, level stepper, media-key
decoding, adapter protocol parsing, timer state machine…) are `nonisolated` and
`Sendable`. C callbacks (event tap, CoreAudio, IOKit, DisplayServices) run off the
main actor and hop back explicitly.

## Layers

```
App/            NotchIslandApp (MenuBarExtra scene), AppDelegate, AppModel (composition root),
                AppCommand (URL parser), DemoDirector, FeaturePlan (preference → feature diff)
Island/         the island's brain
  IslandPresentation   idle | compact(activity) | banner(kind) | expanded(page) — KIND only, never data
  IslandResolver       pure: inputs → presentation (priority: expanded > drag > banner > timer > stopwatch > music)
  IslandLayout         pure: sizes, radii per presentation (compact/banner hug the notch, expanded scales)
  IslandModel          presentation, page, pin, hover; apply() brackets willTransition/didTransition
  BannerCenter         the one transient banner, deadlines, hold, pre-empting vs non-pre-empting posts
  IslandController     policy: hover dwell, close grace, never-visited timeout, drag & drop, banner hold
  Window/              IslandPanel (the stage), IslandHostingView (hit test, hover, drops),
                       IslandWindowController (staging, re-anchoring, suspension), StageGeometry,
                       NotchMetrics, PointerMonitor
DesignSystem/   IslandGlass (the material), IslandGlassButtonStyle, IslandLiquidSegment,
                IslandShape, Metrics, Motion
Views/          IslandRootView + Compact/, Banner/, Expanded/, Components/
Features/       Media/, Levels/, Power/, Shelf/, Timers/ — each an @Observable store + services
System/         Permissions, SystemActivity, Haptics, LaunchAtLogin, Log
Settings/       Preferences (UserDefaults, "ni2." keys), SettingsWindowController, SettingsView
```

Data flows one way: services push into feature stores; `IslandController` observes
the stores it needs (re-arming `withObservationTracking`), resolves the next
presentation and calls `IslandModel.apply`; the views read the stores directly.
Because the presentation carries only the *kind* of content, a volume step or a
track change never re-stages the window or restarts a spring.

## The window

The panel is a borderless, non-activating `NSPanel` one level above the menu bar,
on all Spaces and over full-screen apps, never key, transparent, no shadow.

Its frame is a **stage** owned by `IslandWindowController`:

* at rest and idle it is exactly the notch rectangle — nothing of ours covers a
  menu-bar item;
* before a transition it grows to cover both ends plus a margin for spring
  overshoot, `Motion.settleDuration` later it shrinks to the resting frame;
* `IslandPanel.stage(_:)` is the only way to move it: it sets the frame without
  displaying, lays SwiftUI out for the new size, then displays — so the new size
  is a non-animated update of its own, ahead of the animated state change.

Two rules came out of a live crash and are load-bearing:

1. The `NSHostingView` is **not** the panel's content view. As the content view of
   a non-resizable window it resized the window to its SwiftUI content on every
   animation frame (even with `sizingOptions = []`), which moved the window during
   AppKit's constraint passes until AppKit threw. A plain `NSView` is the content
   view and the hosting view fills it; the panel refuses any frame it did not stage.
2. Pointer state is never reported synchronously from inside a frame or rect
   change; it is re-evaluated on the next main-actor turn, coalesced.

Hit testing is scoped to the island rect (the union of both ends while a
transition runs). At idle an almost-transparent fill (alpha > 0) under the notch
lets the window server deliver hover.

## Glass

One material, defined in `IslandGlass`, taken from the CAD app: smoked clear glass
(`.clear.tint(.black.opacity(0.5))`), `.interactive()` under controls, accent-tinted
for active controls, fully clear for the sliding selection thumb. The panel is
pinned to `darkAqua`. The glass exists only while something is visible and extends
above the window top (clipped) so its top edge never draws a rim against the bezel.

The island is drawn on a canvas the size of its window, which changes only when the
window is re-staged. A transition animates the drawn outline (`IslandSurface`, an
animatable modifier that is also the insertion/removal transition), never a frame, and
the content inside keeps its size and place, so a morph neither re-lays it out nor
re-renders it. The surface glass is the island's body as a system rounded rectangle
(`IslandGlassBody`): Liquid Glass draws that analytically, while any other path is
rasterised again for every size (~100 MB of window-server textures per open). The two
small concave shoulders beside it are filled with the glass's smoke, and the outline
clip around the container gives the exact silhouette.

## Energy

Every signal is pushed by the system; there are no repeating timers. One-shot
deadlines (banner expiry, hover dwell, timer completion) are cancellable tasks
owned by exactly one object each. The equaliser is four `CABasicAnimation`s on the
render server, and so is the Now Playing progress line (`PlayedLine`, one linear
animation at 2 fps); the running times tick once a second, only while on screen.
Island springs end once they are visually settled (`LeanSpring`), and state set as a
view appears inside an open never rides its spring (`withoutAnimation`). Settings'
looping animation picture is Core Animation, and the widget studio's live preview has
a view graph of its own (`IsolatedHosting`), so neither updates all of Settings.

## Diagnostics

`notchisland://demo/state` logs the presentation, staged frame, island rect and the
island's measured position (offset from the notch centre). Transitions, stage
frames, banner changes, feature start/stop and permission changes log at
`.notice`, so `log show` finds them.
