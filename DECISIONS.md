# DECISIONS.md

Decisions that shape the code, newest first, with when they were made. Add a line when you make
or learn one; never rewrite an old one — add a newer line that replaces it.

Format: `YYYY-MM-DD hh:mm` — the decision. *Why.*

---

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
