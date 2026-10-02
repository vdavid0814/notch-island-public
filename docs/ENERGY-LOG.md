# NotchIsland energy log

Reference numbers for how much CPU, GPU and battery NotchIsland takes, per animation and at rest.
Every copy carries this file (the repository, the `.dmg` and `NotchIsland.app/Contents/Resources/`), so any
later version can be measured the same way and compared with it.

## 2026-10-02 (night): scrolling Settings ▸ Widgets

Scrolling the widget gallery with the trackpad showed an Energy Impact of 1300–1500 in Activity
Monitor, and the frame rate dropped. On the charger, release builds, the same synthetic trackpad
scroll (down and up, 1440 pt/s, `ws/smooth`), read in Activity Monitor's Energy tab while it ran
and measured by `coalition.py`:

| scrolling Settings ▸ Widgets | before | now |
|---|---|---|
| Activity Monitor, Energy Impact | 1360–1460 | **25–30** |
| the app's CPU (coalition) | 41–45 % | **7–9 %** |
| SwiftUI updating the page | at every frame of the scroll | once, when it stops |

- **Where it went**: every scroll step moved each hosting view in the page (the page's own, and one
  per gallery preview); SwiftUI then invalidated each of them (`geometryInWindowDidChange`), updated
  the page, hit-tested hover twice through every card and rebuilt its responders. That is not
  something a view can opt out of.
- **Now** a trackpad scroll moves only the clip view's layer (drawn by the window server) and the
  scroller's knob; the scroll view is scrolled to where the page is once the scroll and its momentum
  stop (`ScrollCoalescer`), or at once on a click or a key. Events go straight to the scroll view
  under the pointer. Every page is built whole for it: the gallery's and two other lazy grids became
  non-lazy layouts (`GalleryGrid`, `SwatchGrid`; screenshots identical). A scroll that runs into the
  top or the bottom is handed to AppKit there, so the rubber band is AppKit's own. Wheel (line)
  scrolling and `List`s are left to AppKit.
- The same holds for every Settings page; Settings ▸ About while scrolling went from 27 % to 6 %.

## 2026-10-02 (evening): Settings without the keyboard handover, a quieter rest

On the charger, release builds, `anim.py` back to back (before = v0.7.2 (26), after = this build):

| scenario | before | morning build | now |
|---|---|---|---|
| opening Settings, first time after launch (worst 5 s) | 134–157 | 54 | **20–24** |
| opening Settings again | 39–54 | 38–39 | **13–19** |
| Settings tour (every page twice) | 504–517 | 39–41 | **15–23** |
| at rest: the app's wake-ups a second | ~1 | ~0.6–1 | **~0** |

- **Settings' window no longer takes the keyboard when it opens**: it takes it with the first click
  in it (a click is handled as in a key window). Becoming key had every control of the shown page
  and the sidebar take the key state, and give it back at the close: four fifths of an opening's
  CPU energy (170 → 31 mJ, measured). The island keeps the keyboard meanwhile, so Esc still closes.
- **The clipboard history** looks at the pasteboard every five seconds once nothing has been typed or
  clicked for a minute (once a second otherwise): at rest it was the app's only wake-up.
- **Looked into and left**: scrolling Settings ▸ Widgets costs ~10 % of the main thread while it
  scrolls, about half of it the gallery's cards (not their previews), the rest SwiftUI's own work
  for a scrolled page (hover hit-testing, transforms). An AppKit scroll view around the page, a
  grid that is not lazy, AppKit hover tracking and responsive scrolling were each tried and cost
  more. Siri's first opening starts Safari's AutoFill helper (~50 mJ, once per launch) for its text
  field; setting no content type on the field and its field editor did not stop it.

## 2026-10-02: Settings kept, Siri read ahead (after v0.7.2, build 26)

**Why.** Settings cost an Energy Impact of 400–600 at every opening and page change (Activity
Monitor), its frame rate dropped while it was built, and the widget gallery's pictures arrived one
by one for up to two seconds. Siri's first opening and first search after a launch went past 80 too.
The target: nothing in Settings or Siri near 80, nothing else costlier, the look and the motion the
same.

**Machine and method.** The same MacBook Air M5, macOS 27, on battery (~75 → 60 %). Release builds of
v0.7.2 (26) ("before") and this work ("after"), signed alike, report destinations removed.
`Scripts/perf/ab.py` (`anim.py`, which now also counts GPU energy and the energy other processes bill
to the app, as Activity Monitor does): before and after alternating, two rounds, a fresh launch and
35 s of rest before each. `Scripts/perf/ws/ws_bench.py` for the window server, with a real pointer.

The build running on this Mac before was a **debug** build (`Scripts/run.sh` built debug): in
Settings it takes about three times the CPU of a release build. `Scripts/run.sh` builds release now.

Activity Monitor's Energy Impact (the app's coalition, worst 5 s), and the app's CPU ms; medians of
two rounds (siri and settings-tour: the first and the second time after a launch):

