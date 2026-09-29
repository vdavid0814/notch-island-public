import AppKit
import Observation

/// The composition root: owns every store, controller and system service, and wires them together.
///
/// It holds no feature logic. Its jobs are (1) forwarding feature events to banners, haptics and
/// sounds, (2) starting and stopping features when preferences, permissions or system state
/// change, and (3) translating `AppCommand`s into intents on the stores.
@Observable final class AppModel {
    /// Created on first access (from `NotchIslandApp.init`, on the main actor). Creating it starts
    /// nothing; `start()` does, once the app has finished launching.
    static let shared = AppModel()

    /// Stands in for the notch while no screen exists, so views and layout always have a size.
    nonisolated static let fallbackNotchSize = CGSize(width: 180, height: 32)

    let preferences: Preferences
    let island = IslandModel()
    let banners = BannerCenter()
    let media = MediaController()
    let power = PowerMonitor()
    let airPods = AirPodsMonitor()
    let listeningModes = AirPodsListeningModeWatch()
    let stats = SystemStatsMonitor()
    let levels = LevelsController()
    let shelf = ShelfStore()
    let timers = TimerStore()
    let widgets = WidgetStore()
    let fullscreen = FullscreenMonitor()
    let assistant = AssistantModel()
    /// What the user copied, for Siri's Clipboard (⌘4).
    let clipboard = ClipboardHistory()
    /// Control Center switches for the Controls and Keyboard widgets.
    let controls = SystemControls()
    @ObservationIgnored private let commandSpaceTap = CommandSpaceTap()
    let permissions = PermissionCenter()
    let activity = SystemActivity()
    let haptics: Haptics
    let launchAtLogin = LaunchAtLogin()
    /// Reports to the developer and the user's bug reports (About ▸ Diagnostics).
    let diagnostics = DiagnosticsCenter()

    /// Geometry of the screen the island lives on; nil while no screen exists (clamshell with no
    /// display, or the moment between two display configurations).
    private(set) var metrics: NotchMetrics?

    /// Recomputed from `metrics` and `preferences.scale`; the window controller observes it to
    /// re-stage the panel when either changes.
    var layout: IslandLayout {
        IslandLayout(notch: metrics?.notchSize ?? Self.fallbackNotchSize, scale: preferences.scale,
                     screen: metrics?.screenFrame.size ?? .zero, siri: preferences.siri.layout)
    }

    /// Created at the end of `init` (it needs `self`) and never replaced, hence not observed.
    @ObservationIgnored private(set) var controller: IslandController!

    @ObservationIgnored private let dragMonitor = DragSessionMonitor()
    @ObservationIgnored private let demo = DemoDirector()
    @ObservationIgnored private var windowController: IslandWindowController?
    @ObservationIgnored private var settingsWindow: SettingsWindowController?
    @ObservationIgnored private var customizeWindow: WidgetEditorWindowController?

    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var hasStartedController = false
    @ObservationIgnored private var hasInstalledTransitionHaptics = false
    /// Commands that arrive before `start()`: a URL that launches the app is delivered before
    /// `applicationDidFinishLaunching`.
    @ObservationIgnored private var pendingCommands: [AppCommand] = []

