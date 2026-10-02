import AppKit
import Observation
import SwiftUI

/// Owns the island panel and stages its frame around every transition.
///
/// Staging: before a transition the frame grows to cover both ends (plus
/// `stageMargin` for overshoot); `Motion.settleDuration(for:)` later it shrinks to the
/// resting frame of the target — exactly the notch when idle, so at rest
/// nothing of ours sits over a menu-bar item.
@MainActor final class IslandWindowController {
    private unowned let model: AppModel

    private var panel: IslandPanel?
    private var hostingView: IslandHostingView<IslandWindowRoot>?
    private let probe = StageProbe()
    private var metrics: NotchMetrics?
    /// The layout the current stage was computed with.
    private var stagedLayout: IslandLayout?
    /// Every island rect (global) covered since the last settle. A transition
    /// that interrupts another must keep room for where the island still is,
    /// not only for its new endpoints; nil while resting.
    private var inFlightIslands: CGRect?
    private var isRestagePending = false
    private let settle = DelayedAction()
    private var screenObserver: (any NSObjectProtocol)?
    private var isStarted = false
    private var isSuspended = false
    /// Invalidates observation callbacks registered before the last start/stop.
    private var observationGeneration = 0
    /// Plays the island's outline on the render server while it moves.
    private lazy var outlineMotion = IslandOutlineMotion(model: model)

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        model.island.willTransition = { [weak self] from, to in
            self?.willTransition(from: from, to: to)
        }
        model.island.didTransition = { [weak self] from, to in
            self?.armSettle()
            self?.keyboardFollows(from: from, to: to)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reanchor() }
        }
        observationGeneration += 1
        observeLayout()
        reanchor()
        // `NI_NO_PREPARE=1` (measuring): Settings is built only when first opened.
        if ProcessInfo.processInfo.environment["NI_NO_PREPARE"] != "1" {
            prepareSettings(after: Self.settingsPreparationDelay)
            prepareShades()
        }
    }

    /// The fade style's black for the panel's pages, drawn ahead and unseen on the efficiency cores
    /// (`FadeShadeCache`): the first opening after launch then only shows it.
    private func prepareShades() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3), tolerance: .milliseconds(500))
            guard let self, self.isStarted, self.model.effectiveGlassStyle == .fade,
                  !self.model.island.presentation.isOpen else { return }
            let layout = self.model.layout
            let scale = self.panel?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            var sizes: [CGSize] = []
            for page in ExpandedPage.allCases {
                let size = layout.outline(for: .expanded(page)).size
                let shade = CGSize(width: size.width, height: size.height + IslandLayout.overdraw)
                if !sizes.contains(shade) { sizes.append(shade) }
            }
            MainThrift.lowPower(for: 0.3)
            await Task.yield()
            FadeShadeCache.prepare(solidDepth: IslandLayout.overdraw + layout.notch.height, sizes: sizes, scale: scale)
        }
    }

    /// Settings is built once, unseen, a while after launch (`SettingsSurfaceView.prepare`):
    /// its first opening then costs what any later one does (Energy Impact ~340 → ~40, measured).
    static let settingsPreparationDelay: Duration = .seconds(6)

    /// One piece of Settings per step, at background quality of service (efficiency cores), only
    /// while the island is closed: a step waits while it is open.
    private func prepareSettings(after delay: Duration) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay, tolerance: .milliseconds(200))
            guard let self, self.isStarted, let metrics = self.metrics else { return }
            guard !self.model.island.presentation.isOpen, !self.model.island.presentation.isBanner else {
                self.prepareSettings(after: .seconds(3))
                return
            }
            MainThrift.lowPower(for: 0.5)
            await Task.yield()
            if !SettingsWindow.isPrepared {
                let layout = self.model.layout
                let size = IslandSettingsView.surfaceSize(layout)
                let frame = CGRect(x: (metrics.notchRect.midX - size.width / 2).rounded(),
                                   y: metrics.screenFrame.maxY - layout.notch.height - size.height,
                                   width: size.width, height: size.height)
                SettingsWindow.prepare(model: self.model, frame: frame)
            } else if !SettingsWindow.prepareNextPage(model: self.model) {
                return
            }
            self.prepareSettings(after: .milliseconds(400))
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        observationGeneration += 1
        model.island.willTransition = nil
        model.island.didTransition = nil
        giveKeyboardBack()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        settle.cancel()
        inFlightIslands = nil
        panel?.orderOut(nil)
        SettingsWindow.current?.hide(fade: nil)
    }

    /// Screens asleep, session locked or system sleeping: nothing is visible, so
    /// the panel leaves the window list entirely and the window server stops
    /// compositing it.
    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        SettingsWindow.current?.setSuspended(suspended)
        if suspended {
            giveKeyboardBack()
            panel?.orderOut(nil)
        } else {
            // Displays may have changed while asleep.
            reanchor()
        }
    }

    // MARK: Keyboard

    /// The window that was key before the assistant took the keyboard, if it was one of ours
    /// (Settings, Customize); otherwise the keyboard goes back with `NSApp.deactivate()`.
    private weak var previousKeyWindow: NSWindow?
    private var resignObserver: (any NSObjectProtocol)?
    private var outsideClickMonitor: Any?
    /// Esc for Settings (the assistant handles its own: it steps back before it closes).
    private var escapeMonitor: Any?

    /// The assistant has the keyboard exactly while it is on screen.
    private func keyboardFollows(from: IslandPresentation, to: IslandPresentation) {
        if to.takesKeyboard, !from.takesKeyboard {
            takeKeyboard()
        } else if from.takesKeyboard, !to.takesKeyboard {
            giveKeyboardBack()
        }
    }

    /// Makes the island key and the app active, so keystrokes come here. It closes the assistant
    /// when it stops being key or when the user clicks anywhere else.
    private func takeKeyboard() {
        guard let panel, panel.isVisible, !panel.acceptsKeyboard else { return }
        if let key = NSApp.keyWindow, key !== panel { previousKeyWindow = key }
        panel.acceptsKeyboard = true
        panel.makeKey()
        // Key alone is not enough: the window server keeps sending keystrokes to the active app
        // (measured). The user just asked for the assistant (a click, a URL), so the cooperative
        // activation is granted; the app it takes over from gets it back on close (`deactivate`).
        NSApp.activate()
        // Except while the system asks for folder access (the first Files read): its prompt takes
        // the keyboard and the click that answers it, and the assistant waits for the answer.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.assistant.isAwaitingFileAccess else { return }
                // Our own popovers, menus and the colour panel take the keyboard for a moment and
                // give it back; only another app's window ends the assistant or Settings. Judged a
                // turn later, once the new key window is known — and while one of our own passing
                // windows is up (a popover opening or closing leaves no key window for a moment,
                // which ended Settings as a colour or a symbol was picked), not at all: the panel
                // takes the keyboard back once they are gone.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if NSApp.isActive, NSApp.keyWindow != nil { return }
                    if self.hasPassingWindow { self.reclaimKeyboardAfterPassingWindows(); return }
                    self.model.controller.closeKeyboardOverlay()
                }
            }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only Esc in the panel itself: in a popover it closes the popover first.
            guard event.keyCode == 53, let self, self.model.island.presentation.isSettings,
                  event.window === self.panel || event.window is SettingsWindow else { return event }
            // A popover open over Settings is not key (it took no keystroke yet), so its Esc lands
            // here: it is the popover's, not Settings'.
            if let popover = self.ownWindows(excludingPanel: true).first(where: { String(describing: type(of: $0)).contains("Popover") }) {
                popover.makeKey()
                popover.sendEvent(event)
                return nil
            }
            self.model.controller.closeSettings()
            return nil
        }
        // A global monitor sees clicks in other apps' windows: the clicks outside. Not only those:
        // while the app is not active (Settings opened from the island's gear: the panel never
        // activates it), a click in one of its popovers — a colour's tab, Delete Page… — is reported
        // here too, and so is one that a see-through pixel of the panel let pass. Judged by where it
        // landed: on the island or one of our own windows, it is ours.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, !self.model.assistant.isAwaitingFileAccess,
                  !self.isOverOwnUI(NSEvent.mouseLocation) else { return }
            self.model.controller.closeKeyboardOverlay()
        }
    }

    /// Our visible windows that take clicks (popovers, menus, the colour panel…), the panel too
    /// unless excluded. Overlays that let every click through (the anchor's, the cards') are not.
    private func ownWindows(excludingPanel: Bool) -> [NSWindow] {
        NSApp.windows.filter { window in
            window.isVisible && !window.ignoresMouseEvents && !(excludingPanel && window === panel)
        }
    }

    /// `point` (screen coordinates) is on the island as it is drawn, or on another of our windows.
    private func isOverOwnUI(_ point: NSPoint) -> Bool {
        if let panel, let hostingView, panel.isVisible,
           hostingView.islandRect.contains(panel.convertPoint(fromScreen: point)) {
            return true
        }
        return ownWindows(excludingPanel: true).contains { $0.frame.contains(point) }
    }

    /// One of our own windows that comes and goes over the panel: a popover, a menu, a sheet or an
    /// alert, the colour panel.
    private var hasPassingWindow: Bool {
        NSApp.modalWindow != nil || NSApp.windows.contains { window in
            guard window !== panel, !(window is SettingsWindow), window.isVisible else { return false }
            let name = String(describing: type(of: window))
            return name.contains("Popover") || name.contains("Menu") || window is NSColorPanel || window.isSheet
                || window.level.rawValue >= NSWindow.Level.modalPanel.rawValue
        }
    }

    /// Gives the panel the keyboard back once our passing windows are gone (it lost it to them), or
    /// ends Settings and the assistant if another app took it meanwhile. Checked a few times a
    /// second, only while such a window is up.
    private func reclaimKeyboardAfterPassingWindows() {
        Task { @MainActor [weak self] in
            while let self, self.panel?.acceptsKeyboard == true {
                try? await Task.sleep(for: .milliseconds(300))
                guard self.panel?.acceptsKeyboard == true else { return }
                if self.hasPassingWindow { continue }
                if NSApp.isActive {
                    if NSApp.keyWindow == nil {
                        if let settings = SettingsWindow.current, settings.isVisible { settings.makeKey() } else { self.panel?.makeKey() }
                    }
                } else {
                    self.model.controller.closeKeyboardOverlay()
                }
                return
            }
        }
    }

    /// After a folder-access prompt: the assistant is still open but no longer key, so keystrokes
    /// would go elsewhere. Takes the keyboard back (the user just answered a prompt it caused).
    func assistantNeedsKeyboard() {
        guard let panel, panel.acceptsKeyboard, model.island.presentation.takesKeyboard, !panel.isKeyWindow else { return }
        panel.makeKey()
        NSApp.activate()
    }

    /// Hands the keyboard back. Clearing `acceptsKeyboard` alone does not resign key (measured).
    private func giveKeyboardBack() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        guard let panel, panel.acceptsKeyboard else { return }
        if panel.isKeyWindow || NSApp.keyWindow is SettingsWindow {
            if let previous = previousKeyWindow, previous.isVisible, previous !== panel {
                previous.makeKey()
            } else {
                NSApp.deactivate()
            }
        }
        panel.acceptsKeyboard = false
        previousKeyWindow = nil
    }

    // MARK: Anchoring

    /// Finds the notch screen and puts the panel there. With no screen at all
    /// the panel stays hidden; the next screen-parameters notification retries.
    private func reanchor() {
        guard isStarted else { return }
        let next = ScreenLocator.preferred()
        if next != metrics || model.metrics != next {
            metrics = next
            model.updateMetrics(next)
        }
        guard next != nil else {
            panel?.orderOut(nil)
            Log.window.notice("No screen available; island hidden until one appears")
            return
        }
        let panel = ensurePanel()
        settle.cancel()
        stageResting(for: model.island.presentation)
        guard !isSuspended else { return }
        panel.orderFrontRegardless()
        hostingView?.setNeedsPointerRefresh()
    }

    private func ensurePanel() -> IslandPanel {
        if let panel { return panel }
        let hosting = IslandHostingView(rootView: IslandWindowRoot(model: model, probe: probe))
        hosting.onPointerEntered = { [weak model] in model?.controller.pointerEntered() }
        hosting.onPointerExited = { [weak model] in model?.controller.pointerExited() }
        hosting.onClick = { [weak model] in model?.controller.clicked() }
        hosting.onScroll = { [weak model] event in model?.controller.scrolled(event) ?? false }
        hosting.onDragEntered = { [weak model] in model?.controller.dragEntered() }
        hosting.onDragExited = { [weak model] in model?.controller.dragExited() }
        hosting.onDrop = { [weak model] urls in model?.controller.dropped(urls) ?? false }
        hosting.acceptsDrop = { [weak model] in
            guard let model else { return false }
            // A tile dragged out of our own shelf and back is not a new file.
            return model.preferences.shelfEnabled && !model.shelf.isDraggingOut
        }
        let panel = IslandPanel(contentRect: metrics?.notchRect ?? .zero)
        // A plain view is the content view, the hosting view only fills it: as a window's content
        // view, NSHostingView resizes a non-resizable window to its SwiftUI content every frame of
        // a transition (even with `sizingOptions = []`), which shrank the stage around the
        // animating island, pinned at its top-left corner, and crashed AppKit's constraints pass.
        let stage = IslandStageView(frame: CGRect(origin: .zero, size: panel.frame.size))
        hosting.frame = stage.bounds
        hosting.autoresizingMask = [.width, .height]
        stage.addSubview(hosting)
        panel.contentView = stage
        outlineMotion.attach(to: stage)
        model.island.outlineMover = outlineMotion
        self.panel = panel
        hostingView = hosting
        return panel
    }

    // MARK: Staging

    private func willTransition(from: IslandPresentation, to: IslandPresentation) {
        // Covering macOS's AirPods card: raised while ours grows, is shown and shrinks.
        if Self.covers(to) || Self.covers(from) { panel?.level = IslandPanel.coveringLevel }
        guard let metrics else { return }
        let layout = model.layout
        let fromRect = StageGeometry.islandFrame(for: from, layout: stagedLayout ?? layout, metrics: metrics)
        let toRect = StageGeometry.islandFrame(for: to, layout: layout, metrics: metrics)
        grow(toCover: fromRect.union(toRect))
        if to.isSettings, !from.isSettings, !from.isIdle { crossFadeToSettings() }
    }

    /// Into Settings the island's content cross-fades on the render server, as one picture: the
    /// panel's widgets (or Siri, or the pill) into Settings' ground. Faded by SwiftUI frame by
    /// frame, a busy main thread (Settings being set up, most of all the first time) held the fade
    /// still, and the widgets stood on the growing island for up to half a second (seen on video,
    /// v0.4.2 too). The island's own content swap is not animated then (`IslandContentStack`).
    private func crossFadeToSettings() {
        guard let layer = hostingView?.layer else { return }
        // What is on screen now (the grown stage, still the old content) is where the fade starts.
        CATransaction.flush()
        let fade = CATransition()
        fade.type = .fade
        fade.duration = Self.settingsCrossFade
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "settingsCrossFade")
    }

    /// As long as the content swap it replaces (`Motion.contentSwap`).
    static let settingsCrossFade: CFTimeInterval = 0.18

    private func grow(toCover islands: CGRect) {
        guard let metrics else { return }
        settle.cancel()
        let covered = inFlightIslands.map { $0.union(islands) } ?? islands
        inFlightIslands = covered
        stagedLayout = model.layout
        // Hit/hover region = the union too: the island is visibly large while it
        // closes, and a click on it then must not fall through.
        apply(frame: StageGeometry.transitionFrame(covering: covered, metrics: metrics), islands: covered)
    }

    /// Shrinks to the resting frame once the springs have settled, unless
    /// something newer happened meanwhile (which armed its own settle).
    private func armSettle() {
        let target = model.island.presentation
        let layout = model.layout
        settle.schedule(after: Motion.settleDuration(for: model.preferences.animationDuration)) { [weak self] in
            guard let self, self.model.island.presentation == target, self.model.layout == layout else { return }
            // Springs held mid-way (`demo/freeze`) have not settled: the stage stays large.
            guard LeanSpring.frozenTime == nil else { return }
            if !Self.covers(target) { self.panel?.level = IslandPanel.restingLevel }
            self.stageResting(for: target)
        }
    }

    /// The AirPods card, when the user chose to cover macOS's own with it.
    private static func covers(_ presentation: IslandPresentation) -> Bool {
        if case .banner(.airPods) = presentation {
            return AirPodsSystemCard.current == .cover
        }
        if case .banner(.levelCovering) = presentation { return true }
        return false
    }

    private func stageResting(for presentation: IslandPresentation) {
        guard let metrics else { return }
        let layout = model.layout
        inFlightIslands = nil
        stagedLayout = layout
        apply(
            frame: StageGeometry.restingFrame(for: presentation, layout: layout, metrics: metrics),
            islands: StageGeometry.islandFrame(for: presentation, layout: layout, metrics: metrics)
        )
    }

    private func apply(frame: CGRect, islands: CGRect) {
        guard let panel, let hostingView else { return }
        guard !hostingView.isInUpdatePass else {
            Log.window.error("stage change requested inside the hosting view's update pass; deferred")
            restageNextTurn()
            return
        }
        panel.stage(frame)
        hostingView.islandRect = StageGeometry.local(islands, in: frame)
        Log.window.debug("stage \(frame.logDescription, privacy: .public) island \(islands.logDescription, privacy: .public)")
    }

    /// Re-derives the stage from the state of the next turn (the frame asked for now may be stale
    /// by then): the in-flight union while a transition runs, else the resting frame.
    private func restageNextTurn() {
        guard !isRestagePending else { return }
        isRestagePending = true
        Task { [weak self] in
            guard let self else { return }
            self.isRestagePending = false
            guard self.isStarted, let metrics = self.metrics else { return }
            if let covered = self.inFlightIslands {
                self.apply(frame: StageGeometry.transitionFrame(covering: covered, metrics: metrics), islands: covered)
            } else {
                self.stageResting(for: self.model.island.presentation)
            }
        }
    }

    /// `demo/state`. The probe is where SwiftUI placed a box laid out exactly like the island, so a
    /// stale hosting size or offset shows up as `offset` ≠ 0 against the notch centre.
    func logState() {
        guard let panel, let hostingView, let metrics else {
            Log.window.notice("state: no panel or no screen")
            return
        }
        let presentation = model.island.presentation
        let expected = StageGeometry.islandFrame(for: presentation, layout: model.layout, metrics: metrics)
        let measured = probe.island.isNull ? CGRect.null : CGRect(
            x: panel.frame.minX + probe.island.minX,
            y: panel.frame.maxY - probe.island.maxY,
            width: probe.island.width,
            height: probe.island.height
        )
        let offset = measured.isNull ? .nan : measured.midX - metrics.notchRect.midX
        Log.window.notice("""
            state: \(String(describing: presentation), privacy: .public) \
            panel \(panel.frame.logDescription, privacy: .public) visible \(panel.isVisible, privacy: .public) \
            islandRect \(hostingView.islandRect.logDescription, privacy: .public) \
            hosting \(hostingView.frame.logDescription, privacy: .public) \
            swiftUI root \(self.probe.root.logDescription, privacy: .public) \
            island \(measured.logDescription, privacy: .public) expected \(expected.logDescription, privacy: .public) \
            offset \(offset, privacy: .public)
            """)
        if let root = panel.contentView?.layer {
            // The layer tree the render server draws, for energy work (what a frame re-renders).
            let path = NSTemporaryDirectory() + "ni-layers.txt"
            try? LayerDump.describe(root).write(toFile: path, atomically: true, encoding: .utf8)
            Log.window.notice("state: layer tree in \(path, privacy: .public)")
        }
    }

    // MARK: Layout changes

    /// A scale change keeps the presentation, so no transition stages the
    /// window for it; without this an island enlarged while open is clipped
    /// (legacy bug). Metric changes arrive here too, already handled by reanchor.
    private func observeLayout() {
        let generation = observationGeneration
        withObservationTracking {
            _ = model.layout
        } onChange: { [weak self] in
            // onChange runs before the new value is stored: read it next turn.
            Task { @MainActor in self?.layoutChanged(generation) }
        }
    }

    private func layoutChanged(_ generation: Int) {
        guard isStarted, generation == observationGeneration else { return }
        observeLayout()
        let layout = model.layout
        guard let metrics, let old = stagedLayout, old != layout else { return }
        let presentation = model.island.presentation
        let oldRect = StageGeometry.islandFrame(for: presentation, layout: old, metrics: metrics)
        let newRect = StageGeometry.islandFrame(for: presentation, layout: layout, metrics: metrics)
        guard oldRect != newRect else {
            stagedLayout = layout
            return
        }
        grow(toCover: oldRect.union(newRect))
        armSettle()
    }
}