| scenario | before | after | change | CPU ms before → after |
|---|---|---|---|---|
| Settings tour, first after launch (every page twice, closed) | 591 | 41 | **−93 %** | 2350 → 877 |
| Settings tour, again | 401 | 41 | **−90 %** | 1984 → 843 |
| Siri, first opening after launch | 79 | 71 | −10 % | 313 → 305 |
| Siri, again | 9 | 10 | | 146 → 153 |
| Siri, typing a word, first time after launch | 377 | 286 | **−24 %** | 516 → 426 |
| Siri's app gallery | 37.5 | 41.0 | +9 % | 420 → 408 |
| opening the panel | 13.1 | 15.4 | +18 % | 157 → 173 |
| hover open | 10.2 | 11.8 | +16 % | 155 → 166 |
| spam-open (10 × 0.25 s) | 27.9 | 30.4 | +9 % | 576 → 610 |
| spam-pages (12 page switches in 5 s) | 47.0 | 75.2 | **+60 %** (the new slide) | 960 → 1488 |
| volume (3 changes) | 6.7 | 7.5 | +12 % | 216 → 284 |
| AirPods | 3.2 | 5.8 | (noise: 4.8 → 4.0 in another run) | 108 → 114 |
| battery (charger in and out) | 2.8 | 3.0 | | 98 → 106 |
| timer done | 9.8 | 11.6 | +18 % | 368 → 446 |

(The final build, two rounds, battery 50 %. Typing a word again after the first time: ~65.)

The window server, with a real pointer (`ws_bench.py`, one round each): a Settings tour 3.6 → 1.4 J
(the app 6.6 → 1.2 J, its peak 1039 → 115 mW); Settings ▸ General left open 10–17 → 3–8 mW; ten
hover opens 1.95 → 2.00 J; at rest 2.0 → 2.4 mW (the app 0.01 → 0.04 mW). Memory: 40–50 MB → ~160 MB
with Settings kept.

### What changed

**Settings: built once, kept, in a window of its own**
- Settings' pages were built and laid out from nothing at every opening and every change of page
  (~1.2 s of main thread on the performance cores, almost all of it SwiftUI layout). They are now
  built once, a few seconds after launch, unseen, on the efficiency cores — the sidebar, then one
  page per step, then each page drawn once in its window at no opacity — and kept for as long as the
  app runs (~110 MB more memory, as asked: "load everything into RAM").
- Each page is a view graph of its own (`SettingsPageDeckView`); a page change hides one and shows
  another; hidden pages lay nothing out (`DeferringHostingView`). A page shown again starts at its
  top with nothing picked, as a new one did.
- They live in their own window (`SettingsWindow`) over the island's page area, ordered in only
  while Settings is open. Tried first and dropped: kept inside the island's window, every resize of
  that window (each open, close and Siri step) and every key change went over the hidden pages and
  their native controls (Siri's opening cost five times its main thread); moved out of the island
  and back, every page was laid out again (~1 s, more than building them).
- The window is cut by the island's lower corners at rest (a mask layer there cost the window server
  ~10 mW while General was open) and by the island's moving outline while Settings closes, frame for
  frame (`IslandOutlineMotion` hands it the same keyframes).
- While closed, Settings stands still: its pictures' clocks and monitors wait (`PanelTimelineView`,
  `whileShown`), the level widgets and the header's picture keep their last reading
  (`PictureReadings`, `SettingsPresence`), the Activities page reads only whether there is a battery,
  and the gallery's previews and the studio's island are taken out of the window (a timer finishing
  15.3 → 11.5, the charger 4.0 → 2.9).
