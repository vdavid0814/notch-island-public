import AppKit
import SwiftUI

/// Runs `notchisland://demo/…`: injects fake state so every island presentation can be shown and
/// screenshotted on demand, and takes all of it back out on `demo/reset`.
///
/// It remembers exactly what it injected (shelf items it added, the countdown it started, whether
/// fake level readings are in place) so a reset restores the real state without touching anything
/// the user did in between.
@MainActor final class DemoDirector {
    /// How long the fake drag of `demo/drop` stays "in flight".
    static let dropDuration: Duration = .seconds(4)
    /// `demo/timerdone` starts a countdown this short and lets it finish for real.
    static let timerDuration: TimeInterval = 3

    /// Read-only system images: they exist on every Mac and, unlike `~/Desktop`, reading them
    /// triggers no privacy prompt.
    private static let picturesDirectory = URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true)

    private var dropTask: Task<Void, Never>?
    private var isDropActive = false
    private var demoCountdown: CountdownState?
    private var demoShelfIDs: Set<ShelfItem.ID> = []
    private var injectedLevels = false
    /// `demo/picture`: the drawn desktop under the island, and the style and size to put back.
    private var pictureScene: (backdrop: NSWindow, desktop: PictureDesktopChoice, restore: PictureRestore)?

    func run(_ command: DemoCommand, model: AppModel) {
        switch command {
        case .media:
            model.media.injectDemo(Self.demoTrack(), playing: true)
        case .charging:
            model.power.injectDemo(.demo(level: 76, charging: true, minutes: 72), event: .connected)
        case .unplug:
            model.power.injectDemo(.demo(level: 76, charging: false, minutes: 312), event: .disconnected)
        case .low:
            model.power.injectDemo(.demo(level: 9, charging: false, minutes: 38), event: .low(threshold: 10))
        case .volume(let value):
            injectedLevels = true
            model.levels.injectDemo(.volume, value: value)
        case .brightness(let value):
            injectedLevels = true
            model.levels.injectDemo(.brightness, value: value)
        case .timerDone:
            model.timers.start(duration: Self.timerDuration)
            demoCountdown = model.timers.countdown
        case .drop:
            beginDrop(model)
        case .shelf:
            addShelfSamples(model)
        case .reset:
            reset(model)
        case .hover(let inside):
            model.controller.simulatePointer(inside: inside)
        case .state:
            model.logIslandState()
        case .segments:
            Self.logSegments()
        case .airPods:
            model.airPodsConnected(.demo)
        case .airPodsMode(let mode):
            model.airPodsModeChanged(name: AirPodsInfo.demo.name, to: mode)
        case .siriApps:
            model.controller.openAssistant()
            model.assistant.open(.applications)
        case .siriClipboard:
            model.controller.openAssistant()
            model.assistant.open(.clipboard)
        case .siriType(let text):
            model.controller.openAssistant()
            Task { @MainActor in
                for index in text.indices {
                    try? await Task.sleep(for: .milliseconds(120))
                    model.assistant.query = String(text[...index])
                }
            }
        case .surface(let style):
            withAnimation(.spring(duration: 0.25)) { model.preferences.glassStyle = style }
        case .picture(let desktop, let style, let scale):
            showPicture(desktop: desktop, style: style, scale: scale, model: model)
        case .activityPicture(let desktop, let style, let activity):
            showActivityPicture(desktop: desktop, style: style, activity: activity, model: model)
        case .pictureEnd:
            endPicture(model)
        case .freeze(let time):
            LeanSpring.frozenTime = time
        case .anchorTarget(let on):
            model.anchor.demoTarget(on)
        case .recording(let on):
            model.recorder.demo(on)
        case .update(let on):
            model.updater.injectDemo(on)
        case .crash:
            guard UserDefaults.standard.bool(forKey: DiagnosticsCenter.referenceKey) else {
                Log.app.notice("demo/crash ignored: not the developer's Mac")
                return
            }
            Log.app.notice("demo/crash: crashing on purpose")
            Self.crashOnPurpose()
        case .recordingThumbnail:
            // The last movie this run, else the newest "Screen Recording …" where they are saved.
            let folder = ScreenRecorder.saveDirectory()
            let newest = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]))?
                .filter { $0.lastPathComponent.hasPrefix("Screen Recording") && $0.pathExtension == "mov" }
                .max { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            if let url = model.recorder.lastMovie ?? newest {
                model.recordingThumbnail.show(url, display: model.metrics?.displayID)
            }
        }
    }

    /// Called when the app stops: nothing may fire into a stopped model.
    func cancel() {
        dropTask?.cancel()
        dropTask = nil
    }

    // MARK: Settings' pictures

    /// The scene's place on the screen: its top, centred, in the pictures' 16:9.
    static let pictureSize = CGSize(width: 800, height: 450)
    /// The part of it a live activity's picture takes: the notch and a little desktop round it.
    static let activityPictureSize = CGSize(width: 480, height: 160)
    /// Where the scene writes each size's outline (`IslandPhotoGeometry`) for the script to keep.
    static let geometryFile = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "notchisland-picture-geometry.json")

    /// What the scene changes, to put back.
    private struct PictureRestore {
        let style: IslandGlassStyle, scale: IslandScale, levelStyle: LevelHUDStyle
        let levelDuration: Double, powerDuration: Double, airPodsDuration: Double
        let showLevelHUD: Bool, showPowerAlerts: Bool, showNowPlaying: Bool, showAirPods: Bool
    }

    /// The drawn desktop over whatever is on the screen (its menu bar included), under the island:
    /// the glass shows that desktop, nothing of the user's.
    private func beginPictureScene(_ model: AppModel) -> Bool {
        if pictureScene != nil { return true }
        // The island's own screen.
        guard let screen = NSApp.windows.first(where: { $0 is IslandPanel })?.screen ?? NSScreen.main else { return false }
        let size = Self.pictureSize
        let frame = CGRect(x: (screen.frame.midX - size.width / 2).rounded(), y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        let backdrop = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        backdrop.collectionBehavior = [NSWindow.CollectionBehavior.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backdrop.ignoresMouseEvents = true
        backdrop.hasShadow = false
        let choice = PictureDesktopChoice()
        backdrop.contentView = NSHostingView(rootView: PictureDesktop(model: model, choice: choice))
        backdrop.setFrame(frame, display: true)
        let preferences = model.preferences
        pictureScene = (backdrop, choice, PictureRestore(
            style: preferences.glassStyle, scale: preferences.scale, levelStyle: preferences.levelStyle,
            levelDuration: preferences.levelDuration, powerDuration: preferences.powerDuration,
            airPodsDuration: preferences.airPodsDuration, showLevelHUD: preferences.showLevelHUD,
            showPowerAlerts: preferences.showPowerAlerts, showNowPlaying: preferences.showNowPlaying,
            showAirPods: preferences.showAirPods))
        model.isPictureScene = true
        // Every notice stays long enough to be photographed.
        preferences.levelDuration = Preferences.noticeDurationRange.upperBound
        preferences.powerDuration = Preferences.noticeDurationRange.upperBound
        preferences.airPodsDuration = Preferences.noticeDurationRange.upperBound
        preferences.showLevelHUD = true
        preferences.showPowerAlerts = true
        preferences.showNowPlaying = true
        preferences.showAirPods = true
        return true
    }

    /// The desktop under the island (or, for the bare notch, over it too).
    private func placeBackdrop(overIsland: Bool) {
        guard let backdrop = pictureScene?.backdrop else { return }
        backdrop.level = NSWindow.Level(rawValue: IslandPanel.restingLevel.rawValue + (overIsland ? 1 : -1))
        backdrop.orderFrontRegardless()
    }

    private func set(_ style: IslandGlassStyle, model: AppModel) {
        var plain = Transaction()
        plain.disablesAnimations = true
        withTransaction(plain) { model.preferences.glassStyle = style }
    }

    /// Nothing of an earlier picture left in the notch.
    private func clearActivities(_ model: AppModel) {
        model.banners.dismiss()
        model.power.injectDemo(nil, event: nil)
        if injectedLevels {
            injectedLevels = false
            model.levels.endDemo()
        }
    }

    /// The open island, pinned and empty, in `style` at `scale`.
    private func showPicture(desktop: DesktopBackdropStyle, style: IslandGlassStyle, scale: IslandScale, model: AppModel) {
        guard beginPictureScene(model), let scene = pictureScene else { return }
        clearActivities(model)
        scene.desktop.style = desktop
        scene.desktop.activity = nil
        placeBackdrop(overIsland: false)
        set(style, model: model)
        model.preferences.scale = scale
        model.controller.expand(pinned: true, userInitiated: true)
        // Its outline at this size, for the picture that grows the island out of the notch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak model] in
            guard let model, model.preferences.scale == scale else { return }
            let layout = model.layout
            let presentation = IslandPresentation.expanded(model.island.page)
            let size = layout.size(for: presentation)
            var all = (try? Data(contentsOf: Self.geometryFile)).flatMap { try? JSONDecoder().decode([String: IslandPhotoGeometry].self, from: $0) } ?? [:]
            all[scale.rawValue] = IslandPhotoGeometry(
                width: size.width, height: size.height, radius: layout.bottomRadius(for: presentation),
                shoulder: layout.shoulderRadius(for: presentation), notchWidth: layout.notch.width, notchHeight: layout.notch.height)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(all).write(to: Self.geometryFile)
        }
    }

    /// A live activity in the notch, the island closed.
    private func showActivityPicture(desktop: DesktopBackdropStyle, style: IslandGlassStyle, activity: PictureActivity, model: AppModel) {
        guard beginPictureScene(model), let scene = pictureScene else { return }
        clearActivities(model)
        scene.desktop.style = desktop
        scene.desktop.activity = activity
        set(style, model: model)
        if model.island.isPinned { model.island.isPinned = false }
        model.controller.collapse()
        // The bare notch: the desktop over the island, the notch drawn on it.
        placeBackdrop(overIsland: activity == .idle)
        // A made-up track with a drawn cover in every picture but Now Playing's own: none.
        model.media.injectDemo(activity == .nowPlaying ? Self.pictureTrack() : nil, playing: true)
        if activity != .nowPlaying { model.preferences.showNowPlaying = false } else { model.preferences.showNowPlaying = true }
        switch activity {
        case .idle, .nowPlaying:
            break
        case .airPods:
            // As a set connects: its name without an owner's, everything fully charged.
            model.banners.post(.airPods(Self.pictureAirPods), duration: model.preferences.airPodsDuration)
        case .volumeBanner, .volumePill:
            model.preferences.levelStyle = activity == .volumeBanner ? .banner : .pill
            injectedLevels = true
            model.levels.injectDemo(.volume, value: 0.6)
        case .power:
            model.power.injectDemo(.demo(level: 76, charging: true, minutes: 72), event: .connected)
        }
    }

    private func endPicture(_ model: AppModel) {
        guard let scene = pictureScene else { return }
        pictureScene = nil
        clearActivities(model)
        model.media.injectDemo(nil, playing: false)
        let old = scene.restore, preferences = model.preferences
        preferences.glassStyle = old.style
        preferences.scale = old.scale
        preferences.levelStyle = old.levelStyle
        preferences.levelDuration = old.levelDuration
        preferences.powerDuration = old.powerDuration
        preferences.airPodsDuration = old.airPodsDuration
        preferences.showLevelHUD = old.showLevelHUD
        preferences.showPowerAlerts = old.showPowerAlerts
        preferences.showNowPlaying = old.showNowPlaying
        preferences.showAirPods = old.showAirPods
        model.isPictureScene = false
        scene.backdrop.close()
        model.controller.collapse()
    }

    static let pictureAirPods = AirPodsInfo(name: "AirPods", model: .airPodsPro, left: 100, right: 100, chargingCase: 100)

    /// Now Playing's picture: a made-up track, its cover drawn here (nothing of the system's).
    private static func pictureTrack() -> NowPlayingItem {
        let side = 256.0
        let cover = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSGradient(starting: .systemPink, ending: .systemOrange)?.draw(in: rect, angle: -45)
            return true
        }
        let data = cover.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        return NowPlayingItem(title: "Island Lights", artist: "The Notches", album: "Liquid Glass", duration: 214, artworkData: data)
    }

    private func beginDrop(_ model: AppModel) {
        dropTask?.cancel()
        if !isDropActive {
            isDropActive = true
            model.controller.externalDragBegan()
        }
        dropTask = Task { [weak self, weak model] in
            do { try await Task.sleep(for: Self.dropDuration) } catch { return }
            guard let self, let model else { return }
            self.endDrop(model)
        }
    }

    private func endDrop(_ model: AppModel) {
        dropTask = nil
        guard isDropActive else { return }
        isDropActive = false
        model.controller.externalDragEnded()
    }

    private func addShelfSamples(_ model: AppModel) {
        let before = Set(model.shelf.items.map(\.id))
        model.shelf.add(Self.sampleFiles())
        // Only items that were not on the shelf already belong to the demo (add() de-duplicates).
        demoShelfIDs.formUnion(model.shelf.items.map(\.id).filter { !before.contains($0) })
        model.controller.expand(page: .shelf, pinned: false, userInitiated: true)
    }

    private func reset(_ model: AppModel) {
        dropTask?.cancel()
        endDrop(model)
        model.media.injectDemo(nil, playing: false)
        model.power.injectDemo(nil, event: nil)
        model.recorder.demo(false)
        if injectedLevels {
            injectedLevels = false
            // Silent and in place: restarting the level services here used to report the first
            // real reading as an external change, i.e. a volume banner out of a reset.
            model.levels.endDemo()
        }
        if let demoCountdown, model.timers.countdown == demoCountdown {
            model.timers.cancel()
        }
        demoCountdown = nil
        if case .finished = model.timers.countdown {
            model.timers.acknowledge()
        }
        for id in demoShelfIDs {
            model.shelf.remove(id)
        }
        demoShelfIDs.removeAll()
        model.banners.dismiss()
        model.controller.collapse()
    }

    /// A made-up track whose artwork is one of the square desktop-picture thumbnails (356 px HEIC,
    /// ~30 KB — the size real album art arrives in).
    private static func demoTrack() -> NowPlayingItem {
        let thumbnails = picturesDirectory.appending(path: ".thumbnails", directoryHint: .isDirectory)
        let artwork = images(in: thumbnails).first.flatMap { try? Data(contentsOf: $0) }
        return NowPlayingItem(
            title: "Island Lights",
            artist: "The Notches",
            album: "Liquid Glass",
            duration: 214,
            artworkData: artwork,
            bundleIdentifier: "com.apple.Music"
        )
    }

    private static func sampleFiles() -> [URL] {
        Array(images(in: picturesDirectory).prefix(4))
    }

    private static func images(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "heic" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

private extension PowerState {
    static func demo(level: Int, charging: Bool, minutes: Int) -> PowerState {
        PowerState(
            hasBattery: true,
            level: level,
            isCharging: charging,
            isPluggedIn: charging,
            isCharged: false,
            minutesRemaining: minutes,
            isLowPowerMode: false
        )
    }
}

extension DemoDirector {
    /// Each segmented control in the app's windows as AppKit has it: its frame against the width
    /// it wants (how the bars' first-click widening was found).
    static func logSegments() {
        func walk(_ view: NSView) {
            if let control = view as? NSSegmentedControl {
                let widths = (0..<control.segmentCount).map { String(format: "%.1f", control.width(forSegment: $0)) }
                let line = "\(type(of: control)) frame \(control.frame.width) intrinsic \(control.intrinsicContentSize.width) "
                    + "distribution \(control.segmentDistribution.rawValue) style \(control.segmentStyle.rawValue) "
                    + "size \(control.controlSize.rawValue) selected \(control.selectedSegment) widths [\(widths.joined(separator: ","))] "
                    + "labels [\((0..<control.segmentCount).map { control.label(forSegment: $0) ?? "?" }.joined(separator: ","))]"
                Log.window.notice("SEGMENTS \(line, privacy: .public)")
            }
            view.subviews.forEach(walk)
        }
        for window in NSApp.windows where window.isVisible { window.contentView.map(walk) }
    }
}

private extension URL {
    var creationDate: Date? { (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate }
}

extension DemoDirector {
    /// A crash with NotchIsland's own frames on the stack, so the symbolicated event shows them.
    @inline(never) static func crashOnPurpose() -> Never {
        let reason = ["deliberate crash (demo/crash)"]
        fatalError(reason[Int.random(in: 0..<1)])
    }
}

/// Which desktop the scene shows now.
@Observable private final class PictureDesktopChoice {
    var style = DesktopBackdropStyle.system
    /// A live activity's picture (nil: the open island's).
    var activity: PictureActivity?
}

/// The desktop Settings' pictures are photographed over (`demo/picture`): one of the drawn ones
/// — the default wallpaper dark or light, or the test pattern; ours, so the pictures ship nothing
/// of the system's or the user's — and a menu bar that makes room for the island, its clock at 9:41.
private struct PictureDesktop: View {
    let model: AppModel
    let choice: PictureDesktopChoice

    var body: some View {
        let layout = model.layout
        let style = choice.style
        ZStack(alignment: .top) {
            if style == .checkerboard {
                Checkerboard()
            } else {
                DefaultWallpaper(light: style == .systemLight)
            }
            // The AirPods' picture is the island on macOS's own card, as a set connecting shows it
            // (asked for, from a screenshot of it): a stand-in for that card, which the island lies
            // on and its glass shows, under a menu bar gone black as over a full-screen app.
            if choice.activity == .airPods {
                // Laid out as the island lays its own lines over the card (`SystemAirPodsCovering`):
                // macOS's card has them in the same places, so nothing doubles through the glass.
                let card = SystemVolumeCard.Kind.airPods
                LiquidAirPodsContent(info: DemoDirector.pictureAirPods)
                    .frame(width: card.size.width, height: card.size.height)
                    .background(Color(white: 0.17), in: .rect(cornerRadius: card.radius, style: .continuous))
                    .padding(.top, layout.notch.height + 1 + card.top)
                    .environment(model)
                Color.black.frame(height: layout.notch.height)
            } else {
            // A live activity's picture is the middle of the scene: its menu bar ends there.
            PreviewMenuBar(height: layout.notch.height,
                           notchWidth: choice.activity == nil ? layout.size(for: .expanded(model.island.page)).width : Self.activityRoom,
                           darkText: style.prefersDarkMenuBar, backing: style.menuBarBacking, date: Self.clock)
                .frame(width: choice.activity == nil ? nil : DemoDirector.activityPictureSize.width)
            }
            // The bare notch (the desktop is over the island for it): the camera housing.
            if choice.activity == .idle {
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8, style: .continuous)
                    .fill(.black)
                    .frame(width: layout.notch.width, height: layout.notch.height)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// The widest a live activity is in the notch: the menus keep clear of it.
    private static let activityRoom: CGFloat = 330
    private static let clock = Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: .now) ?? .now
}
