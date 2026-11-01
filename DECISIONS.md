# DECISIONS.md

Decisions that shape the code, newest first, with when they were made. Add a line when you make
or learn one; never rewrite an old one — add a newer line that replaces it.

Format: `YYYY-MM-DD hh:mm` — the decision. *Why.*

---

- **2026-11-01 21:00** — A new track's title (Live Activities ▸ New Track) is a banner nobody asked
  for: it buries no other notice, shows only for a title other than the last one played (no pause,
  resume or gap between tracks), not for what already plays at launch, and waits up to 0.8 s for the
  cover so it shows in the cover's colour. Its glide is one Core Animation move on a pre-drawn title.
  Listen Again keeps only Music's last song (on disk, cover decoded only when shown) and opens Music at
  it by Apple Event without playing it (asked for): Music's current track, else the library by title
  and artist, else Music's search for it.
  *Asked for; the energy rules: no SwiftUI frames for motion, nothing decoded unseen.*
- **2026-11-01 19:00** — The island's screen is the user's choice (Live Activities ▸ Displays: Automatic,
  MacBook or a monitor, kept by vendor-model-serial since display ids change at every plug-in); a choice
  that cannot be met falls back, never hides the island. A monitor plugged in beside another screen
  brings a notice with the screens as the island's choice bar (1–30 s, off in Settings); none for 15 s
  after a wake. A screen picked while Settings is open is moved to once it closes. On a screen without
  a notch the island at rest is a faint grey line, not nothing. *Asked for: MacBook + monitor use, and
  the M1 Air / MacBook Neo, which have no notch.*
- **2026-11-01 19:40** — Settings' page scroll views use `.scrollIndicators(.never)`, not `.hidden`: with a
  mouse connected macOS's always-on scroller came back beside the edge scroller (two bars). The panel
  kept at rest draws no surface at all (`isHiddenAtRest`): the opacity round it did not reach the glass
  container's black, a black notch on a monitor. *Both seen by the user on an external display.*
- **2026-11-01 19:15** — On a screen without a notch the island opens and closes with the same move out
  of the notch's shape and back into it, fading in over the first 40 % of the way out and out over
  the last 40 % of the way in (`IslandOutlineMotion`, on the render server with the outline), so no
  black notch is left where there is none. *Asked for: a sliver-shaped rest outline was rejected.*
- **2026-11-01 19:30** — The rest line is the island window's own view (`IslandStageView.showRestLine`), over
  the content and outside the outline's mask: shown as a close begins and kept through it, faded as an
  open begins. *Inside SwiftUI it faded with the island and flashed back when the mask went (asked for).*
- **2026-11-01 19:40** — Live Activities ▸ Screens Without a Notch opens on a drawn picture (`RestLinePicture`):
  a monitor's top with the line as the sliders have it, drafts included, like Now Playing's width
  picture. *Asked for; a photograph could not follow the sliders.*
- **2026-11-01 19:50** — A Settings section headed by a feature's switch reads: the switch, its picture,
  then its options; while the switch is off the options fold up out of sight (`settingsFolded`, an
  animated `SettingsFold` layout on `StudioStageSpring.unfold`, the Size room's spring) and the picture
  stays. A choice drawn as pictures (volume style, anchor size) stays, dimmed. *Asked for, on General,
  Live Activities and Spotlight.*
- **2026-11-01 18:00** — Storage shows System Data's places outside the home folder: Time Machine's
  snapshots (counted; deleted in Disk Utility, which it opens: their size is not readable), Simulator
  runtimes, macOS downloads, temporary files, swap, system logs, iPhone updates, purgeable space, and with
  Full Disk Access apps' containers over 1 GB (Docker's and virtual machines' disks). macOS's own are shown,
  never cleared. *Asked: a Mac with hundreds of GB of System Data nobody could delete.* What's New from
  Settings comes in only once the panel is shown. *With Settings kept (battery, or in use), the step came
  a moment before the panel showed, the fade was left at its start and the page stayed empty.*

- **2026-11-01 14:05** — Storage measures four places at once (one lane per efficiency core, at most four),
  folders read in bulk (`getattrlistbulk`). *54 s → 18 s for 8.9 → 9.4 J (asked: quicker loading); the
  bulk read alone gave 6 %.* Its overview lists as many places as the box holds, then "Everything else".

- **2026-11-01 12:10** — About's Storage page (the drive beside ⓘ) clears only to the Trash, the Trash
  itself excepted, and asks on the card, not in a dialog. `com.apple.…` folders are never opened.
  *Reading Caches' Apple Music folder brought up a media-library prompt; Messages' leftovers and the Trash need Full Disk Access.*
  Every card says Safe to delete / You'd notice / Leave alone and its Storage row (System Data…). A page's
  scroll content is at least the room's height (`SettingsFormScroll`). *What About opens below a short page's
  end took no clicks: clicks reach only the scroll view's content.*
  Only About's page fills its room (every page switch paid the extra pass). The info pages' frame is
  rounded as the room's foot and their cards concentric inside it (8 pt gap, as the sidebar's). While
  Storage measures, "Loading" and a green line round the notch show it (`StorageLoadingBand`, a host
  that takes no clicks). Your own files are measured only with Full Disk Access: without it macOS asks per folder.
  Storage walks with `fts` in one background task nobody awaits, and keeps a report 10 minutes. *An awaited
  task is lifted to its awaiter's priority: the walk went to the performance cores (68 J → 10 J, ENERGY-LOG).*
