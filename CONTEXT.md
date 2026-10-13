# CONTEXT.md

All the context on the app in one page. Where files live: [AGENTS.md](AGENTS.md). Why things are
as they are: [DECISIONS.md](DECISIONS.md). The details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## What it does

**NotchIsland** turns the MacBook's notch into a Dynamic-Island-style surface made of Liquid Glass.

- **At rest** it is exactly the notch — nothing of it covers a menu-bar item.
- **Compact / banners**: music playing, timers and stopwatches, screen recording, battery and charger
  events, volume and brightness changes hug the notch.
- **Hover to open**: rest the pointer on the notch and it grows into a panel of pages (Home, Battery,
  Shelf and the user's own) filled with **widgets** — Control Center controls, levels, Now Playing,
  clocks, calendar, battery charts, System stats, Chip Temperature, Fan Control (MacBook Pro), …
- **Shelf**: drop files on the notch to keep them there.
- **Spotlight** (the Assistant): search apps, files, actions and the clipboard from the notch.
- **Settings** opens inside the island: appearance (Liquid Glass / Fade / Black), size, widgets with
  a per-widget editor (Customize), the top bar, permissions, updates, What's New.
- **Updates in place** (Settings ▸ About ▸ Update Now), keeping the user's permissions.
- **Reports** (opt-in): crashes and errors to Sentry, usage to Mixpanel, bug reports/feature requests
  to Discord.

## Who it's for

- **MacBook owners with a notch** (Apple silicon, macOS 27) who want the notch to be useful and the
  Mac to feel like an iPhone's Dynamic Island.
- People who care about **looks**: it must feel native — Apple's glass, concentric corners, system
  controls, nothing overflowing — and smooth: dropped frames are noticed at once.
- People on **battery**: it runs all day, so its energy use (Activity Monitor's Energy Impact) is
  watched as closely as its look.
- Distributed as a free **DMG from GitHub releases** (vdavid0814/notch-island-public); users talk to
  the developer through Discord and the in-app reports.

## How it works

- **Swift 6 + SwiftUI + AppKit**, one SwiftPM package: `NotchIsland` (executable) and `NotchIslandKit`
  (everything else); everything on the main actor unless marked `nonisolated`.
- **The window**: a borderless, non-activating `NSPanel` above the menu bar, on every Space and over
  full-screen apps. Its frame is a "stage" that grows before a transition and shrinks back after.
- **One-way data flow**: system services push into feature stores → `IslandController` resolves the
  presentation (`idle | compact | banner | expanded`) → `IslandModel` applies it → views read stores.
  The presentation carries only the *kind* of content, so a volume step never re-stages the window.
- **Energy**: no repeating timers; animations on the render server (Core Animation); Settings built
  once ahead of time in its own window and frozen while closed; deferred work on the efficiency cores.
- **System hooks**: MediaRemote (Now Playing), CoreAudio, IOKit/SMC (battery, temperature, fans via a
  privileged helper), event taps (media keys), ScreenCaptureKit, EventKit, Spotlight queries.
- **Build & ship**: `Scripts/build.sh` → `build/NotchIsland.app`; `Scripts/make-dmg.sh` →
  `NotchIsland.dmg`, signed by the one pinned certificate; release notes in README.md and in-app.
- **Testing**: Swift Testing suites + widget snapshots (`Scripts/test.sh`), `notchisland://demo/…`
  URLs to show any state, `Scripts/perf/` to measure energy and frame rate.

## Where it stands (2026-10-13)

- Latest release: **0.8.5.1.1 (45)**. Work happens on `widgets-reset`; releases also go to `main`.
- Open energy items: the panel's page picker is ~30 % of every notch opening; Settings' first open
  after launch, Customize and the widget studio's clicks are still costly (see docs/ENERGY-LOG.md).