- **Frames**: the longest main-thread turns while Settings opens and changes pages (`NI_TRACE=1`)
  went from 245–410 ms (the pages built) to ≤ 70 ms: Settings' window comes on screen, invisible,
  and takes the keyboard while the island grows (on the render server), so the turn in which the
  pages fade in is ~45 ms instead of ~210; a page switch writes no environment over the pages any
  more (50–80 → 30–60 ms, most of it the URL command's own handling in the test).
- The widget gallery's previews come one a frame as their cards appear (`GalleryPreviewQueue`)
  instead of 60 ms plus 35 ms per place in the gallery (up to two seconds for the cards further down).
- `MenuBarExtra(isInserted:)` set its binding again (unchanged) at every activation of the app (each
  Siri and Settings opening and closing); each write went to the user defaults and woke every
  `@AppStorage` view. It is written only when it changes.

**Siri**
- The lists a typed word searches (shortcuts, System Settings panes, emoji, bookmarks) are read ahead
  after launch and kept half an hour after a close (they went ten seconds after it and were read
  again at the next word); the system's search services get their first query then too; Siri's view
  is drawn once unseen (`AssistantRehearsal`).
- A keystroke's search and the lists run at utility priority (efficiency cores); the apps on disk are
  read once a minute instead of at every keystroke; the app list is kept 30 minutes instead of 10.

**The panel's pages** (asked for: a nicer switch)
- The new page slides in a short way from its side of the header's order as it fades in, the page
  left fades out where it is; no blur. Moving a page costs SwiftUI a redraw per frame, glass and all,
  so only the arriving page moves (both moving cost half again as much).

### Not met, or costlier
- **Typing in Siri the first time after a launch** stays far above 80 (272): most of it is energy
  other processes bill to the app (~1 J, against 0.13 J the second time) — the window server drawing
  the list the first time, Spotlight, the privacy daemon. The searches' own share went down; warming
  the services ahead did not move the billed part.
- **Siri's first opening after a launch** is just under 80 (68–79 across runs); later openings ~9.
- **Page switches** cost more with the slide (12 switches in 5 s: 50 → 93); a single switch is about
  +30 ms of main thread. Kept pages, a cheaper curve and moving only the arriving page were tried;
  moving anything over glass costs a SwiftUI redraw per frame.
- **Banners while Settings is kept**: a timer finishing (+80 ms) and a volume change (+50 ms) still
  cost a little more than before. What was found is stopped while Settings is closed: the levels,
  the header picture, the battery, the clocks, and the widget gallery's previews and the studio's
  island, which leave the window (`DeferringHostingView.pausesWithSettings`) and come back as
  Settings grows.

### Tests
`Scripts/test.sh`: 887 tests; the timing tests that fail under load (banner expiry, Siri's return
after typing) pass alone. `thePagesFadeInOnTheRenderServer` looks for the pages in Settings' window now.

## 2026-10-01: v0.7.1 (build 25): the window server's share

**Why.** A comparison with Boring Notch (2.7.3) on September 30 counted the window server too: at rest
NotchIsland was ahead, but opening the island and touring Settings cost more in total, because the
window server worked far harder for NotchIsland than NotchIsland itself (Settings: the app 4.8 J, the
window server ~245 mW). This round looked only at that side.

**Machine and method.** The same MacBook Air M5, macOS 27, on battery (100 → ~75 %), Music playing.
Release builds of v0.7 (24) ("before") and v0.7.1 (25) ("after"), signed alike, report
destinations removed. `Scripts/perf/ws/ws_bench.py`: a real pointer (hover onto the notch, clicks on
Settings' gear and sidebar, line scrolls), the coalitions of NotchIsland, WindowServer and coreaudiod
sampled every second, the Claude window hidden. Two rounds, before and after alternating, fresh
launch and 45 s of rest before each.

| scenario (as in the Boring Notch comparison) | before | after | change |
|---|---|---|---|
| Rest with music, 120 s: window server | 16.4 mW | 14.2 mW | −13 % (−18 % in a later 90 s A/B: 17.7 → 14.5) |
| Rest with music: the app itself | 0.07 mW | 0.10 mW | (noise; a 4 mW second at a track change) |
| 10 opens and closes (66 s): window server | 7.8 J (106 mW) | 4.4 J (60 mW) | **−44 %** |
| 10 opens and closes: the app | 0.46 J | 0.56 J | +0.10 J |
| Settings tour (60 s, 10 page visits): window server | 13.1 J (218 mW) | 4.3 J (71 mW) | **−68 %** |
| Settings tour: the app | 7.2 J | 6.7 J | −7 % |
| Settings ▸ General open, at rest: window server | 785 mW | 23 mW | **−97 %** |
| Panel open on a playing track, at rest: window server | 30–80 mW | ~15 mW | −50…−80 % |

Without NotchIsland the window server took 2–3 mW here; with the island at rest and music paused, the
same. Everything above that is the island's.

### What changed

- **General's animation picture** (Animation length) looped as one infinite Core Animation group:
  the window server drew 60 frames a second for as long as General was open — through the picture's
  pauses (58 % of each cycle) and while it was scrolled out of sight (it is at the foot of the page,
  so nearly always). Each spring is now added just before it starts, and only while the picture is
  in view; between springs nothing is attached and no frame is drawn. Same springs, same timing.
- **Settings' halo.** The island's legibility halo (a 0.18 shadow meant for content over glass) also
  wrapped Settings, whose surface is solid: the halo's shadow pass spanned the whole near-screen page,
  so every frame of any animation in Settings re-rendered and blurred all of it. Settings no longer
  gets it (the surface's black style did not reach its content through the surface transition).
- **Settings' ground and panels are a plain material** (asked for): no behind-window blur under the
  page, and the sidebar and the Customize editor's outline and inspector panes no longer Liquid Glass
  — the same greys, measured on screen and matched within 1–3/255, edged like Settings' cards. The
  segmented bars, buttons and the island's glass are unchanged, as is the black-to-grey fade.
- **The played line** (Now Playing's progress) was a linear animation with a 2 fps frame-rate hint:
  the window server drew it far more often (~200 wake-ups a second while the panel was open on a
  playing track). It now steps twice a second as discrete keyframes, as the hint meant.
- **The fade style's black** is drawn once into a picture of its own (`drawingGroup`) instead of a
  live blur filter the window server ran again in every frame the island moved or anything on it
  changed — at rest with music, every frame of the bars (frozen-frame screenshots: within 4/255).
  At rest with music the window server went 17.7 → 14.5 mW with it, 17.5 without it (two rounds
  each). The picture is drawn by the app on the CPU, once per surface: Activity Monitor's worst 5 s
  for the app rises a little on a volume banner (4.5 → 7.7) and an open (8.5 → 12), while the
  window server saves more (a volume banner: app +9 mJ, window server −17 mJ). A surface that
  SwiftUI sizes frame by frame, and Siri's (which settles at many sizes), keep the live filter.
- Settings' rows keep their measurements in the layout cache (a row measured its native controls
  eight times per layout pass); Login Items' status is read at background priority.

### Tried and left out
- **One halo for the whole panel** (`compositingGroup` before the shadow) instead of one shadow per
  text and shape: −37 % of an open's window-server energy, but halos over the cards came out up to
  29/255 darker. The per-layer halo is the look: kept.
- **Bars' frame rates on one grid** (breathing at 15 fps under the 30 fps beat): no measurable change.
  At rest with music the window server's ~12 mW is the bars' frames themselves (a plain test window
  with the same bars costs the same per frame); fewer of them would change how they move.
- Leaving the glass container, the outline clip or the pill's invisible shadow out: no measurable
  change at rest.

### Tests
`Scripts/test.sh`: 875 tests; the timing tests that fail under load (banner expiry, Siri's return
after typing, the icon cache's daily tidy) pass alone; the `analogClock-1x1` snapshot fails the same
way without these changes.

## 2026-09-30: v0.6 (build 23): the new features, and the next energy round

**Machine:** the same MacBook Air M5 (Mac17,3), macOS 27, on battery the whole time (57 % for the
middle pass, 39 → 38 % for the final one: both above 30 %, the same core scheduling). Music
playing. Release builds signed with the same identity, report destinations removed.

**Builds compared:** "v0.5.1" = v0.5.1 (22) as released plus the uncommitted liquid-card lead
(`airPodsMode` 0.20); "v0.6" = this release. Every number is the median of two rounds run back to
back, v0.5.1 and v0.6 alternating, with the same scenario list (`Scripts/perf/ab.py`).

### Result in short

Activity Monitor's Energy Impact (coalition mW, worst 5 s window), and the app's CPU ms:

| scenario | v0.5.1 | v0.6 | change | CPU ms v0.5.1 → v0.6 |
|---|---|---|---|---|
| settings (General, then Widgets, close) | 500.8 | 424.9 | −15 % | 1460 → 1328 |
| siri-apps (Siri's app gallery) | 48.3 | 40.7 | −16 % | 542 → 524 |
| spam-pages (home → timer → shelf, 4 rounds) | 53.1 | 49.1 | −8 % | 1206 → 1188 |
| open-home | 12.8 | 12.4 | −3 % | 218 → 206 |
| open-timer | 7.8 | 7.5 | −4 % | 154 → 154 |
| timer-done | 12.6 | 12.1 | −4 % | 432 → 448 |
| volume | 6.1 | 5.8 | −5 % | 218 → 226 |
| airpods | 1.8 | 1.6 | | 110 → 112 |
| open-battery (new page) | — | 7.5 | below open-home | 148 |
| siri | 63.0 | 67.9 | +8 % (the middle pass: 68.4 → 64.8, noise) | 310 → 311 |
| siri-search (typing "smile") | 113.3 | 133.4 | **+18 %, not met** | 366 → 421 |
| spam-open (10 × open/close, 0.25 s) | 32.9 | 37.9 | **+15 %, not met** (another order: 25.8 → 27.1) | 1120 → 1126 |
| spam-siri (8 × open/close) | 79.8 | 90.7 | **+14 %, not met** (another order: equal) | 1528 → 1590 |

- **First opening of the panel after a launch** (open-home run first): 33.6 → 46.8 (+36 %, once per
  launch). About 5 of the 13 come from the header's four-page picker and the battery button; the
  rest from the new widget code's first build.
- **siri-search** pays for the new Spotlight sources (commands, System Settings panes, emoji) on
  the first search after a launch; typing itself got cheaper (below).
- **spam-open / spam-siri** depend on the order of the scenarios: with the panel or Siri opened
  first after a launch they are within noise of v0.5.1, after the other scenarios 14–15 % above.

### What changed (each kept only with the look, the timing and the behaviour unchanged)

**Settings**
- The pages and every gallery preview fade in on the render server (a Core Animation opacity
  animation on their own layer) instead of a SwiftUI fade that updated the outer view graph on
  every frame. Each preview is its own picture host, re-rendered only when its widget changes.
- The desktop picture behind the stage and the gallery is looked up once per opening and shared
  (it was looked up about ten times).
- Isolated hosts re-render only when their input changes (an equatable input).

**Siri and Spotlight**
- App icons are kept on disk (8-bit BGRA, keyed by the app's path, the dates of the bundle and its
  Info.plist, the scale and the icon style), so the app gallery draws no icons when it opens; a
  tidy at most once a day drops icons of removed apps and old icon styles.
- Siri's lists, rows and icons are kept 10 s after closing, so a quick re-opening rebuilds nothing.
- The glow's flowing band is played by the render server (SwiftUI's own gradient layer with a
  49-step keyframe animation of its end point, 30 frames a second) instead of a 30 fps SwiftUI
  timeline: no CPU in the app while the glow runs. Held-frame screenshots are identical to v0.5.1.
- Typing: names are folded for matching once and kept (the lists are matched again on every key);
  the result list is redrawn only when a list really changed; the Siri view no longer rebuilds on
  every keystroke. Offscreen: 11.2 → 3.0 ms per typed query in the model, 62 → 37 ms for the view.
- Emoji are indexed once per opening.

**Panel and widgets**
- The header's page picker measures itself once, not on every opening: a `ViewThatFits` (added
  for the fourth page) had measured the system's segmented bar again at every opening, the
  largest new item in a `sample` of spam-open.
- The widget style layer costs nothing when a widget has no style: the element modifiers take the
  resolved style as a value, and an element without overrides gets exactly its old font. Board
  opening offscreen: 103.3 → 89.1 M instructions (v0.5.1: 96.4).
- The timer ruler's resting picture draws one capsule per minute and a number every fifth minute
  instead of a full tick stack per minute: the timer widget costs 18 % less to open (pixel
  identical at 1×, 2× and 3×).
- Clock texts and text widths are remembered instead of formatted and measured again.

**Rest and launch**
- The diagnostics report after a launch is scheduled by the system at background priority, with
  the hardware and app sections kept per boot and version.
- The liquid card's outlines are kept on disk and not worked out at all when both liquid cards are
  off.
- The widget board is written 0.4 s after the last change, not on every slider step.
- The battery history records only real changes from the power notifications the app already
  receives: no new wake-ups.

### Tried and left out
- **Settings ▸ General built lazily** (sections below the fold built when scrolled to): opening
  General 37 % cheaper offscreen, but every scroll through the page cost about twice the CPU. Left
  out.
- **The Widgets page's stage shadow as a fixed outline shadow**: SwiftUI's shadow is drawn from
  the glass's own transparency, so an outline shadow cannot be proven identical. Left live.
- **Settings gradients and shadows as pre-rendered bitmaps**: they already are Core Animation
  layers; nothing to gain.
- **The glow as a film of pre-rendered frames**: the renderer's frames differ from the render
  server's gradient by up to 155/255 (dithering). The render server's own layer is animated instead.
- Suspects measured and cleared for spam-open and spam-siri: the glow (old vs new: equal) and the
  new concentric widget corners (uniform vs concentric: equal).

### Left for next time (worst first)
- Opening Settings: 425, the goal is 200 (and 30 for every animation).
- siri-search and the first opening after a launch: the new sources' and widgets' first build.
- spam-open and spam-siri after the other scenarios.
- The Now Playing and Shelf widgets alone: +2.6 % and +6 % instructions per opening against
  v0.5.1 (the player's icon is drawn again each time).

### Checks
- **Looks:** frozen-frame screenshots against v0.5.1 (`demo/freeze`, `Scripts/perf/frames/`):
  Siri 0.1 s into opening and settled, the app gallery, the timer page (its ruler included) and
  Settings ▸ General settled within the noise of two shots of the same build; in the middle pass
  Siri at 0.1 and 0.3 s was identical to the pixel. Intended differences only: the header's fourth
  page (Battery), the widgets' bottom corners concentric with the panel's, the Now Playing cover's
  corners following its padding, and the widget gallery's new categories (a narrower bar, so the
  Widgets page no longer widens Settings by 12 pt).
- **Unit tests:** 724 tests in 160 suites, plus the 242 widget snapshots (exact) in their own run.
  Failing in the full run: the known liquid-card lead (0.25 → 0.20, the owner's change) and
  timing tests that pass when run alone (`DelayedActionTests`, `BannerCenterTests`, the Settings
  fade test, `otherRowsNeverWaitForTheRunningApps`).

## 2026-09-29: energy campaign on v0.5 (build 21)

**Machine:** MacBook Air M5 (Mac17,3), macOS 27, 3024×1964 built-in display, on battery the
whole time (80 → 77 % for the "before" pass, 59 → 56 % for the "after" pass: both above 30 %, so
both on the same core scheduling). Liquid Glass style: Fade; level style: banner.

**Builds compared:** "before" = v0.5 (21) as released plus the uncommitted liquid-card lead
(`airPodsMode` 0.20); "after" = the same plus this campaign. Release builds, signed with the same
identity. Report destinations removed from the test builds so no diagnostics were sent while
measuring (diagnostics otherwise on).

**What the numbers are**
- **Activity Monitor's Energy Impact is the app's coalition energy in mW** (checked on screen:
  opening Settings on "before" read 245 in Activity Monitor while `top`'s POWER column peaked at
  54). `Scripts/perf/anim.py` reports it per scenario as the worst 1 s and worst 5 s window
  (Activity Monitor averages over its update interval). This is the number the owner's targets
  refer to: at most 30 during any animation, close to 0 at rest with music playing.
- CPU ms: the app's own CPU time (with child processes where the tool reads the coalition).
- GPU: the app itself does no GPU work (SwiftUI's renderer draws on the CPU, `RB_DISABLE_GPU`); its
  pixels are composited by WindowServer. WindowServer ran at 36–43 % CPU on this Mac with or without
  NotchIsland (0.7 % apart, within its own noise), so no cost was moved there.
- Single runs of `anim.py` vary by ±20–40 % for the first opening after a launch (the liquid card's
  outlines are worked out in the background right after launch); the tables give each pass's run
  as measured, and repeated A/B runs are quoted where a decision rested on them.

**How to measure again** (the app running, music playing in Music):
`Scripts/perf/anim.py` (every animation, Activity Monitor's number), `Scripts/perf/events_bench.py
<label>` (every demo event, AirPods cards included), `Scripts/perf/night.py cycle <label> 120`,
`Scripts/perf/states.py <label> 20`, `Scripts/perf/levels_bench.py <label>`, `Scripts/perf/idle.py
180` with `Scripts/perf/coalition.py 180 5` for rest.

### Result in short

| | before | after | |
|---|---|---|---|
| Opening Settings, energy per round (A/B, 3 runs each) | ~2.4 J | ~1.4 J | **−40 %** |
| Opening Settings, Activity Monitor peak (A/B, worst 5 s) | ~370 | ~172 | **−53 %** |
| Opening the panel (home), Activity Monitor worst 5 s | 38.2 | 27.9 | −27 %, now under 30 |
| Siri's clipboard / Siri's app gallery, worst 5 s | 22.5 / 62.5 | 15.3 / 48.7 | −32 % / −22 % |
| Timer page opening, worst 5 s | 12.0 | 8.5 | −29 % |
| Liquid volume card, `top` POWER peak per change | 28.0 | 5.4 | −81 % (CPU max 197 → 78 ms) |
| At rest, music playing (A/B back to back, 2×100 s each) | 0.13 mW (AM ~0.1) | 0.13 mW (AM ~0.1) | unchanged: already at the floor |
| Memory at rest after the tour | 69–73 MB | 59–63 MB | −10 MB |

**Honestly:** the owner's targets were "idle with music close to 0" and "no animation above 30".
Idle with music already sat at ~0.1 in Activity Monitor (0.13 mW, 0.07 % CPU, 0.4 wake-ups/s)
and stays there; the one bump left at rest is the diagnostics launch report for testers (~0.7 s of
CPU, 90 s after a launch, only with diagnostics on). Single animations are under 30 except
**Settings** (still ~170–400 depending on the page opened) and **Siri's app gallery** (~49); rapid
repeated use (`spam-*`) of Siri, the pages and the panel stays above 30. Gains are real but
uneven: large on Settings, the liquid card and Siri's rooms, small or within the noise on the
banners.

### Rest: the fair comparison

The first "before" pass read 0.00 mW at rest for its first minute because the spectrum tap only
started ~70 s after launch in that run, so the rest was re-measured back to back, same state,
battery 57 → 56 %:

| build | round 1: mW mean / median | round 2 | CPU % | wake-ups/s |
|---|---|---|---|---|
| before | 0.137 / 0.140 | 0.126 / 0.110 | 0.07 | 0.34–0.45 |
| after | 0.132 / 0.120 | 0.129 / 0.120 | 0.07 | 0.44–0.45 |

(`after` pass, rest with music, 180 s: steady 0.02–0.15 mW after the first 5 s; paused: 0.0–0.8.)

### What changed (every change kept only with the look, the timing and the behaviour unchanged)

Screenshots of Settings (0.1, 0.25, 0.45 s into its growth and settled, General and Widgets), the
panel (0.2 s and settled), Siri, the volume banner and the finished-timer banner, taken over a still
backdrop with every spring frozen (`demo/freeze`), match the old build's pixels within the noise of
two shots of the same build (≤ 0.1 % of pixels more than 2/255 apart, none of them on the island).

**Settings (the worst: Activity Monitor 245–470 on opening)**
- The island's window draws at 8 bits per channel (`IslandPanel.depthLimit`). SwiftUI's CPU
  renderer had drawn its shadows, blurs, gradients and pictures at 16 bits per channel for the
  near-screen-sized Settings page. A/B: 2.4 J → 1.7 J per Settings round (−28 %), pixels unchanged.
- Opening Settings runs its first 0.7 s on the efficiency cores (`MainThrift.lowPower`, as Siri's
  first opening and Settings' closing already did). The growth itself runs in the render server, the
  page comes in with the same cross-fade. A/B on top of the above: 1.98 J → 1.44 J (−27 %), worst
  5 s 240 → 172. Together with the depth: ~2.4 J → ~1.4 J, Activity Monitor's peak about halved.
- The isolated Settings host no longer gives its hosting view a new root on every island update.

**Idle with music (the spectrum tap behind the bars)**
- A rest between analyses ends on the audio thread (one host-time comparison per I/O cycle) instead
  of a main-thread task: one main-thread wake-up fewer per analysis window.
- Letting go of the tap keeps the device running 2 s before stopping it: every banner, panel peek or
  rebuild of the compact view had stopped and restarted the audio device (~19 ms each, and the
  recording indicator blinking) since 99973f5 — the likely cause of the rest regression seen then.
- Exact digital silence (no recording permission, muted playback, the gap after a song) skips the
  analysis work that could not change anything: ~4× less analyser CPU then, bit-identical output.
- Each hand-over: the debug line is only formatted when debug logging is on; a bar holder without a
  beat no longer copies its presentation layer.
- A new cover is drawn once into Core Animation's own 8-bit BGRA layout (opaque sRGB covers), so the
  render server no longer makes a colour-converted copy of it.

**AirPods and volume/brightness**
- `system_profiler` (read on AirPods events, during the card's animation) runs as one process
  instead of two (`-nospawn`, byte-identical output).
- The audio device-list listener runs off the main thread; the main thread hears only when the
  Bluetooth outputs change (the spectrum tap's own private device no longer re-lists every device
  there).
- Watching macOS's own AirPods card: no window-list read before the card in cover mode, one read
  instead of two after, off the main thread.
- Level writes that change nothing no longer notify observers.
- The volume banner over macOS's card reads the output's name from CoreAudio once per banner, not
  in every evaluation of its body.

**The island**
- An on-battery flag of its own: the battery's level and time left (changing about once a minute on
  battery) no longer re-evaluate the island's root and the compact now-playing view.
- Siri rests on its transition frame, as the panel and Settings do: one window resize fewer for each
  Siri opening, closing and growth (field → rows → list → gallery).
- Fade style: the text halo is not drawn on the pills, where the band under them is solid black and
  a halo changes no pixel.
- Siri's row icons are looked up and drawn off the main thread (same pixels).
- The transport buttons take values instead of a closure: a re-render no longer re-springs their
  interactive glass. The played line waits while its panel is kept hidden.
- Dead code removed: the growth blur that never ran, `MainThrift.run` and its slow-mode net, unused
  glass roles and two unused layout and presentation members.

**Tools:** `events_bench.py` sent `value=` where the app reads `level=` (every volume/brightness row
measured the defaults), now also measures the four AirPods noise-control cards, GPU ms and wake-ups,
and writes JSON; `night.py` drives the music through the island's own media commands (Music's
scripting can hang on an Automation prompt).

### Tried and left out
- **GPU rendering** (`RB_DISABLE_GPU=0`) on top of the 8-bit window: a further ~5–10 % on Settings
  for far more memory (as in September): left out.
- Rejected by review because the user could see or get something different:
  - the tap stopping while the screen is locked: after unlocking, the bars would come back with a
    stale beat from before the lock;
  - no drift compensation on the tap: Apple's documented setup has it on, and nothing was measured;
  - the native mini/small level sliders shown as a picture at rest: not checked on screen;
  - pausing the island's clocks while locked: tied to the tap change above;
  - two changes with no measurable gain: the timer sound loaded ahead, and a demo-only AirPods
    shortcut.
- Declined by the implementers because the look could not stay identical:
  - Siri's in-place morphs moved to the render server: the glass cannot be resized there without
    changing it;
  - Core Animation cross-fades instead of SwiftUI's blur-replace for the pill ↔ panel swap: the
    blur-replace is the look;
  - the symbol effects (bell, drop, AirPods), which are drawn by the system;
  - Siri's answering glow as a Core Animation layer.

### Left for next time (worst first)
1. **Settings' first drawing**: SwiftUI's CPU renderer draws the near-screen-sized page's shadows
   (distance filters), blurs and gradients; ~1.4 J per opening even on the efficiency cores.
2. **Settings ▸ Widgets while open**: 14–16 % CPU continuously (its live previews).
3. **Siri's app gallery** (~49 worst 5 s) and repeated Siri use.
4. **Siri's in-place morphs** (SwiftUI rebuilds the glass, clip and content every frame): would need
   a render-server outline for the glass, which could not be made pixel-identical.
5. **The diagnostics launch report** (testers only): ~0.7 s of CPU 90 s after each launch.
6. **The liquid card's outlines** worked out right after launch (~0.3 s of CPU in the background).

### Tests
`Scripts/test.sh`: 500 of 501 pass. The one failure, `LiquidCardExitTests.eachCardLeavesWithItsOwnLead`,
expects the noise-control card's exit lead 0.25 where the working tree holds 0.20: that is the
uncommitted hand-tuning in `LiquidCard.swift`, not part of this campaign.

## Full tables (the `before` and `after` passes of `measure.sh`, same scripts, same order)

### Animations (Activity Monitor's Energy Impact = coalition mW; worst 5 s window, worst 1 s, CPU ms)

| scenario | AM 5 s before | after | change | worst 1 s before | after | CPU ms before | after | change |
|---|---|---|---|---|---|---|---|---|
| settings | 468.9 | 405.6 | -13 % | 1152 | 1156 | 1198 | 1748 | +46 % |
| spam-siri | 86.0 | 73.2 | -15 % | 135 | 100 | 1542 | 1550 | +1 % |
| siri-apps | 62.5 | 48.7 | -22 % | 168 | 136 | 492 | 391 | -21 % |
| spam-pages | 49.0 | 54.9 | +12 % | 66 | 74 | 1300 | 1196 | -8 % |
| open-home | 38.2 | 27.9 | -27 % | 162 | 113 | 306 | 287 | -6 % |
| spam-open | 38.1 | 33.7 | -12 % | 76 | 61 | 1118 | 1063 | -5 % |
| spam-hover | 26.2 | 26.7 | +2 % | 31 | 30 | 1191 | 1207 | +1 % |
| siri-clipboard | 22.5 | 15.3 | -32 % | 75 | 54 | 388 | 277 | -29 % |
| spam-volume | 21.7 | 20.9 | -4 % | 25 | 24 | 738 | 851 | +15 % |
| spam-open-slow | 17.7 | 20.4 | +15 % | 29 | 34 | 1264 | 1200 | -5 % |
| siri | 13.8 | 12.1 | -12 % | 39 | 36 | 250 | 198 | -21 % |
| open-timer | 12.0 | 8.5 | -29 % | 38 | 31 | 194 | 150 | -23 % |
| timer-done | 11.2 | 11.7 | +4 % | 36 | 32 | 358 | 393 | +10 % |
| volume | 7.1 | 5.8 | -18 % | 18 | 14 | 184 | 217 | +18 % |
| open-shelf | 4.9 | 5.0 | +2 % | 16 | 15 | 127 | 132 | +4 % |
| hover | 3.6 | 3.4 | -6 % | 10 | 8 | 104 | 117 | +12 % |
| battery | 2.8 | 2.9 | +4 % | 7 | 8 | 107 | 119 | +11 % |
| airpods | 2.6 | 2.4 | -8 % | 7 | 6 | 97 | 120 | +24 % |


### Single events (own process: CPU ms, idle wakeups, top's 1 s POWER peak)

| event | CPU ms before | after | change | wakeups before | after | POWER peak before | after |
|---|---|---|---|---|---|---|---|
| volume?level=0.4 | 80 | 94 | +18 % | 18 | 33 | 3.5 | 4.3 |
| brightness?level=0.6 | 83 | 93 | +12 % | 11 | 34 | 3.7 | 4.8 |
| charging | 91 | 98 | +8 % | 7 | 42 | 3.4 | 5.3 |
| unplug | 94 | 95 | +1 % | 5 | 36 | 4.2 | 4.6 |
| low | 82 | 94 | +15 % | 9 | 41 | 3.7 | 4.6 |
| timerdone | 344 | 292 | -15 % | 25 | 196 | 12.9 | 13.0 |
| drop | 67 | 84 | +25 % | 7 | 36 | 3.2 | 4.6 |
| airpods | 78 | 116 | +49 % | 38 | 45 | 4.6 | 5.3 |
| airpodsmode?mode=anc | 77 | 94 | +22 % | 31 | 26 | 4.2 | 3.9 |
| airpodsmode?mode=transparency | 78 | 101 | +29 % | 23 | 50 | 3.5 | 5.2 |
| airpodsmode?mode=adaptive | 81 | 99 | +22 % | 26 | 53 | 3.5 | 4.8 |
| airpodsmode?mode=off | 73 | 93 | +27 % | 29 | 42 | 2.3 | 3.3 |
| media | 23 | 36 | +57 % | 3 | 5 | 0.2 | 2.6 |
| siriapps | 378 | 476 | +26 % | 14 | 26 | 18.8 | 27.1 |
| siriclipboard | 303 | 210 | -31 % | 10 | 43 | 17.1 | 12.8 |


Single events are the app's own CPU only (the AirPods noise-control rows start `system_profiler`, a
child process, which `anim.py`'s coalition numbers include). The `after` pass ran with the spectrum
tap following the music from the start, the `before` pass without it for its first minute (see
above): part of the extra wake-ups per event are the tap's I/O cycles.

### Soak scenarios (night.py: CPU %, top POWER mean / peak, memory peak MB, wakeups/s)

| scenario | CPU % before | after | POWER peak before | after | MB peak before | after | wakeups before | after |
|---|---|---|---|---|---|---|---|---|
| rest+music | 0.11 | 6.29 | 0.3 | 43.7 | 69 | 63 | 0.6 | 16.5 |
| open-home | 3.26 | 8.62 | 11.0 | 54.5 | 72 | 71 | 1.1 | 18.0 |
| open-timer | 2.08 | 1.80 | 6.3 | 5.5 | 72 | 61 | 4.7 | 4.2 |
| open-shelf | 1.78 | 1.60 | 5.3 | 4.2 | 71 | 61 | 4.9 | 4.7 |
| hover | 1.71 | 1.51 | 5.1 | 4.2 | 71 | 61 | 3.6 | 4.1 |
| siri | 2.84 | 1.86 | 8.3 | 6.1 | 71 | 62 | 1.6 | 4.7 |
| siri-apps | 6.21 | 4.76 | 19.2 | 12.5 | 72 | 62 | 1.7 | 6.0 |
| siri-clipboard | 4.70 | 3.05 | 18.2 | 13.2 | 71 | 60 | 2.2 | 4.2 |
| volume | 2.69 | 2.51 | 11.8 | 8.0 | 70 | 59 | 13.5 | 9.2 |
| battery | 1.42 | 1.57 | 4.3 | 4.9 | 70 | 59 | 2.2 | 3.7 |
| airpods | 1.09 | 1.11 | 3.6 | 1.3 | 70 | 59 | 4.7 | 3.8 |
| timer-done | 2.93 | 2.38 | 13.5 | 10.6 | 70 | 59 | 14.2 | 11.5 |
| drop | 0.91 | 0.80 | 2.4 | 2.9 | 70 | 59 | 3.4 | 3.4 |
| track-change | 0.65 | 0.55 | 3.0 | 0.4 | 70 | 59 | 0.5 | 0.3 |
| settings | 7.35 | 6.82 | 35.1 | 32.6 | 120 | 120 | 5.0 | 1.8 |
| after-settings | 0.10 | 0.10 | 0.3 | 0.2 | 73 | 60 | 0.4 | 0.2 |
| rest-paused | 0.10 | 0.09 | 1.4 | 1.0 | 73 | 60 | 0.4 | 0.7 |
| open-home-paused | 2.01 | 1.68 | 6.6 | 5.4 | 73 | 62 | 2.9 | 1.1 |
| rest+music-again | 0.17 | 0.16 | 0.2 | 0.3 | 72 | 60 | 0.3 | 0.4 |
| rest-1m | 0.67 | 0.10 | 1.6 | 0.3 | 72 | 60 | 0.4 | 0.4 |
| rest-2m | 0.08 | 0.08 | 0.2 | 0.2 | 72 | 60 | 0.4 | 0.3 |


In the `after` soak, the first two scenarios (rest+music, open-home) caught a ~40 s burst of 6–9 %
CPU that no other pass or A/B showed and that could not be traced afterwards; every other
scenario is at or below its `before` value.

Steady states (panel pages and Settings left open, `states.py`, measured back to back on both
builds with music playing): the same within noise on both — expanded home ~3.4 % CPU, Settings ▸
Widgets **~14–16 % CPU for as long as it stays open** (its live previews), everything else under
0.5 %. The first `before` pass had read Widgets at 2.3 % with the bars not yet following the music.

### Liquid volume card (levels_bench, per change)

CPU 82 → 74 ms (max 197 → 78), top POWER mean 2.68 → 1.84, max 28.0 → 5.4.

