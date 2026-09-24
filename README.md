# NotchIsland

Turns the MacBook notch into a Dynamic-Island-style surface made of Liquid Glass.
Rest the pointer on the notch and it grows into a panel; music, timers, battery
events, volume/brightness and dropped files live there the rest of the time.

Version 2 is a from-scratch rewrite: Swift 6, SwiftUI, macOS 27.

---

## Download

**[⬇ Download NotchIsland (.dmg)](https://github.com/vdavid0814/notch-island-public/releases/latest/download/NotchIsland.dmg)**

1. Open the downloaded `NotchIsland.dmg`.
2. Drag **NotchIsland** onto the **Applications** folder.
3. Open NotchIsland from Applications (or Spotlight).
4. The first time, macOS says it cannot verify the app, because it is not
   notarized by Apple. Click **Done**, then open **System Settings → Privacy &
   Security**, scroll down and click **Open Anyway** next to NotchIsland, and
   confirm. This is needed only once.
5. Grant what it asks for: **Accessibility** (for the ⌘Space Siri and the
   volume/brightness HUD) and **Automation** for Music or Spotify (Now Playing).

Needs a MacBook with a notch (Apple silicon) and **macOS 27** or later.
All releases: [Releases](https://github.com/vdavid0814/notch-island-public/releases).

---

## Build and run

```bash
./Scripts/run.sh
```

Builds the package, assembles `build/NotchIsland.app`, signs it with the first
Apple Development identity in your keychain (a stable identity keeps Accessibility
grants across rebuilds; without one it signs ad hoc), replaces a running instance
and launches it.

| Script | Does |
|---|---|
| `Scripts/build.sh` | build + assemble + sign (`CONFIG=release` for a release build) |
| `Scripts/run.sh` | build, quit the old instance, launch |
| `Scripts/test.sh` | `swift test` (Swift Testing) |
| `Scripts/logs.sh` | stream the app's log |
| `Scripts/vendor-mediaremote.sh` | optional: vendor ungive/mediaremote-adapter for Now Playing from every player |

The scripts use the Xcode 27 beta toolchain through `DEVELOPER_DIR`, because
`xcode-select` on this machine points at the Command Line Tools. Override it if
your setup differs.

To read persisted logs: `/usr/bin/log show --last 5m --predicate 'subsystem == "com.davidvarga.notchisland"'`
(in zsh, `log` without the path is a shell builtin).

---

## What it does

| State | When | Looks like |
|---|---|---|
| **Idle** | nothing to show | just the notch; an invisible hover target, no glass |
| **Compact** | a timer, stopwatch or music is running | glass hugging the notch, never taller than it: artwork + equaliser, or the countdown |
| **Banner** | volume/brightness key, charger plugged/unplugged, low battery, timer finished, a file drag somewhere on screen | drops just below the notch, auto-dismisses; volume/brightness have a live slider |
| **Expanded** | hover (≈0.2 s), click, menu or URL | the panel: Home (Now Playing + timer + shelf), Shelf, Timer |

* **Now Playing** — Music and Spotify out of the box (broadcast notifications +
  in-process AppleScript with timeouts); every player with the optional adapter.
* **Volume & brightness** — replaces the system HUD (needs Accessibility; it asks
  once). Keys it cannot act on (HDMI outputs, external displays) are left alone.
* **Battery** — plugged in / unplugged / fully charged / 20 · 10 · 5 %, each once.
  Optimised-charging holds say "Plugged In", never "Charging". Desktop Macs show
  no battery UI.
* **Shelf** — drag files onto the notch; they persist, drag back out anywhere,
  AirDrop or share them.
* **Timers** — countdown (with a finish banner, sound and haptic) and stopwatch.

Settings live in a normal macOS window (menu bar icon ▸ Settings…, the gear in
the island, or `notchisland://settings`).

---

## Look

The island wears one Liquid Glass material everywhere — the same glass as the
CAD app: `Glass.clear.tint(.black.opacity(0.5))`, `.interactive()` under
controls, the accent colour for active controls, fully clear glass for the moving
selection thumb. The island window is pinned to the dark appearance, like the CAD
app's floating UI. All of it is defined in one place:
[`DesignSystem/IslandGlass.swift`](Sources/NotchIslandKit/DesignSystem/IslandGlass.swift).

---

## Scripting

```bash
open "notchisland://open"                 # open (optionally ?page=home|shelf|timer)
open "notchisland://close"
open "notchisland://pin"
open "notchisland://media/toggle"         # play | pause | toggle | next | previous
open "notchisland://timer?minutes=25"
open "notchisland://timer/cancel"
open "notchisland://stopwatch"
open "notchisland://settings"
```

Demo / diagnostics routes (inject state without touching the system):
`demo/media`, `demo/charging`, `demo/unplug`, `demo/low`, `demo/volume?level=0.6`,
`demo/brightness?level=0.4`, `demo/timerdone`, `demo/drop`, `demo/shelf`,
`demo/hover?inside=1|0`, `demo/state` (logs the stage geometry), `demo/reset`.

---

## Permissions

| Feature | Needs | Without it |
|---|---|---|
| Island, timers, shelf, battery, showing volume/brightness | nothing | — |
| Replacing the system volume/brightness HUD | Accessibility | the system HUD stays |
| Music / Spotify artwork and position | Automation (per app) | title/artist still appear; Settings shows the status |

---

## Energy

Nothing polls: IOKit run-loop source for power, CoreAudio property listeners,
DisplayServices notifications, distributed notifications from the players,
NSWorkspace notifications, and NSEvent monitors only while they are needed. No
SwiftUI `repeatForever`; the equaliser is Core Animation on the render server.
The panel is ordered out while the screens sleep or the session is locked.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it fits together.

---

## Third-party

The downloadable app bundles [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
(BSD 3-Clause License, © 2025 Jonas van den Berg and contributors) to read Now
Playing from browsers and video apps; its license is inside the app at
`Contents/Resources/MediaRemoteAdapter/LICENSE`.