/// Where SwiftUI last placed the root and an island-shaped probe, in hosting-view coordinates
/// (top-left origin). Plain storage, not observed: writing it must never re-render anything.
final class StageProbe {
    var root: CGRect = .null
    var island: CGRect = .null
}

/// Concrete root type for the hosting view, so the root is not type-erased
/// behind `AnyView`.
private struct IslandWindowRoot: View {
    let model: AppModel
    let probe: StageProbe

    var body: some View {
        IslandRootView()
            .environment(model)
            .background(alignment: .top) {
                // Laid out like the island (top-centred, size from the layout), never animated:
                // it reports where the island is headed, which is what `demo/state` compares.
                let size = model.layout.size(for: model.island.presentation)
                Color.clear
                    .frame(width: size.width, height: size.height)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { probe.island = $0 }
                    .transaction { $0.animation = nil }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { probe.root = $0 }
    }
}

extension CGRect {
    /// Compact, locale-free form for the log: `x,y w×h`.
    nonisolated var logDescription: String {
        isNull ? "null" : "\(minX),\(minY) \(width)×\(height)"
    }
}

/// `demo/state`'s dump of the island window's layers: class, frame, and whatever makes the render
/// server work per frame (masks, filters, shadows, backdrops, running animations).
enum LayerDump {
    static func describe(_ layer: CALayer, depth: Int = 0) -> String {
        var line = String(repeating: "  ", count: depth) + String(describing: type(of: layer))
        line += " \(layer.frame.integral)"
        if layer.isHidden { line += " hidden" }
        if layer.opacity < 1 { line += " opacity=\(layer.opacity)" }
        if layer.mask != nil { line += " MASK" }
        if layer.masksToBounds { line += " clips" }
        if let filters = layer.filters, !filters.isEmpty { line += " filters=\(filters)" }
        if let filters = layer.backgroundFilters, !filters.isEmpty { line += " bgfilters=\(filters)" }
        if let filter = layer.compositingFilter { line += " comp=\(filter)" }
        if layer.shadowOpacity > 0 { line += " SHADOW(\(layer.shadowOpacity), r \(layer.shadowRadius), path \(layer.shadowPath != nil))" }
        if layer.contents != nil { line += " contents" }
        if let keys = layer.animationKeys(), !keys.isEmpty { line += " anim=\(keys)" }
        if let mask = layer.mask { line += "\n" + String(repeating: "  ", count: depth + 1) + "mask: " + describe(mask, depth: depth + 2).trimmingCharacters(in: .whitespaces) }
        var out = line
        for sub in layer.sublayers ?? [] { out += "\n" + describe(sub, depth: depth + 1) }
        return out
    }
}
