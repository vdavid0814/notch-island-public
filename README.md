# NotchIsland

Turns the MacBook notch into a Dynamic-Island-style surface made of Liquid Glass.
Rest the pointer on the notch and it grows into a panel; music, timers, battery
events, volume/brightness and dropped files live there the rest of the time.

<p align="center">
  <img src="docs/NotchIsland.png" width="220" alt="NotchIsland">
</p>

<h2 align="center">
  <a href="https://github.com/vdavid0814/notch-island-public/releases/latest/download/NotchIsland.dmg">⬇&nbsp;&nbsp;Download NotchIsland v0.4 (.dmg)</a>
</h2>
<p align="center">
  <sub>Latest version · macOS 27 · MacBook with a notch (Apple silicon) · <a href="#download">How to install</a></sub>
</p>

For older versions, see the **[Releases page](https://github.com/vdavid0814/notch-island-public/releases)**.

Swift 6, SwiftUI, macOS 27.

---

## What's new in v0.4

An equalizer that follows the music, Siri's clipboard history, a Fade style like the iPhone's
Siri, the app's own icon — and about half the memory.

**Now Playing**
- **The equalizer follows the music.** The five bars beside the notch — bass on the left, treble on the right — move with what is actually playing, in the cover's colours, as tall as the cover opposite them; neighbouring bars lift each other a little. macOS asks once for **System Audio Recording**: the sound is only measured, never recorded or kept. Without the permission (or in a quiet intro) the bars breathe as before.
- With the Fade style, the compact pill's edge no longer glows for ~3 s after the island closes into it.

**Siri**
- **Clipboard history (⌘4):** the last 50 copied texts, kept on this Mac only; texts that password managers mark as concealed are never kept. Return pastes the selection where you were typing. It can be switched off in Settings ▸ Siri.
- Lists are exactly as tall as their rows (up to the list height) and do not rubber-band when everything fits.
- The app gallery no longer jumps to the bottom while you scroll with the pointer over it.

**Look**
- **Fade** fades like the iPhone's Siri: black through about two thirds of the island, easing slowly out, clearing along the sides and the bottom in a mild V, with the glass's own edge light.
- A much fainter text halo on the see-through styles.
- NotchIsland has its own icon (Finder, the Dock, the disk image).

**Energy and memory** (measured overnight on a MacBook Air M5, the release build)

| | v0.3.2 | v0.4 |
|---|---|---|
| At rest | 26–28 MB | 19–21 MB |
| At rest after using Settings, Siri and the rest for hours | 82–91 MB | 42–44 MB |
| Volume / brightness key (peak) | 72–122 MB | 21–30 MB |
| AirPods / timer-finished banner (peak) | 73–95 MB | 30–32 MB |
| Opening Settings (peak) | 158–197 MB | 71–84 MB |
| At rest with music playing | 1.0–1.25 % CPU, Energy Impact 1.7 | 0.9–1.0 % CPU, Energy Impact 1.3–1.4 |

- The volume and brightness sliders, symbol animations (the volume symbol, the AirPods and timer bounces) and the native controls in Settings no longer set up ~40 MB of graphics memory each time they appear.
- Freed memory goes back to the system: after Settings or Siri close, the app returns to about where it was.
- The wallpaper pictures in Settings are decoded at the size they are shown, in the form the system displays directly: Settings ▸ General open 95 → 57 MB.
- The equalizer's audio analysis wakes the Mac half as often.
- Settings ▸ Widgets left open: ~3.5 % CPU (was ~10 %).
- No leaks: hours of opening, closing and resting, a hundred opens in a row, memory flat to 0.1 MB. Energy Impact stays below 50 in every animation (opening the panel ~28, Siri's app gallery ~45).

**Known issues**
- Opening and closing the island costs about the same CPU as in v0.3.2.
- Settings ▸ Widgets left open uses ~3.5 % CPU: its live widget previews redraw every second.
- Switching between Settings pages can reach ~84 MB for a moment.

---

## What's new in v0.3.2

Browser playback that resumes reliably, a preview-wallpaper picker, widget element sizes
that always differ, timer and Siri fixes, and less memory after Settings.

**Now Playing**
- **Safari (and other browsers) resume after a long pause.** A browser suspends a background tab that has been paused for a few minutes, and the page then ignores every Now Playing command (play, toggle, seek, even the keyboard's play key). An unanswered play is now sent again with the browser brought forward for a moment; the focus then returns to the app you were in.
- Play and pause from the island are always the explicit command, never a toggle, so a paused video is never "paused" again.
- **Next and previous work on web videos.** When a page does not handle them, next goes to the end of the video (the page's autoplay moves on) and previous back to its start.
- The equalizer bars beside the notch take a faint tint of the cover's colour.

**Widgets**
- **Small, Medium and Large always look different.** Text is measured against the room it has; where the room caps it, Large takes all of it and Medium and Small a step and two below. Rings (battery, volume, brightness, CPU/RAM) and the percentage and icon inside them follow their element sizes too.
- The widget search in Settings is the system's own search field.

**Timer**
- Dragging the minutes past 0 no longer leaves the seconds at 0:01; 0:00 can be passed through and cannot be started.
- The ruler reads its value from the scroll itself: no jumps back while scrolling, a haptic on every step, and it starts on its value when the island reopens.

**Siri**
- Typing a suggestion's name ("application", "files", "shortcuts") lists it first, so Return opens it.
- The window is as tall as the results it shows, up to the full list.

**Settings**
- **Preview Wallpaper** (General): your own desktop, the macOS default wallpaper in dark or light, or a black-and-white test pattern — used by every picture in Settings and by the widget studio. "Your Desktop" now shows the wallpaper that is really on screen, including the system's moving wallpapers.
- The pictures of each setting show a real menu bar, the notch and the chosen wallpaper.
- The widget studio always shows the whole island.
- The title bar reads just "Settings".

**Memory**
- After Settings closes: ~57–88 MB instead of ~119 MB. The decoded wallpapers are released, Settings runs in a view graph of its own that goes with it, and freed memory is handed back to the system after Settings and Siri close.

**Known issues**
- Settings ▸ Widgets left open uses ~10 % CPU in this build (measured over 20-second windows); being investigated.
- Opening and closing the island costs about the same CPU as in v0.3.1.

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
   volume/brightness HUD), **Automation** for Music or Spotify (Now Playing) and
   **System Audio Recording** (the equalizer that follows the music).

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
| The equalizer following the music | System Audio Recording (measured only, never recorded) | the bars breathe |

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
