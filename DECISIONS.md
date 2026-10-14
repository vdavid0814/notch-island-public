# DECISIONS.md

Decisions that shape the code, newest first, with when they were made. Add a line when you make
or learn one; never rewrite an old one — add a newer line that replaces it.

Format: `YYYY-MM-DD hh:mm` — the decision. *Why.*

---

- **2026-10-14 14:00** — Memory macOS counts twice is counted once (`AliasTrim`: a place wholly
  covered by another kept mapping of the same memory is mapped onto itself); memory mapped once
  is never touched that way. *The same call takes singly mapped memory out of Activity Monitor's
  number while it stays in RAM: a number that lies.*
- **2026-10-14 14:00** — The closed panel is kept at rest too, for ten minutes (the content stack
  stays, unseen). *Taken away at rest, every opening from an empty notch built the panel and its
  page picker again: 50 → 15 mJ an opening; a banner costs ~4 mJ more, ~6 MB.*
- **2026-10-14 14:00** — Siri's file search is stoppable: gathered in steps and stopped when the
  user types on. *A synchronous Spotlight query for one letter ran ~460 ms in Spotlight's daemons,
  ~1 J billed to the app, for rows nobody saw.*
- **2026-10-14 14:00** — Openings' energy (own + billed) is part of every diagnostics report.
  *The user judges the app by Activity Monitor's spikes at an opening, not by its average.*
- **2026-10-13 22:42** — Released as 0.8.5.4.
- **2026-10-13 21:40** — Siri's field, list and gallery stay SwiftUI's animation. Tried again on the
  render server (the outline's mask with the glass body's own layers given the outline's frames):
  the glass went and the content sat wrong; the fade style's black is drawn for the held outline
  besides. *Not the same picture, so not shipped (`refs/backup/siri-glass-experiment`).*
- **2026-10-13 21:30** — The content's swap on the island (pill, banner, panel) is faded by the render
  server where it is a plain cross-fade (on battery, Low Power Mode, into Siri): SwiftUI swaps at
  once and keeps what leaves, unseen, until its layers have faded (`IslandModel.contentSwap`,
  `ContentSwapMotion`). On the charger the blur-replace stays SwiftUI's. *Half the main thread's
  turns of an opening and closing; the energy about the same (174.8 against 178.0 mJ a cycle).*
- **2026-10-13 20:40** — The panel's page switch runs on the items' own layers (`PanelPageMotion`):
  held as they were until the shown page has drawn itself, then all started together, late items
  joining in step. SwiftUI makes the change at once (`IslandModel.show`). *83–98 → 37 ms of main
  thread a switch, 187 → 156 mJ for two; SwiftUI's own animation had waited for the page the same way.*
- **2026-10-13 19:30** — Nothing is moved to background quality of service on a busy Mac
  (`MainThrift.canLower`: `SystemLoad`), and every lowered stretch is watched from another thread
  (`ThriftWatch`): starved, blocked, met by the pointer or by a key, the main thread gets its
  priority back at once. Settings' first preparation step builds the shell and sidebar only; it is
  not built ahead while memory is tight, and is built at the thread's own priority on a Mac that is
  only busy. *16 hang reports from one Mac (builds on every core, 150–390 MB free): a lowered turn
  of 0.1 s took 2 s and more; reproduced with ten cores taken — the main thread stood for 28 s.*
- **2026-10-13 18:30** — Released as 0.8.5.3.
- **2026-10-13 18:20** — Settings ▸ Widgets ▸ Size sets the page it shows (`Preferences.pageSizes`: its cells
  and its ready-made size); Apply to All Pages makes it every page's; General's Size when Open is every
  page's. The island is at the size of the page it shows. *The user: one page sized, not all.*
- **2026-10-13 17:50** — Fan Control's animations on the render server: the dials as layers (`RingLayers`),
  the graph drawn once a reading and glided 0.35 s (soft) by Core Animation (`FanGraphLayerView`).
  SwiftUI per-frame animation on the island cost 300–600 ms of main thread per 0.8 s (debug build).
  *The user picked the short glide over a continuous slide (window server 250 → 156 mW).*
- **2026-10-13 17:20** — Fan Control has no pointer read-out (removed after it lagged on the island:
  SwiftUI state per move came in bursts; an NSTrackingArea of the widget's own got no moves, as the
  panel takes no mouse-moved events). *The user asked to take it out.*
- **2026-10-13 16:00** — Fan Control redesigned from the proposal the user chose: one graph (heat line,
  the fans as strokes whose spacing is the speed, `FanRhythm`), colours by reading green → yellow → red,
  a dotted line at the lowest temperature, words on the dials, Manual the button back to automatic;
  reach 10 s–10 min on the timer's ruler (minutes and seconds, haptics), seconds below 10 only once a
  minute is set. The speed graph went (its looks are left out of saved widgets).
- **2026-10-13 15:50** — Usage by App counts percent of the battery, not energy shares (replaces 15:18's
  shares): each percent the battery drops goes to the apps by the energy they used since the drop
  before (a sweep at each drop, plus every 5 min between), so a day's rows add up to Daily Usage's
  figure; what no app was measured for is a "Not measured" row. Calendar days, from midnight.
  *The user: the apps must add up to what the day really used.*
- **2026-10-13 15:43** — Battery Chart's hours (replaces 15:33's "23"): 00, 06, 12, 18, 24, each centred on its
  line, the plot inset by half an hour's text on each side for the ends; every other one, or the ends
  alone, where they would touch. *The user: evenly spaced, so the bars show to the hour when it ran down.*
