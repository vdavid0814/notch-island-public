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
    /// The battery history (recorded from launch on), details and chart.
    let battery = BatteryCenter()
    let airPods = AirPodsMonitor()
    let listeningModes = AirPodsListeningModeWatch()
    /// The newest version from GitHub, downloaded from About.
    let updater = AppUpdater()
    let stats = SystemStatsMonitor()
    /// The Screen Recording widget's recorder; the island shows it while it records.
    let recorder = ScreenRecorder()
    /// The saved movie in the screen's corner, as macOS shows its own recordings.
    @ObservationIgnored let recordingThumbnail = RecordingThumbnail()
    let levels = LevelsController()
    let shelf = ShelfStore()
    let timers = TimerStore()
    /// Home's board.
    let widgets = WidgetStore()
    /// Every page's board, home's among them.
    @ObservationIgnored private(set) var boards: WidgetPages!
    let studio = WidgetStudio()
    let fullscreen = FullscreenMonitor()
    let assistant = AssistantModel()
    /// What the user copied, for Siri's Clipboard (⌘4).
    let clipboard = ClipboardHistory()
    /// Control Center switches (the Wi-Fi widget, the top bar's toggles).
    let controls = SystemControls()
    /// The coming events, read only while Spotlight shows them.
    let calendar = CalendarService()
    @ObservationIgnored private let commandSpaceTap = CommandSpaceTap()
    /// Whether ⌘Space is really caught (About ▸ Permissions shows it).
    private(set) var commandSpaceState: InterceptionState = .off
    let permissions = PermissionCenter()
    let activity = SystemActivity()
    let haptics: Haptics
    let launchAtLogin = LaunchAtLogin()
    /// Reports to the developer and the user's bug reports (About ▸ Diagnostics).
    let diagnostics = DiagnosticsCenter()

    /// Geometry of the screen the island lives on; nil while no screen exists (clamshell with no
    /// display, or the moment between two display configurations).
    private(set) var metrics: NotchMetrics?

    /// Recomputed from `metrics` and the preferences that size the island (scale, Siri's window,
    /// the panel); the window controller observes it to re-stage the panel when any changes.
    var layout: IslandLayout {
        IslandLayout(notch: metrics?.notchSize ?? Self.fallbackNotchSize, scale: preferences.scale,
                     screen: metrics?.screenFrame.size ?? .zero, siri: preferences.siri.layout, panel: preferences.panel.layout,
                     display: DisplayProfile.factor(for: metrics),
                     settingsFillsLikeReference: DisplayProfile.isKnown(metrics))
    }

    /// The panel's pages on this Mac with these settings: the shelf while it is on, the battery page
    /// only with a battery (`open?page=` and Spotlight ask for the others in vain).
    var availablePages: [ExpandedPage] {
        ExpandedPage.allCases.filter { page in
            switch page {
            case .shelf: preferences.shelfEnabled
            case .battery: power.hasBattery
            default: true
            }
        } + preferences.header.customPages.map(\.page)
    }

    /// The panel's board set (Settings ▸ Widgets ▸ Size): every page's board follows its grid, each
    /// widget on its cells; `leadingColumns` of the columns added (or taken away) at the leading side.
    func setPanel(_ panel: PanelSettings, leadingColumns: Int? = nil) {
        preferences.panel = panel
        boards.follow(panel.grid, leadingColumns: leadingColumns)
    }

    /// The saved notch styles (Settings ▸ Widgets' Save Notch Style and Open Notch Styles).
    let notchStyles = NotchStyleStore()

    /// The island as Settings ▸ Widgets has it now, as a notch style (not yet named or kept).
    func currentNotchStyle() -> NotchStyle {
        let pages = preferences.header.orderedPages.filter(\.isBoard)
        let boards = Dictionary(uniqueKeysWithValues: pages.map { ($0.rawValue, self.boards.store(for: $0).board) })
        let look = NotchStyle.Look(glassStyle: preferences.glassStyle, theme: preferences.theme,
                                   musicBars: preferences.musicBars.rawValue, musicBarsOnPower: preferences.musicBarsOnPower.rawValue,
                                   levelStyle: preferences.levelStyle.rawValue)
        return NotchStyle(name: "", panel: preferences.panel, scale: preferences.scale, header: preferences.header, boards: boards,
                          look: look)
    }

    /// Whether the island is as `style` has it.
    func isCurrent(_ style: NotchStyle) -> Bool {
        let now = currentNotchStyle()
        return now.panel == style.panel && now.scale == style.scale && now.header == style.header && now.boards == style.boards
            && (style.look == nil || now.look == style.look)
    }

    /// The island as `style` has it: its look, its pages and top bar, its cells and size, every board. A page
    /// of the user's it does not have goes, with its board; a board it does not have is emptied.
    /// The boards' changes are steps Undo takes back.
    func open(_ style: NotchStyle) {
        if let look = style.look {
            preferences.glassStyle = look.glassStyle
            preferences.theme = look.theme
            if let bars = MusicBarsStyle(rawValue: look.musicBars) { preferences.musicBars = bars }
            if let bars = MusicBarsStyle(rawValue: look.musicBarsOnPower) { preferences.musicBarsOnPower = bars }
            if let level = LevelHUDStyle(rawValue: look.levelStyle) { preferences.levelStyle = level }
        }
        preferences.header = style.header
        boards.sync(preferences.header.orderedPages)
        preferences.scale = style.scale
        preferences.panel = style.panel
        for page in preferences.header.orderedPages where page.isBoard {
            let store = boards.store(for: page)
            store.load(style.boards[page.rawValue] ?? WidgetBoard(widgets: [], grid: style.panel.grid))
        }
        if !preferences.header.orderedPages.contains(studio.page) { studio.page = .home }
        if !preferences.header.orderedPages.contains(island.page) { island.page = .home }
    }

    /// The panel, its scale and every board as they are now (Settings ▸ Widgets ▸ Size).
    func sizeSnapshot() -> SizeSnapshot {
        SizeSnapshot(panel: preferences.panel, scale: preferences.scale, boards: boards.snapshot())
    }

    /// All of it back as `snapshot` had it, every widget where it was.
    func restoreSize(_ snapshot: SizeSnapshot) {
        preferences.scale = snapshot.scale
        preferences.panel = snapshot.panel
        boards.restore(snapshot.boards, grid: snapshot.panel.grid)
    }

    /// The board the Widgets stage shows and edits: the studio's page's.
    var editedWidgets: WidgetStore { boards.store(for: studio.page) }

    /// A new page of the user's, an empty board, at the picker's end; nil at the limit.
    @discardableResult
    func addPage() -> ExpandedPage? {
        var header = preferences.header
        guard let page = header.addCustomPage(title: header.nextCustomTitle) else { return nil }
        preferences.header = header
        _ = boards.store(for: page)
        return page
    }

    /// Takes a page of the user's away with its board and its widgets' data.
    func removePage(_ page: ExpandedPage) {
        guard page.isCustom else { return }
        preferences.header.removeCustomPage(page)
        if studio.page == page { studio.page = .home }
        if island.page == page { island.page = .home }
        boards.sync(preferences.header.orderedPages)
    }

    /// The pages the top bar's picker offers, in the user's order (`HeaderLayout`). A hidden page
    /// is still there for what asks for it by name (the battery in the bar, `open?page=`).
    var pickerPages: [ExpandedPage] { preferences.header.pages(among: availablePages) }

    /// Window Anchor: another app's window held under the notch.
    let anchor = WindowAnchor()
    /// The anchored window up at the screen's top, as a live copy the clicks go through to.
    let anchorMirror = AnchorMirror()
    /// A window is held under the notch: the top bar shows its release button.
    var isWindowAnchored: Bool { anchor.isAnchored }

    /// The page the panel shows: the one chosen, or home once that one is gone (the shelf switched
    /// off while it was the page).
    var panelPage: ExpandedPage {
        availablePages.contains(island.page) ? island.page : .home
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
        boards = WidgetPages(home: widgets)
        // A panel stored before the board was set by its cells: its board's grid at the default cell.
        if preferences.panel.isFromBefore {
            let grid = widgets.board.grid
            preferences.panel = PanelSettings(cell: PanelSettings().cell, gap: Double(grid.gap), columns: grid.columns, rows: grid.rows)
        }
        boards.follow(preferences.panel.grid)
        boards.sync(preferences.header.orderedPages)
        haptics = Haptics(preferences: preferences)
        controller = IslandController(model: self)
        assistant.onClose = { [weak self] in self?.controller.closeAssistant() }
        recorder.onStop = { [weak self] in self?.controller.recordingStopped() }
        recorder.onStart = { [weak self] in self?.recordingThumbnail.dismiss(animated: false) }
        recorder.onSaved = { [weak self] url, display in self?.recordingThumbnail.show(url, display: display) }
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
        assistant.enableCurrencies = { [weak preferences] in preferences?.siri.convertsCurrency = true }
        assistant.clipboard = { [weak self] in self?.clipboard.items ?? [] }
        assistant.system = .live(controls: controls, isPinned: { [weak self] in self?.island.isPinned ?? false })
        assistant.timerIsActive = { [weak self] in self?.timers.isCountdownActive ?? false }
        // People & Calendar (⌘8): the events the Up Next widget reads, leased while it is open.
        assistant.calendarAccess = { [weak self] in
            switch self?.calendar.access {
            case .granted?: .granted
            case .notDetermined?: .notDetermined
            default: .denied
            }
        }
        assistant.calendarEvents = { [weak self] query in
            guard let self else { return [] }
            let events = self.calendar.upcoming(calendars: nil, count: CalendarService.limit)
            return query.isEmpty ? events : events.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        assistant.requestCalendar = { [weak self] in self?.calendar.requestAccess() }
        assistant.onCalendarLease = { [weak self] holds in
            if holds { self?.calendar.acquire() } else { self?.calendar.release() }
        }
        assistant.widgetKinds = { [weak self] in self?.widgets.board.widgets.map(\.kind) ?? [] }
        assistant.pages = { [weak self] in self?.availablePages ?? [] }
        assistant.anchorIsHolding = { [weak self] in
            guard let self, self.canAnchorWindows else { return nil }
            return self.anchor.isAnchored
        }
        assistant.onAnchorWindow = { [weak self] window in
            guard let self else { return }
            // The keyboard goes back first; then the window comes forward, and is taken once it is there.
            self.controller.closeAssistant()
            RunningWindows.switchTo(window)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.anchor.anchorFront()
            }
        }
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
        commandSpaceTap.onStateChange = { [weak self] state in
            guard let self else { return }
            self.commandSpaceState = state
            // Refused for want of Input Monitoring (macOS 27): its own prompt, once.
            if case .failed = state, !CGPreflightListenEventAccess() { self.permissions.promptInputMonitoringOnce() }
        }
        // A permission allowed (or the list changed): refused key taps get another try.
        permissions.onChange = { [weak self] in
            self?.commandSpaceTap.retryIfFailed()
            self?.levels.retryInterception()
        }
        // A Reset of Accessibility or Input Monitoring: the key taps go before the permission does,
        // at once (the feature loop follows a moment later, too late). Let go, they are refused
        // until the user allows the app again: tried patiently, not given up after three attempts.
        permissions.onHoldKeyTaps = { [weak self] in
            self?.commandSpaceTap.stop()
            self?.levels.setInterceptionEnabled(false)
            self?.commandSpaceTap.expectRefusals()
            self?.levels.expectInterceptionRefusals()
        }
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
        battery.start(power: power, activity: activity)
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
        updater.startAutomaticChecks()
        // The liquid card's frames for where macOS's card is expected, once the launch has settled.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.liquidCard.prewarm()
        }

        // Just updated and a permission in use is missing (a copy signed differently): About shows
        // which one, instead of features that silently do nothing.
        if updater.updatedFrom != nil {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.isRunning, self.permissionsNeedAttention else { return }
                self.controller.openSettings(pane: .about)
            }
        }

        // Siri's app icons are kept on disk for the next launch (a test run keeps none).
        AssistantIcons.disk = .caches

        let queued = pendingCommands
        pendingCommands.removeAll()
        queued.forEach(perform)

        // What the first opening of Siri needs, read ahead while nothing else is going on.
        if !hasPrewarmed {
            hasPrewarmed = true
            // At background priority: what it reads off the main thread runs on the efficiency cores.
            Task(priority: .background) { [weak self] in
                try? await Task.sleep(for: .seconds(12), tolerance: .seconds(3))
                guard let self, self.isRunning, !self.island.presentation.isAssistant else { return }
                await self.assistant.prewarm()
                guard self.isRunning, !self.island.presentation.isOpen else { return }
                AssistantRehearsal.run(model: self)
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
        battery.stop()
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
        case .editWidget(.kind(let kind)):
            editWidget(widgets.board.first(of: kind)?.id)
        case .editWidget(.instance(let id)):
            editWidget(boards.page(containing: id) != nil ? id : nil)
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
        case .anchorFrontWindow:
            // Asking for it says the user wants it: the permission it needs is asked for.
            if preferences.anchorEnabled, !permissions.accessibilityTrusted { permissions.promptOrOpenAccessibilitySettings() }
            anchor.anchorFront()
        case .releaseAnchoredWindow:
            anchor.release()
        case .toggleRecording:
            recorder.toggle(display: metrics?.displayID)
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
    var editingWidget: WidgetID?

    /// Settings ▸ Widgets, with the widget's editor open (nil: the page alone).
    func editWidget(_ id: WidgetID?) {
        if let page = id.flatMap(boards.page(containing:)) { studio.page = page }
        editingWidget = id
        settingsPane = .widgets
        showSettings()
    }

    /// Lets go of the window held under the notch.
    func releaseAnchoredWindow() {
        anchor.release()
    }

    /// Window Anchor can run: the preference is on and Accessibility is trusted.
    var canAnchorWindows: Bool { appliedFeatures?.anchor ?? false }

    /// The notch screen for Settings' size picture (a MacBook's own when there is none).
    var anchorScreenForSettings: AnchorScreen {
        anchorScreen ?? AnchorScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), band: 33, notch: CGSize(width: 185, height: 32))
    }

    /// The notch screen for the anchor, in the window server's coordinates (y down from the top of
    /// the primary display).
    private var anchorScreen: AnchorScreen? {
        guard let metrics, let screen = notchScreen, let primary = NSScreen.screens.first else { return nil }
        let frame = CGRect(x: metrics.screenFrame.minX, y: primary.frame.maxY - metrics.screenFrame.maxY,
                           width: metrics.screenFrame.width, height: metrics.screenFrame.height)
        // The menu bar (a pixel taller than the notch's safe area on this Mac); the safe area where
        // the bar hides itself.
        let band = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
        return AnchorScreen(frame: frame, band: band, notch: metrics.notchSize)
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

    /// A feature that is on cannot work for want of Accessibility or Input Monitoring.
    var permissionsNeedAttention: Bool {
        let prefs = preferences
        let needsTrust = prefs.commandSpaceOpensSiri || prefs.replaceSystemHUD || prefs.anchorEnabled
        return (needsTrust && !permissions.accessibilityTrusted) || (prefs.commandSpaceOpensSiri && !permissions.inputMonitoringAllowed)
    }

    /// For diagnostics reports: the feature state last applied, and whether ⌘Space is listened for.
    var diagnosticsFeatureState: String { appliedFeatures.map { String(describing: $0) } ?? "stopped" }
    var diagnosticsCommandSpaceTapRunning: Bool { commandSpaceState == .active }
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
        anchor.screen = { [weak self] in self?.anchorScreen }
        anchor.onTargeted = { [weak self] targeted in self?.controller.setAnchorTargeted(targeted) }
        anchor.size = { [weak self] screen in
            (self?.preferences.anchorSize ?? AnchorSizePreference()).size(on: screen)
        }
        anchor.onHeldChanged = { [weak self] held in
            guard let self else { return }
            // Up at the screen's top as a live copy (the real window right under the menu bar).
            self.anchorMirror.update(held: held, screen: self.anchorScreen)
        }
        anchor.onAppWindowsChanged = { [weak self] in self?.anchorMirror.appWindowsChanged() }
        anchorMirror.onRelease = { [weak self] in self?.anchor.release(reason: "released from the stage") }
        anchorMirror.setBar(preferences.anchorBar)
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
            self?.updateAnchorIslandReach(to)
        }
    }

    /// The anchored window's name and Release beside the notch move out past the island's compact
    /// ears (what is playing) while those are out.
    private func updateAnchorIslandReach(_ presentation: IslandPresentation) {
        guard case .compact = presentation else { return anchorMirror.setIslandReach(0) }
        let layout = self.layout
        let reach = (layout.size(for: presentation).width - layout.notch.width) / 2 + layout.shoulderRadius(for: presentation)
        anchorMirror.setIslandReach(reach.rounded(.up))
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
            levelWidgets: boards.needsLevels,
            replaceSystemHUD: preferences.replaceSystemHUD,
            accessibilityTrusted: permissions.accessibilityTrusted,
            keyTapsHeld: permissions.keyTapsHeld,
            shelfEnabled: preferences.shelfEnabled,
            suspended: activity.isSuspended,
            hideInFullscreen: preferences.hideInFullscreen,
            fullscreenActive: isPlayingVideoFullscreen,
            fullscreenPresent: needsMenuBarGuard,
            commandSpaceOpensSiri: preferences.commandSpaceOpensSiri,
            liquidVolume: preferences.liquidVolume,
            liquidAirPods: preferences.liquidAirPods,
            anchorEnabled: preferences.anchorEnabled,
            anchorByDrag: preferences.anchorByDrag,
            anchorMirror: preferences.anchorMirror,
            anchorPaused: metrics == nil || !fullscreen.fullscreenApps.isEmpty
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
        case .prewarmLiquid: liquidCard.prewarm()
        case .setAnchor(let enabled):
            anchor.setEnabled(enabled)
            setAnchorQuitWatch(enabled)
        case .setAnchorDrag(let enabled): anchor.setDragEnabled(enabled)
        case .setAnchorPaused(let paused):
            anchor.setPaused(paused)
            anchorMirror.setPaused(paused)
        case .setAnchorMirror(let enabled): anchorMirror.setEnabled(enabled)
        }
    }

    @ObservationIgnored private var anchorQuitToken: (any NSObjectProtocol)?

    /// An app quitting takes its anchored window with it (watched only while the anchor runs).
    private func setAnchorQuitWatch(_ enabled: Bool) {
        let center = NSWorkspace.shared.notificationCenter
        if let anchorQuitToken { center.removeObserver(anchorQuitToken) }
        anchorQuitToken = nil
        guard enabled else { return }
        anchorQuitToken = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid { self?.anchor.applicationTerminated(pid) }
            }
        }
    }
}