- **2026-11-01 (later)** — What's New opens on its highlights (`WhatsNewHighlights`): seven tiles of
  pictures drawn from the release's true numbers and its cards' symbols, round the title, with More Details
  leading to the cards by topic and a back button returning. A topic may have up to 15 cards, the 16th only
  "And many more…" (4×4). *Asked for: a home screen in the look of a bento of pictures, and 15 + 1.*
- **2026-11-01 01:30** — The `whats-new` skill is used at every commit and push, enforced by the hook
  `Scripts/release-guard.py` (it brings the skill up and refuses when the versions disagree). *Asked for:
  in no situation left out.* 0.8.8's Performance and most of its Fixes keep 0.8.7's, compared with 0.8.6:
  it went out a day before, and nothing new was measured.
- **2026-11-01 01:10** — The header menus' lists (Open Notch Styles, Open App Settings) lie over the page,
  not in its header (`HeaderMenuBox`). *The header became the page's bar (`safeAreaBar`), and what stood
  out of it drew but took no clicks: Open and Delete did nothing.* What's New has 4–12 cards a topic, in
  full rows (2×2, 3×2, 4×2, 3×3, 4×3), its window as high as the rows, unfolding on Size's spring. *Asked for.*
- **2026-11-01 00:40** — General has Save App Settings and Open App Settings, placed and drawn as Widgets'
  notch style buttons. A save keeps every `ni2.` choice (boards and top bar too); saved lists, the shelf,
  records and diagnostics stay out. Opening restarts the app and applies them first thing at launch
  (`AppSettingsStore.applyPending`): every part reads its settings as it starts, and reloading each live
  would be easy to get wrong. What was set before is kept in the list. *Asked for.*
- **2026-11-01 00:10** — No outline round widget texts any more (`ClearTextEdge` removed): grey texts and
  own-colour texts are drawn plainly on every surface. Replaces 2026-10-14 17:50. *Asked for.* The grey
  bars' edge in Light Mode stays: it is on bars, not text.
- **2026-10-31 23:50** — What's New from About stays the island's own window under the notch: Settings
  changes into it, its cards coming in as How NotchIsland Works's do, and two fingers go between the
  two (`AppModel.openWhatsNewFromSettings`). Opened after an update, it has no gesture. *Asked for.*
- **2026-10-31 03:00** — What's New has the look and voice of How NotchIsland Works (`InfoPageShell`,
  `InfoCardGrid`): big numbers, then a short card per change, by topic. On the island's own surface, 0.8 of Settings' width and as high as its rows (no gap below), tabs as on GitHub (Features,
  Performance, Fixes, Good to Know), full rows of three. Every release writes it with the `whats-new` skill. *Asked for: the info page's build, style and wording were liked.*
- **2026-10-31 02:20** — The anchored window's raise tab comes only after 0.2 s on the window's very top
  edge (2 pt) beside the notch, see-through, and says "Move window up"/"Move window down". *Asked for:
  a zone over the whole title bar brought it up at every pass, and white stood out.*
- **2026-10-31 02:00** — Now Playing's picture in Live Activities follows the Width slider: drawn in
  the pill's real sizes (`NowPlayingPicture`), not a photograph. *Asked for; a photograph cannot change
  width, the one exception to the photographed pictures, as Spotlight's pictures are.*