- **2026-10-13 15:33** — Battery Chart writes its percentages at every size (was only 220 pt wide and 60 pt tall
  and up); the plot narrows for them, a low chart writes only 0 and 100 %. The hours too, at every size, the last one
  (23) at the axis's end; a chart a row tall writes both at 8 pt. *The user: they must stay.*
- **2026-10-13 15:18** — Usage by App (`appUsage`, the iPhone's Battery Usage by App): every user process's
  energy counter (`proc_pid_rusage`) read every 5 min on a background queue, only while on battery
  (no timer on the charger), attributed to the responsible app's outermost `.app`; macOS's own parts
  as one "macOS" row. An exception to "no repeating timers": nothing pushes per-process energy.
  *~12 ms of CPU a sweep; root's processes (WindowServer, kernel) cannot be read without the helper.*
- **2026-10-13 12:50** — Released as 0.8.5.2. Since Light Mode's approval: Dark Mode's clearest
  glass is 20 % black, growing to 40 % along the slider; the notch-height pill is solid black on
  Liquid Glass in both Modes (its black fading in while the island closes); each Mode has its own
  automatic widget background (Light #B5B5B5 50 %, Dark black 40 %), announced in Settings ▸
  Widgets with Revert Changes; Settings' after-launch preparation waits while the Mac is busy or
  short of memory (`SystemLoad`). *A user's Mac stuttered after an update under heavy load.*
- **2026-10-13 11:54** — Light Mode on Liquid Glass approved as it is (replaces 10:30 and 09:40 for Light
  Mode): the island and its content in the light appearance (black texts and symbols); the system's
  clear glass with white frost growing evenly along the Liquid Glass slider, 30 % → 55 %, and the
  system's frosted glass with 55 % white at its very end; a thin black edge round the island and
  the volume/AirPods card (35 %, 0.5 pt); grey chart bars edged in 60 % black; sliders black on a
  15 % black track; the battery with a black edge, nub and number; the page picker on 30 % white
  with 5 % frost. Every widget gets Colour #B5B5B5 at 50 % as Light Mode on Liquid Glass begins
  (whatever it had), kept over the whole slider, given back on leaving; the user's changes meanwhile
  stay until then. *Tuned with the user step by step on October 13; Dark Mode is next.*
- **2026-10-13 10:30** — The clearest Liquid Glass has 10 % white frost in the glass and 10 % black
  under it. Light Mode's automatic black widget background follows the slider: on only while the
  glass is clear. Only the user's own background edits opt a widget out; a board put back whole
  (⌘Z, a notch style) no longer does. *Asked for; the Home widgets had been opted out that way.*
- **2026-10-13 09:40** — Liquid Glass follows the system's Liquid Glass slider as the system's
  own glass does ("C4", picked from 17 photographed variants): clear glass with its white veil
  taken out below ¼ of the slider, the frosted `.regular` glass from ¼, with 40 % black in it past
  ¾. The same in Light and Dark Mode; the old 20 % Light Mode black and the 0–50 % black under the
  glass are gone. *The user liked it best of the variants; tuning continues from here.*
- **2026-10-13 06:59** — On the charger Settings stays built while the Mac is in use, and is freed
  2 min into lock/display sleep or on memory pressure (no timer-based give-up while in use).
  *Reopening a given-up Settings spiked Activity Monitor to ~3900; memory still comes back when away.*
- **2026-10-13 02:09** — Settings' ahead-of-time build (frames, wallpapers) stays on the efficiency
  cores. *Work nobody waits on must not show up in Activity Monitor.*
- **2026-10-12 04:15** — Tests never change the real output volume; volume banners go through
  `notchisland://demo/…`. *A test made the user's music loud.*
- **2026-10-11 18:58** — Fan Control: a speed set by hand is held until the user gives it back;
  only the chip at 105 °C hands the fans back to macOS automatically. Fans may go down to 0 rpm.
  *95 °C was reachable under normal heavy load and undid the user's setting.*
- **2026-10-11 17:48** — Memory on the charger, energy on battery: Settings kept built only on
  battery (27 MB at rest on the charger instead of ~220). *Superseded on the charger by 10-13 06:59.*
- **2026-10-11 14:51** — Island pictures in Settings are real photographs of the island
  (`Scripts/settings-pictures.sh`), never drawings; Settings pages stay one column.
  *Drawn versions were rejected three times — proportions, corners and glass never matched.*
- **2026-10-11 14:51** — Liquid Glass is plain clear glass (no tint, white veil cancelled) and
  follows System Settings ▸ Appearance ▸ Liquid Glass. Fade's glass stays as it was.
  *Its slider-following replaced by 10-13 09:40.*
- **2026-10-11 12:26** — The scroll pacer was removed. Energy savings must come from less work per
  frame or moving motion to the render server, never from fewer updates.
  *It halved the ruler to 30–40 fps; the user noticed within minutes.*
- **2026-10-10 12:04** — `make-dmg.sh` refuses a release without the Sentry, Mixpanel and Discord
  addresses. *0.8.2 shipped without them: no reports from any 0.8.2 install.*
- **2026-10-05 19:07** — Widgets rebuilt from scratch on a few bases (button, slider, label, live
  number, composite, chart); every other kind comes back on top of those. New widget kinds are
  added after the base ones in `IslandWidgetKind`. *The user wants to design the basic elements
  first. Order matters: snapshots drawn earlier shift later ones by 1/255.*
- **2026-10-03 11:55** — Deferred main-thread work runs from a run-loop timer at background QoS,
  not `Task {}`. *A Task brings its own priority onto the P cores; Settings prep 5.0 → 2.35 J.*
- **2026-10-03 00:07** — Every release is signed by one certificate, pinned in
  `Support/release-requirement.txt`; the in-app updater installs only a download that satisfies it.
  *Releases signed by two different certificates made users lose Accessibility and Input Monitoring.*
- **2026-10-02 03:28** — Settings is built once after launch and kept in a window of its own, each
  page its own hosting view; kept hosting views are never moved to another superview.
  *Laying the pages out was ~1.2 s per open; inside the island's window every resize went over them.*
- **Since the start** — No repeating timers: every signal is pushed by the system; one-shot deadlines
  are cancellable and owned by one object. The `NSHostingView` is never the panel's content view, and
  the panel refuses any frame it did not stage. *Both came from a live crash; see ARCHITECTURE.md.*