    /// The feature state last applied; nil while stopped.
    @ObservationIgnored private var appliedFeatures: FeatureState?
    /// Bumped by `stop()` so a re-arm that was already queued by the observation loop dies.
    @ObservationIgnored private var featureGeneration = 0
    /// True between a forwarded `externalDragBegan()` and its `externalDragEnded()`, so the two
    /// always pair up even if the shelf is switched off or a drag-out flag flips mid-drag.
    @ObservationIgnored private var isForwardingDrag = false
    /// The volume card that runs out to macOS's own when that one is not under the notch.
    @ObservationIgnored private(set) lazy var liquidCard = LiquidCard(model: self)

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        haptics = Haptics(preferences: preferences)
        controller = IslandController(model: self)
        assistant.onClose = { [weak self] in self?.controller.closeAssistant() }
        assistant.onCommand = { [weak self] command in
            guard let self else { return }
            if case .open = command {
                // The panel takes the assistant's place, as the header's Siri button came from it.
                self.perform(command)
                self.controller.closeAssistant()
            } else {
                // Closed first, so the keyboard is handed back before a window (Settings) opens.
                self.controller.closeAssistant()
                self.perform(command)
            }
        }
        assistant.mediaState = { [weak self] in
            guard let self, self.preferences.showNowPlaying, self.media.item != nil else { return .none }
            return self.media.isPlaying ? .playing : .paused
        }
        assistant.onFileAccessSettled = { [weak self] in self?.windowController?.assistantNeedsKeyboard() }
        assistant.settings = { [weak preferences] in preferences?.siri ?? SiriSettings() }
        assistant.clipboard = { [weak self] in self?.clipboard.items ?? [] }
        assistant.onPaste = { [weak self] item in
            guard let self else { return }
            // Siri gives the keyboard back to the app the user was typing in, then ⌘V lands there.
            self.clipboard.place(item)
            self.controller.closeAssistant()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                ClipboardHistory.pasteIntoFrontApp()
            }
        }
        commandSpaceTap.setModifiers(preferences.siri.shortcut.modifiers)
        // Like the system's ⌘Space: opens Siri, and closes it again.
        commandSpaceTap.onPress = { [weak self] in
            guard let self else { return }
            if self.island.presentation.isAssistant {
                guard self.preferences.siri.shortcutCloses else { return }
                self.controller.closeAssistant()
            } else {
                self.controller.openAssistant()
            }
        }
        wireFeatureEvents()
    }

    // MARK: Lifecycle

    /// Starts every service. Idempotent. Works without a screen: the menu bar and Settings stay
    /// usable and the window controller anchors the island once a display appears.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        Log.app.notice("start")
        PerfTrace.install()

        permissions.start()
        activity.start()
        launchAtLogin.refresh()
        power.start()
        airPods.start()
        shelf.pruneMissingInBackground()

        // The window controller must exist before the island controller applies its first
        // presentation, because it stages the panel in `willTransition`.
        let window = windowController ?? IslandWindowController(model: self)
        windowController = window
        window.start()
        if !hasStartedController {
            hasStartedController = true
            controller.start()
        }
        installTransitionHaptics()
        observeFeatures()
        diagnostics.start(model: self)
        // The liquid card's frames for where macOS's card is expected, once the launch has settled.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.liquidCard.prewarm()
        }

        let queued = pendingCommands
        pendingCommands.removeAll()
        queued.forEach(perform)

        // What the first opening of Siri needs, read ahead while nothing else is going on.
        if !hasPrewarmed {
            hasPrewarmed = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(12), tolerance: .seconds(3))
                guard let self, self.isRunning, !self.island.presentation.isAssistant else { return }
                await self.assistant.prewarm()
            }
        }
    }

    @ObservationIgnored private var hasPrewarmed = false

    /// Stops every service and removes every observer. Idempotent.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        featureGeneration += 1
        Log.app.notice("stop")

        demo.cancel()
        diagnostics.stop()
        FeatureState.actions(from: appliedFeatures, to: .off).forEach(run)
        appliedFeatures = nil
        clipboard.setWatching(false)
        power.stop()
        airPods.stop()
        listeningModes.stop()
        activity.stop()
        permissions.stop()
        windowController?.stop()
    }

    // MARK: Intents

    func perform(_ command: AppCommand) {
        guard isRunning else {
            pendingCommands.append(command)
            return
        }
        Log.app.info("command: \(String(describing: command), privacy: .public)")
        switch command {
        case .open(let page):
            // An explicit request (menu or URL). Without the pointer the island controller closes
            // it again after a while unless the user moves in.
            controller.expand(page: page, pinned: false, userInitiated: true)
        case .close:
            controller.collapse()
        case .togglePin:
            controller.togglePinned()
        case .media(let mediaCommand):
            // With Now Playing off every media source is stopped; a command would have no target.
            guard preferences.showNowPlaying else {
                Log.media.info("ignored \(String(describing: mediaCommand), privacy: .public): Now Playing is off")
                return
            }
            media.send(mediaCommand)
        case .startTimer(let minutes):
            timers.start(minutes: minutes)
        case .cancelTimer:
            timers.cancel()
        case .startStopwatch:
            timers.startStopwatch()
        case .showSettings:
            showSettings()
        case .showSettingsPane(let pane):
            settingsPane = pane
            showSettings()
        case .editWidget(let kind):
            editWidget(kind)
        case .customize:
            showCustomize()
        case .assistant:
            controller.openAssistant()
        case .sendDiagnostics:
            guard diagnostics.isEnabled else {
                Log.app.notice("diagnostics/send ignored: diagnostics are off")
                return
            }
            Task { await diagnostics.sendReport(.manual) }
        case .sendPeriodicDiagnostics:
            guard diagnostics.isEnabled else { return }
            Task { await diagnostics.sendReport(.periodic) }
        case .publishBaseline:
            Task { await diagnostics.publishBaseline() }
        case .demo(let demoCommand):
            demo.run(demoCommand, model: self)
        }
    }

    /// The style the island is drawn in: the user's, except in Low Power Mode, where it is plain
    /// black — no glass sampling its backdrop, no fade gradient (the user asked for it).
    var effectiveGlassStyle: IslandGlassStyle {
        activity.isLowPowerMode ? .black : preferences.glassStyle
    }

    /// The Settings tab shown in the island; remembered across launches.
    var settingsPane: IslandSettingsPane = IslandSettingsPane.named(
        UserDefaults.standard.string(forKey: IslandSettingsPane.key) ?? ""
    ) ?? .general {
        didSet { UserDefaults.standard.set(settingsPane.rawValue, forKey: IslandSettingsPane.key) }
    }

    /// A widget whose editor Settings ▸ Widgets should open (from the island's context menu).
    var editingWidget: IslandWidgetKind?

    func editWidget(_ kind: IslandWidgetKind) {
        editingWidget = kind
        settingsPane = .widgets
        showSettings()
    }

    /// Settings grows out of the notch; without a notch screen (nothing to grow out of) it opens as
    /// a window.
    func showSettings() {
        if isRunning, metrics != nil {
            controller.openSettings()
        } else {
            showSettingsWindow()
        }
    }

    /// The widget editor is Settings' Widgets tab.
    func showCustomize() {
        if isRunning, metrics != nil {
            controller.openSettings(pane: .widgets)
        } else {
            let editor = customizeWindow ?? WidgetEditorWindowController(model: self)
            customizeWindow = editor
            editor.show()
        }
    }

    func showSettingsWindow() {
        let settings = settingsWindow ?? SettingsWindowController(model: self)
        settingsWindow = settings
        settings.show()
    }

    /// Called by the window controller whenever it (re)anchors the island.
    func updateMetrics(_ metrics: NotchMetrics?) {
        guard metrics != self.metrics else { return }
        self.metrics = metrics
        if let metrics {
            Log.window.notice("anchored on display \(metrics.displayID, privacy: .public), notch \(metrics.notchSize.width, privacy: .public)×\(metrics.notchSize.height, privacy: .public) physical: \(metrics.isPhysical, privacy: .public)")
        } else {
            Log.window.notice("no screen")
        }
        // The full-screen check needs the notch screen; at launch it may run before it is known.
        fullscreen.refresh()
        controller.notchGeometryChanged()
    }

    /// `demo/state`: the island as the window layer and SwiftUI see it, in the log.
    func logIslandState() {
        guard let windowController else {
            Log.window.notice("state: window layer not started")
            return
        }
        windowController.logState()
    }

    /// For diagnostics reports: the feature state last applied, and whether ⌘Space is listened for.
    var diagnosticsFeatureState: String { appliedFeatures.map { String(describing: $0) } ?? "stopped" }
    var diagnosticsCommandSpaceTapRunning: Bool { commandSpaceTap.isRunning }
    /// The applied features want the ⌘Space tap (so a stopped tap is a problem).
    var diagnosticsCommandSpaceWanted: Bool { appliedFeatures?.commandSpace ?? false }

    /// Settings ▸ Siri changed the shortcut: the key tap listens for the new modifier at once.
    func siriShortcutChanged(_ shortcut: SiriShortcut) {
        commandSpaceTap.setModifiers(shortcut.modifiers)
    }

    // MARK: Wiring

    private func wireFeatureEvents() {
        power.onEvent = { [weak self] event in self?.powerEvent(event) }
        airPods.onConnect = { [weak self] info in self?.airPodsConnected(info) }
        airPods.onOutputsChanged = { [weak self] outputs in self?.listeningModes.follow(outputs) }
        listeningModes.onChange = { [weak self] name, mode in self?.airPodsModeChanged(name: name, to: mode) }
        airPods.systemCard = { [weak self] in self?.preferences.airPodsSystemCard ?? .cover }
        airPods.onUpdate = { [weak self] info in self?.airPodsUpdated(info) }
        levels.onChange = { [weak self] kind, source in self?.levelChanged(kind, source: source) }
        timers.onFinished = { [weak self] in self?.timerFinished() }
        dragMonitor.onDragBegan = { [weak self] in self?.externalDragBegan() }
        dragMonitor.onDragEnded = { [weak self] in self?.externalDragEnded() }
    }

    private func powerEvent(_ event: PowerEvent) {
        // Passive: nothing appears by itself over a full-screen video (the banner would also count
        // down invisibly and pop out stale afterwards).
        guard preferences.showPowerAlerts, appliedFeatures?.hidden != true else { return }
        banners.post(.power(event), duration: preferences.powerDuration)
        haptics.play(.alert)
    }

    func airPodsConnected(_ info: AirPodsInfo) {
        DiagnosticsFlow.record(info.listeningMode.map { "airpods mode: \(info.name) → \($0)" } ?? "airpods connected: \(info)")
        // Passive, like a power notice: nothing appears by itself over a full-screen video.
        guard preferences.showAirPods, appliedFeatures?.hidden != true else { return }
        // Covering macOS's card away from the notch: the liquid runs to it.
        if preferences.airPodsSystemCard == .cover,
           liquidCard.airPodsConnected(info, duration: preferences.airPodsDuration, flows: preferences.liquidAirPods) {
            haptics.play(.alert)
            return
        }
        banners.post(.airPods(info), duration: preferences.airPodsDuration)
        haptics.play(.alert)
    }

    /// The AirPods' noise control changed: macOS shows its card, the island covers it as it does the
    /// connection card (the same settings: shown or not, over macOS's card, flowing out, how long).
    func airPodsModeChanged(name: String, to mode: AirPodsListeningMode) {
        // The batteries last read at once (macOS's card shows them too), fresher ones after.
        var info = airPods.lastInfo[name] ?? AirPodsInfo(name: name, model: .init(name: name, productID: nil))
        info.listeningMode = mode
        airPodsConnected(info)
        Task { [weak self] in
            guard var fresh = await AirPodsMonitor.readInfo(named: name), let self else { return }
            self.airPods.remember(fresh)
            fresh.listeningMode = mode
            self.airPodsUpdated(fresh)
        }
    }

    /// Fresher batteries: only into the card still up for these headphones.
    private func airPodsUpdated(_ info: AirPodsInfo) {
        guard !liquidCard.airPodsUpdated(info), case .airPods(let shown)? = banners.current, shown.name == info.name,
              shown.listeningMode == info.listeningMode, shown != info else { return }
        banners.post(.airPods(info), duration: preferences.airPodsDuration)
    }

    /// How much longer a banner over macOS's volume card stays (asked for, v0.4.7).
    static let coveringExtra: Double = 0.2

    private func levelChanged(_ kind: LevelKind, source: LevelChangeSource) {
        // `.island`: the user is dragging the island's own slider and already sees the value.
        if source == .external { DiagnosticsFlow.record("\(kind) changed elsewhere") }
        guard preferences.showLevelHUD, source != .island else { return }
        // Over a full-screen video only a key press is answered; a Control Center, AirPods or
        // auto-brightness change stays invisible there.
        if appliedFeatures?.hidden == true, source != .key { return }
        // macOS's own card away from the notch (the desktop, a tiled window): the liquid runs to it.
        if liquidCard.handleLevel(kind, source: source, duration: preferences.levelDuration + Self.coveringExtra,
                                  flows: preferences.liquidVolume) {
            if source == .key { haptics.play(.tick) }
            return
        }
        // A key press is the user asking to see the level; a change made elsewhere is only a notice
        // and must not bury a banner already up (a power event, a finished timer).
        // A volume change made elsewhere (an AirPods stem swipe) brings macOS's own volume card up
        // under the notch, past any key tap; the banner then lies over it, in either style.
        let banner: BannerKind = if kind == .volume, source == .external { .levelCovering(kind) }
            else if preferences.levelStyle == .pill { .levelPill(kind) } else { .level(kind) }
        // Over macOS's card a little longer: it stays up a moment past a banner of the usual length.
        let duration = preferences.levelDuration + (banner == .levelCovering(kind) ? Self.coveringExtra : 0)
        banners.post(banner, duration: duration, preempting: source == .key)
        // Only a key press is felt; a Control Center slider drag (`.external`) must not buzz.
        if source == .key { haptics.play(.tick) }
    }

    private func timerFinished() {
        banners.post(.timerFinished, duration: 30)
        if preferences.timerSound {
            NSSound(named: "Glass")?.play()
        }
        haptics.play(.alert)
    }

    private func externalDragBegan() {
        // A drag that started on one of our own shelf tiles is not a drop candidate.
        guard preferences.shelfEnabled, !shelf.isDraggingOut, !isForwardingDrag else { return }
        isForwardingDrag = true
        controller.externalDragBegan()
    }

    private func externalDragEnded() {
        guard isForwardingDrag else { return }
        isForwardingDrag = false
        controller.externalDragEnded()
    }

    /// Open/close haptics. Chained onto whatever the island layer installed rather than replacing
    /// it; should that layer also buzz, the per-event throttle in `Haptics` absorbs the duplicate.
    private func installTransitionHaptics() {
        guard !hasInstalledTransitionHaptics else { return }
        hasInstalledTransitionHaptics = true
        let previous = island.didTransition
        island.didTransition = { [weak self] from, to in
            previous?(from, to)
            self?.transitionHaptic(from: from, to: to)
        }
    }

    private func transitionHaptic(from: IslandPresentation, to: IslandPresentation) {
        if to.isOpen && !from.isOpen {
            haptics.play(.open)
        } else if from.isOpen && !to.isOpen {
            haptics.play(.close)
        }
    }

    // MARK: Feature observation

    private func currentFeatureState() -> FeatureState {
        FeatureState(
            showNowPlaying: preferences.showNowPlaying,
            showWebMedia: preferences.showWebMedia,
            showLevelHUD: preferences.showLevelHUD,
            levelWidgets: widgets.needsLevels,
            replaceSystemHUD: preferences.replaceSystemHUD,
            accessibilityTrusted: permissions.accessibilityTrusted,
            shelfEnabled: preferences.shelfEnabled,
            suspended: activity.isSuspended,
            hideInFullscreen: preferences.hideInFullscreen,
            fullscreenActive: isPlayingVideoFullscreen,
            fullscreenPresent: needsMenuBarGuard,
            commandSpaceOpensSiri: preferences.commandSpaceOpensSiri
        )
    }

    /// Re-arming observation loop. Tracking covers only the properties `currentFeatureState()`
    /// reads, so hover-delay or size slider drags never wake it; when it does fire, only the
    /// difference to the applied state is acted on.
    private func observeFeatures() {
        let generation = featureGeneration
        let (state, watchesClipboard) = withObservationTracking {
            (currentFeatureState(), preferences.siri.showsClipboard)
        } onChange: { [weak self] in
            // Fires in willSet on the mutating thread; the hop lands after the new value is set.
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.featureGeneration == generation else { return }
                self.observeFeatures()
            }
        }
        clipboard.setWatching(watchesClipboard)
        let actions = FeatureState.actions(from: appliedFeatures, to: state)
        appliedFeatures = state
        guard !actions.isEmpty else { return }
        Log.app.notice("features: \(String(describing: actions), privacy: .public)")
        actions.forEach(run)
    }

    /// Hidden for a video playing in full screen, straight from the inputs (see `FeatureState.hidden`).
    var hidesForFullscreenVideo: Bool {
        preferences.hideInFullscreen && isPlayingVideoFullscreen && !activity.isSuspended
    }

    /// A full-screen app is on the notch screen, whose physical notch is where the pointer goes, and
    /// the menu bar hides in full screen (System Settings ▸ Control Center ▸ "Automatically hide and
    /// show the menu bar"; with it always shown there is nothing to keep hidden).
    private var needsMenuBarGuard: Bool {
        !fullscreen.fullscreenApps.isEmpty && (metrics?.isPhysical ?? false)
            && !UserDefaults.standard.bool(forKey: "AppleMenuBarVisibleInFullscreen")
    }

    /// The app playing the current media (playing, or paused a moment ago) has a full-screen window:
    /// a video watched in full screen. A full-screen app that is not the player never counts.
    private var isPlayingVideoFullscreen: Bool {
        guard media.isActive, let player = media.item?.bundleIdentifier else { return false }
        return fullscreen.fullscreenApps.contains(player)
    }

    /// The screen the island lives on.
    var notchScreen: NSScreen? {
        guard let id = metrics?.displayID else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    private func run(_ action: FeatureAction) {
        switch action {
        case .startMedia: media.start()
        case .stopMedia: media.stop()
        case .setWebMedia(let enabled): media.setWebMediaEnabled(enabled)
        case .startLevels: levels.start()
        case .stopLevels: levels.stop()
        case .setInterception(let enabled): levels.setInterceptionEnabled(enabled)
        case .requestAccessibility: permissions.requestAccessibility()
        case .startDragMonitor: dragMonitor.start()
        case .stopDragMonitor:
            dragMonitor.stop()
            externalDragEnded()
        case .setSuspended(let suspended):
            if suspended { controller.closeAssistant() }
            windowController?.setSuspended(suspended)
            media.setSuspended(suspended)
        case .setFullscreenMonitor(let enabled):
            if enabled {
                fullscreen.screen = { [weak self] in self?.notchScreen }
                fullscreen.start()
            } else {
                fullscreen.stop()
            }
        case .setHidden(let hidden):
            // Media keeps running: it is what tells us when the video stops playing.
            controller.setHidden(hidden)
        case .setFullscreenPresent(let present):
            controller.setFullscreenPresent(present)
            // Where macOS's card comes up depends on it: its frames, if not worked out yet.
            liquidCard.prewarm()
        case .setCommandSpace(let enabled):
            if enabled { commandSpaceTap.start() } else { commandSpaceTap.stop() }
        }
    }
}