- **2026-10-31 01:30** — How NotchIsland Works changes topic only from its bar; two fingers sideways
  are Settings' back and forward there too, and the page is a place of its own in that history
  (`SettingsPlace.showsInfo`). The App Gallery has Recent and Apps titles, Recent in the middle. *Asked for.*
- **2026-10-31 21:30** — Settings cut down, values kept: the switches taken out (Spotlight's Opening,
  Suggestions, Files, Actions; drag to the notch; up to the top) keep what each user had saved. Named
  Spotlight sizes became sliders, a saved name becoming its value. *Asked for; nobody's Mac should
  change by itself because a row is gone.*
- **2026-10-31 21:30** — The anchored window's name and Release are always beside the notch; a tab at
  the window's top, shown by the pointer, raises the picture by the old bar's 22 pt and drags back down
  (`ni2.anchor.raised`). A saved "under the window" is not carried over. *Asked for; without the way
  back down the raise could not be undone.*
- **2026-10-31 21:30** — The Now Playing width slider moves each ear by −10…+20 % of its own width
  (34–46 pt on a 32 pt notch), not of the whole pill: 10 % of the pill would put the cover on the notch.
  The cover and bars keep their size. *The request's "10 % in, 20 % out" read so; to change: `nowPlayingWidthRange`.*
- **2026-10-31 21:30** — Update checks are fixed at twice a day, the old setting removed. *Asked for.*
- **2026-10-31 00:40** — Replace macOS Spotlight on: the app list, every icon and the read lists stay
  in memory until the app quits (the lists are read again at an opening over 30 min after the last);
  off: all of it goes, the disk apps and Siri's pictures too; on again: read ahead again. *Asked for.*
- **2026-10-30 23:40** — Of Settings only General is built ahead and kept; every other page, Widgets
  too, is built when the user goes to it and let go a minute after they leave it, also with Settings
  open (`unkeptPagesLinger`). *Asked for; replaces the 30 s after closing and the kept Widgets.*
- **2026-10-30 23:40** — A reopen with Siri AI in front counts only from Finder, the Dock or
  Spotlight. *The sender check never matched: every reopen's sender read "unknown" (helpers and gone
  processes are no `NSRunningApplication`), so Siri AI's reopens opened Settings on a tester's Mac.*
- **2026-10-15 20:45** — Settings opened without a page (the gear, the menu, `settings`) opens on
  General, not on the page it was closed on; links to a page still go there. *Asked for.*
- **2026-10-15 19:30** — Window Anchor's live copy runs at the screen's rate (60 at least) and stays
  on every space, over full-screen apps too; there its app is not brought forward by a click. A frame
  the same as the shown one (the whole frame compared) is left out. Over a full-screen app, while
  only unchanged frames come, the stream is asked for 10 a second, the full rate at the first change.
  *Asked for. The real window cannot join a full-screen space (SIP blocks the private calls), only
  our copy can. The copy fed itself through the window server (60 frames a second of a still
  window): 2.0 mW at rest instead of ~33. A window on another space is sent 60 a second, changed or
  not: 80.7 → 36.7 mW with the quiet rate, its first change still on screen in ~16 ms.*
- **2026-10-15 18:40** — With "Replace macOS Spotlight" off, nothing of Siri is read ahead or kept:
  the app list, the gallery's icons and the lists go 10 s after Siri closes, and at once when the
  setting is turned off. *Asked for: Siri is not opened then (34 → 26 MB after a use, 23 → 18 MB
  after launch); an opening costs more (~0.4–0.5 J).*
- **2026-10-15 17:05** — About, Spotlight and Live Activities are built only when the user goes to
  them in Settings, and let go once Settings has closed; General and Widgets are built ahead and
  kept (`IslandSettingsPane.isKept`). *Asked for, to get under 150 MB at rest (186 → 136–141 MB);
  going to those pages costs ~1 J more than when they were kept.* They stay 30 s after Settings
  closes (`unkeptPagesLinger`): closed to look at the island and opened again, they are there at once.
- **2026-10-15 04:20** — The report's energy, CPU and wakeups set against the reference (and sent
  as `metric_powerMW`, `metric_recentPowerMW`, `metric_cpuPercent`, `metric_wakeupsPerSecond`) are
  the stretches at rest: no change of the island in them, no report collected. The report still
  shows since launch and the last hour as they were. *Measured since launch, every report of a Mac
  in use read as tens of times the idle reference (Sentry NOTCHISLAND-10/Z/V/12 on both Macs).*
