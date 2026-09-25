# NotchIsland

Turns the MacBook notch into a Dynamic-Island-style surface made of Liquid Glass.
Rest the pointer on the notch and it grows into a panel; music, timers, battery
events, volume/brightness and dropped files live there the rest of the time.

**Current version: v0.3.1** (the energy and memory update of v0.3).
Swift 6, SwiftUI, macOS 27.

> v0.3.1 fixes the extra battery use and the memory peaks of v0.3 — nothing looks or
> behaves differently. Older builds are on the [Releases](https://github.com/vdavid0814/notch-island-public/releases) page.

---

## What's new in v0.3.1

An energy and memory update. Nothing looks or behaves differently; it just costs far
less. Measured on a MacBook Air (M5) with music playing, CPU as a share of one core
over 30-second windows.

**Memory — peaks stay below ~130 MB everywhere**
- Opening the panel peaks at ~40 MB instead of ~145 MB; Settings at ~100 MB instead of
  ~420 MB; the Siri app gallery at ~50 MB instead of ~285 MB; banners at ~40–80 MB.
- The cause: Liquid Glass drawn in the island's own outline was rasterised again for
  every frame of an animation. The glass is now drawn in a shape the system renders
  directly, and the exact outline comes from a clip.
- A 4.7-hour test (music playing, screen locked) stayed flat at 23 MB: no leaks.

**CPU**
- Opening and closing the panel costs less than half as much as before (about 0.35 s of
  CPU for open + close instead of ~0.9 s): springs stop once they are visually settled
  instead of running on for another second, and a morph animates only the island's
  outline, so the content inside is no longer laid out again on every frame.
- Settings ▸ General at rest: ~0.03 % instead of ~15 % (the animation-length preview
  now runs on Core Animation).
- Settings ▸ Widgets at rest: ~1.8 % instead of ~2.5 % (the live preview updates on its
  own).
- The open panel: the Now Playing progress line moves on Core Animation, and the
  System widget no longer animates every reading (it kept the panel redrawing).
- Idle with music: ~0.00 %; with the screen locked: ~0.002 %.
- The hover diagnostic (`demo/hover`) no longer opens and closes the island in a loop.

---

## What's new in v0.3

**Settings, rebuilt inside the notch**
- Settings grows out of the notch as a large page: sidebar of Liquid Glass, a soft
  black-to-grey fade, and an ⓘ next to every option that explains it on hover.
- Settings that change the look show small pictures: surface style, island size,
  a live preview of the open/close animation, the volume style, AirPods, battery.

**Look**
- Island surface: **Liquid Glass**, **Black** or **Fade** (black at the notch fading
  into glass). Switching between them no longer freezes the app.
- Five sizes: Extra Small, Small, **Standard** (default), Large, Extra Large.
- Header: native tab bar for Home / Shelf / Timer, a menu-bar-style battery icon.
- Widgets sit closer to the island's edge, with the same gap at the side and bottom.

**Widgets**
- Arrange the Home page on a live copy of your desktop: drag to move, drag a corner
  to resize (smoother now), arrow keys, ⌘-click several widgets to change their
  colour, background and opacity together.
- Every widget: colour, background (None / Plate / Colour / Artwork) with an opacity
  slider; one-cell widgets are always a single circle.
- Labels adapt to every size instead of being cut to “…”.
- **New widgets:** Date & Time, System (CPU and memory), and Control Center style
  controls — Calculator, Voice Memos, Screenshot, Notes, Lock Screen, Focus, Clock,
  Home — next to Wi-Fi, Bluetooth, AirDrop, Dark Mode, Night Shift, Keep Awake,
  Microphone.
- Now Playing: a wide, thick progress line with larger times; neutral buttons that
  can each get their own colour and opacity.
- Timer: set hours and seconds too, a cleaner ruler when switching units.

**Live Activities**
- **AirPods connected:** picture, name, and the battery of the left and right
  earbud and the case. It covers macOS's own AirPods card (or waits for it, or
  stays away — your choice).
- Volume and brightness: **Minimal** style beside the notch (default) or the banner
  under it; how long every notice stays up is adjustable.

**Siri in the notch**
- Many new options: shortcut (⌘/⌥/⌃ Space), swipe down on the notch to open,
  search delay, matching (word starts / anywhere / fuzzy), results per kind, which
  folders to search, app gallery columns / rows / order, answer length, web search
  engine, window width and list height.
- Inside Applications, Files or Actions a click on the field goes back.

**Performance**
- Settings used to take up to ~700 MB of memory while opening; now ~100 MB.
- Previews and background checks only run while they are on screen.

**New defaults:** hover delay 100 ms, close delay 100 ms, animation 400 ms,
volume/brightness Minimal for 1.5 s, AirPods card 5 s.

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

Settings open in the notch (menu bar icon ▸ Settings…, the gear in the island,
or `notchisland://settings`).

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
SwiftUI `repeatForever`; the equaliser and the Now Playing progress line are Core
Animation on the render server. Animations move shapes, never frames, and Liquid Glass
is only drawn in shapes the system renders directly.
The panel is ordered out while the screens sleep or the session is locked.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it fits together.

---

## Third-party

The downloadable app bundles [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
(BSD 3-Clause License, © 2025 Jonas van den Berg and contributors) to read Now
Playing from browsers and video apps; its license is inside the app at
`Contents/Resources/MediaRemoteAdapter/LICENSE`.
