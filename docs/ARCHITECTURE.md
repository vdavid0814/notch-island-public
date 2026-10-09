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

Settings is built once and kept for as long as the app runs, in a window of its own
(`SettingsWindow`) that lies over the island's page area and is ordered in only while Settings is
open: built a few seconds after launch, unseen, on the efficiency cores (sidebar, then one page per
step, then each page drawn once in the window at no opacity). Each page has a view graph of its own
(`SettingsPageDeckView`); the pages not shown are hidden and lay nothing out (`DeferringHostingView`).
The island's SwiftUI only holds an empty anchor (`SettingsSurfaceAnchor`) that puts the window over
its place. The window is cut by the island's lower corners at rest and by the island's moving outline
while Settings closes (`IslandOutlineMotion` hands it the same keyframes). While closed, Settings'
pictures stand still: their clocks and monitors wait (`PanelTimelineView`, `whileShown`), and the
level widgets and header pictures keep their last reading (`PictureReadings`, `SettingsPresence`).
Kept anywhere else it cost the island: in the island's window every resize and key change went over
the hidden pages; moved in and out of a window, every page was laid out again.
A trackpad scroll of a Settings page moves only the clip view's layer while it lasts, and the scroll
view itself once it stops (`ScrollCoalescer`): scrolled by AppKit at every event, every hosting view
in the page was told its place changed and SwiftUI updated the whole page, hover included. The pages
are built whole for it (no lazy grids: `GalleryGrid`, `SwatchGrid`). The ends stretch and spring
back on the layer too, with AppKit's rubber-band curves (measured).

## Browser playback

Commands to the system's Now Playing are checked (`AdapterCommandCheck`): a browser suspends a
background tab that has been paused for a few minutes, and the page then answers no command (play,
toggle, seek, the keyboard's play key — measured with YouTube in Safari). An unanswered command to a
browser is sent again with the browser brought forward for a moment, then the focus goes back to the
app the user was in. Play/pause from the island is always the explicit command, never a toggle. A
next or previous the page did not register falls back to the end (the page's autoplay moves on) or
the start of the video.

## Diagnostics

`notchisland://demo/state` logs the presentation, staged frame, island rect and the
island's measured position (offset from the notch centre). Transitions, stage
frames, banner changes, feature start/stop and permission changes log at
`.notice`, so `log show` finds them.

### Reports to the developer

`Features/Diagnostics/`. Off until the user turns it on in About; bug reports and feature requests
(About's two buttons) work either way.

* **What is read.** `DiagnosticsProbes` (the Mac, the bundle, permissions, Spotlight against the disk,
  the log, crash/hang reports, System Information), `BatteryProbe` (the gauge, the top energy users,
  power assertions), `DiagnosticsAppState` (the island, screens, features, preferences, copies,
  running apps), `DiagnosticsHistory` (launches, versions, runs that did not end with a quit,
  presentations since launch).
* **Energy.** `EnergyMeter` reads `proc_pid_rusage` (energy in nJ, CPU, wakeups, footprint) for the
  app and its helper processes every 10 minutes while diagnostics are on; the report has averages
  since launch, the last hour, on battery and on the charger, the worst 10 minutes and a timeline.
* **The reference.** `docs/diagnostics-baseline.json` holds the developer's Mac's numbers for the
  published version (`Scripts/publish-baseline.sh`, only on a Mac with `ni2.diagnostics.reference`).
  Every copy fetches it from GitHub, with the latest release, and flags a metric past both the
  rule's minimum and its factor times the reference (`DiagnosticsMetric.Rule`; the file's `rules`
  override the defaults without a release). Two 10-minute samples in a row past it send a report at
  once, at most every 6 hours.
* **Sentry and Mixpanel** (`Features/Telemetry/`, both in the EU). `Support/telemetry.json`
  (git-ignored; keys in `Support/telemetry.example.json`) goes into Info.plist (`NITelemetry`) at
  build time; without it no reports are sent. `Telemetry` starts with the About switch (on unless
  the user turned it off; and for one delivery when the user sends by hand with it off), in one of
  two modes:
  * **Standard** (default): nothing of Sentry's runs between reports; each delivery starts the SDK
    without its crash handler, sends (the flow's last steps as breadcrumbs, typed text left out)
    and closes it. Crashes and hangs come from macOS's own records, the crash reporter's `.ips`
    and MetricKit, rebuilt as native events (`NativeCrash`: threads of instruction addresses,
    binaries by UUID and load address) that Sentry symbolicates with the uploaded dSYM. The same
    crash from both goes once (`.ips` first). At rest 0.25 wakeups/s, as before Sentry.
  * **Detailed** (About ▸ Detailed Diagnostics, off by default): the SDK runs with its crash
    handler, App Hang watcher, system breadcrumbs and the flow with what was typed; every report
    is full and goes whole to Sentry (hourly); energy readings every 2 minutes, one reading past
    the reference is an anomaly, problems checked every 15 s.
  * `notchisland://demo/crash` crashes on purpose, only on the developer's Mac
    (`ni2.diagnostics.reference`), to check a crash reaches Sentry symbolicated.
  * **Sentry** (the `sentry-cocoa` SDK, static): crashes from its crash handler, hangs from
    MetricKit's diagnostics, every likely cause (`DiagnosticsVerdict.Check`) as an issue grouped by
    its id, NotchIsland's own error lines grouped by category and wording, macOS's crash and hang
    reports as attachments, the whole report (report.txt, report.json, log.txt) for a report sent
    by hand, a crash, an anomaly or a problem, the user's flow as breadcrumbs with typed text left
    out (`TelemetryMapping.redacted`), and bug reports and requests as user feedback. A cause or
    an error line goes at most once a day per Mac. No tracing, swizzling or automatic breadcrumbs;
    the SDK's crash handler and App Hang watcher only in detailed mode (together 0.25 → 3.7 wakeups/s
    at rest).
  * **Mixpanel** (`MixpanelClient`, no SDK): "App Launched", "Update Installed", and per report a
    "Health Snapshot" (the metrics, each feature's state, the verdict's counts; no paths, nothing
    typed). Events wait in `Application Support/NotchIsland/Mixpanel/queue.json` and go with the
    report cycle (`/track`, `ip=0`), so no timer of its own.
  * Release builds write `build/NotchIsland.app.dSYM`; with `sentry-cli` and `SENTRY_AUTH_TOKEN`
    it is uploaded so Sentry symbolicates crashes.
* **Discord** (bug reports and requests, besides Sentry). `Scripts/discord-setup.py` builds the
  forums and writes `Support/diagnostics-webhooks.json`, which `Scripts/build.sh` puts in Info.plist
  (`NIDiagnosticsConfig`); bugs and requests get a post in their forum with a pointer in the Mac's
  post. A failed delivery waits in the outbox. Automatic reports no longer go there.