- **2026-10-15 03:30** — Siri AI is read only inside its conversation view (`innerChatSessionView`,
  found once, kept while it answers to its identifier), and the clipboard is looked at every thirty
  seconds once nobody has typed or clicked for ten minutes (the list looks again as it shows).
  *A whole-window walk was ~900 Accessibility calls every 300 ms during an answer; at rest the look
  was the app's only wake-up (rest −17 % against 0.8.6). Skipping file searches narrower than an
  empty one was measured and dropped: no difference.*
- **2026-10-14 21:40** — No message to another process waits on the main thread: Siri AI's
  Accessibility walks (`SiriHandoff`, `@concurrent`, 1 s per read) and the pasteboard's change count
  (`PasteboardWatch`, a queue of its own) moved off it. Settings is built ahead only after a calm
  that doubles with each memory warning in six hours (5 min → 1 h). Diagnostics leave out readings
  taken while the island was in use, and what was said to Siri AI is no app search.
  *Gergő's Mac (October 13–14): App Hangs in `SiriHandoff.submit` and `ClipboardHistory.check`;
  Settings built and given up three times (~5 J each); "unusual behaviour" for clicking Settings.*
- **2026-10-14 17:50** — On Liquid Glass, grey widget texts and own-colour texts low in contrast with
  the glass (WCAG < 4.5) get a 100 % black/white 0.5-pt sharp edge (`ClearTextEdge`), drawn by the
  text itself (`ClearTextEdgeRenderer`: offset glyphs in one layer, the glyphs cut out of it). *Eight
  view copies per text made the island lag, and showed through see-through grey (heavy black letters).*
  The page picker is made anew when a page's symbol changes (`PickerLook`), as when its colour does.
- **2026-10-14 17:20** — The macOS default wallpaper's resting frame ships with the app
  (`Support/Wallpapers`, 1800 px, dark and light) and is the previews' desktop where the video is not
  downloaded (`WallpaperSource.systemDefault`; `NI_WALLPAPER=bundled` to see it). *The system's own
  preview, the fallback before, is 214 × 130 px: blurred and pixelated on the widget studio's stage
  (a tester's M5 MacBook Pro).*
- **2026-10-14 17:10** — System grows into Fan Control's graph and dials (asked for): from two rows and
  150 pt of room (timer size) its loads are a graph made on Fan Control's code (`LoadGraph` on
  `FanGraphLayers`, reach 10 s–10 min on the timer's ruler, percentages as the battery chart's) and,
  switched on, `ReadingDial`s (memory in GB, two decimals); GPU is IOKit's "Device Utilization %",
  read only while shown. Dial/graph texts and lines follow the colour scheme (black in Light Mode).
  *One graph code for both widgets; widgets saved before (version < 5) get the graph switched on.*
- **2026-10-14 16:20** — Siri's answer is shown as Siri lays it out (`SiriReplyReader` → `SiriBlock`s →
  `SiriAnswerView`): paragraphs with its semibold runs and links (tapped: pressed in Siri AI), source
  chips, file/app cards with Siri's own icons (opened by name through the file search), a photo grid,
  a message card, its buttons. The answer room is as tall as the answer (measured, 8-pt steps) up to
  55 % of the screen. *Siri AI hands over no pictures but icons through Accessibility: a picture of a
  thing is Wikipedia's for its title (only the title is sent), a photo is found in the library by the
  minute Siri reads out (Photos permission asked from the answer).*
- **2026-10-14 15:35** — "Use Siri AI" asks the system's Siri AI unseen and shows its answer in the
  island (`SiriHandoff`): all through Accessibility with Siri AI hidden and never in front — its
  window's New Conversation button, the question set into the Ask Siri field and read back,
  `AXConfirm`, the prompt seen in the conversation (else once more), the reply read as it comes;
  Siri's buttons mirrored in the island and pressed in Siri AI. *Dropped on the way: `siri://` and
  `spotlight://` carry no question; the Spotlight bar takes no synthetic keys; typing into Siri AI's
  window needed it in front — AppKit then pulled its window on screen however far it was moved, and
  handed the front to another app. Reopens NotchIsland gets during a handoff are ignored.*
- **2026-10-14 14:05** — Two fingers sideways are back/forward: in Siri out of a suggestion and into
  the last one (`swipeBack`/`swipeForward`), in Settings a browser-like history of page + Customize
  (`SettingsHistory`); not where something under the fingers scrolls sideways. *Asked for.*
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
