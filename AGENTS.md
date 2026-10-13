# AGENTS.md

Where everything lives, and what an agent may and may not do here.
What the app is and who it is for: [CONTEXT.md](CONTEXT.md). Why things are the way they are:
[DECISIONS.md](DECISIONS.md).

## Where everything lives

```
notch app v0.8/
├── Package.swift                  ← SwiftPM: NotchIsland (exe) + NotchIslandKit (lib) + tests; Swift 6, macOS 27
├── Sources/
│   ├── NotchIsland/               ← one line: NotchIslandApp.main()
│   └── NotchIslandKit/
│       ├── App/                   ← composition root (AppModel), AppDelegate, notchisland:// URL commands, demos
│       ├── Island/                ← the island's brain: presentation, resolver, layout, controller
│       │   └── Window/            ← the NSPanel "stage", hit testing, notch metrics, pointer monitor
│       ├── DesignSystem/          ← IslandGlass (the material), shapes, metrics, motion
│       ├── Views/                 ← SwiftUI: Compact/, Banner/, Expanded/, Widgets/, Settings/, Assistant/
│       ├── Features/              ← one folder per feature: Media, Levels, Power, Shelf, Timers, Widgets,
│       │                            Thermals (fans), Assistant (Spotlight), Diagnostics, Telemetry, …
│       ├── Settings/              ← Preferences ("ni2." UserDefaults keys), Settings window, widget editor
│       └── System/                ← permissions, haptics, launch at login, logging
├── Tests/NotchIslandKitTests/     ← Swift Testing suites; Snapshots/ = widget reference images
├── Support/                       ← Info.plist, entitlements, icon, fan helper plist, Settings pictures
│                                    + git-ignored secrets (see "Not allowed")
├── Scripts/
│   ├── build.sh / run.sh          ← build (and relaunch) build/NotchIsland.app
│   ├── test.sh                    ← the test suite (snapshots in a process of their own)
│   ├── logs.sh                    ← the app's log
│   ├── make-dmg.sh                ← release image; refuses a wrong signer or missing report addresses
│   ├── settings-pictures.sh       ← retakes the island photographs used in Settings
│   └── perf/                      ← energy / FPS measuring tools (README.md explains them)
├── docs/
│   ├── ARCHITECTURE.md            ← how the island, window, glass and Settings work — read this first
│   ├── OPTIMIZATION-PLAYBOOK.md   ← how energy/FPS work is done here
│   ├── ENERGY-LOG.md              ← measured numbers, before and after
│   └── PERFORMANCE-TESTS.md       ← the tests behind those numbers
├── Vendor/                        ← MediaRemote adapter (git-ignored, Scripts/vendor-mediaremote.sh)
└── README.md                      ← user-facing: download link + "What's new" for every release
```

## Allowed

- **Edit the code**, the tests and the docs.
- **Build and run**: `Scripts/build.sh`, `Scripts/run.sh` (release by default; `CONFIG=debug` for debug).
  Measure energy on release builds only — a debug build costs about 3× in Settings.
- **Run the tests**: `Scripts/test.sh` (pass `--filter <Suite>` for one suite).
- **Drive the running app** through its own URLs (`notchisland://demo/…`, `notchisland://settings/…`)
  and the tools in `Scripts/perf/`; take screenshots with `screencapture` to check what changed.
- **Commit on the working branch** (`widgets-reset` at the moment) when asked.
- **Simulate hardware/state with env switches**: `NI_DEMO_FANS=1`, `NI_POWER=battery|charger`,
  `NI_APPEARANCE`, `NI_TRACE=1`. Check they reached the process (`ps eww <pid>`) — zsh does not split
  `set -- $v`.

## Not allowed

- **Touch secrets.** Never read out, print, commit or send: `Support/telemetry.json`,
  `Support/diagnostics-webhook*.txt|json`, `Support/discord-bot-token.txt`, `.sentryclirc`,
  `Support/reports/`. Use `Support/telemetry.example.json` for shape.
- **Push to `main` or publish a release** (GitHub release, DMG, README download link) without the
  user's explicit go-ahead for that release.
- **Sign a release with any certificate but the pinned one** (`Support/release-requirement.txt`), or
  bypass `make-dmg.sh`'s checks (`ALLOW_OTHER_SIGNER`, `ALLOW_NO_REPORTS` are for test images only).
  A different signer makes every user lose their permissions on update.
- **Change the real output volume in tests** — the user's music plays during test runs. Use demo routes.
- **Build ad-hoc test binaries that touch protected folders** (Desktop, Documents, Pictures…): their
  privacy prompt blocks the app's own file searches until someone answers it. Measure inside the app.
- **Save energy by dropping frames or updates.** Fewer FPS is a regression here, whatever the meter says.
- **Draw mock-ups of the island** for Settings; retake real photographs (`Scripts/settings-pictures.sh`).

## Before you call it done

- Tests pass (`Scripts/test.sh`), or say exactly which fail and whether they failed before.
- UI change: seen in the running release build (screenshot), not only compiled.
- Energy change: old vs new measured back to back (Activity Monitor's Energy Impact, or
  `Scripts/perf/`), numbers added to `docs/ENERGY-LOG.md`.
- A decision worth remembering: one line in [DECISIONS.md](DECISIONS.md).
