import AppKit
import Observation
import SwiftUI

/// What the automatic close of an expanded island depends on, as plain values.
nonisolated struct AutoCloseInputs: Sendable, Equatable {
    var isExpanded = false
    var isPinned = false
    var isInteracting = false
    var isDropTargeted = false
    var isLingeringAfterDrop = false
    var isPointerInside = false
    var pointerHasVisited = false
}

nonisolated enum AutoCloseDecision: Sendable, Equatable {
    /// The island is not expanded; nothing to close.
    case notApplicable
    case keepOpen
    /// The pointer visited and left: close after the grace period.
    case closeAfterGrace
    /// Opened without the pointer (menu, URL, drop) and it never came: close after the timeout.
    case closeIfNeverVisited

    static func decide(_ i: AutoCloseInputs) -> AutoCloseDecision {
        guard i.isExpanded else { return .notApplicable }
        if i.isPinned || i.isInteracting || i.isDropTargeted || i.isLingeringAfterDrop || i.isPointerInside {
            return .keepOpen
        }
        return i.pointerHasVisited ? .closeAfterGrace : .closeIfNeverVisited
    }
}

/// When a showing banner stops counting down. The island controller is its only writer
/// (`BannerCenter.isHeld`): two writers would each undo the other's release and could leave a
/// banner up forever.
nonisolated enum BannerHold {
    static func isHeld(hasBanner: Bool, isBannerShowing: Bool, isPointerInside: Bool, isInteracting: Bool) -> Bool {
        // A drag in progress holds whatever banner is current, also when it replaced the one the
        // slider belongs to; the pointer holds only a banner it is actually over.
        hasBanner && (isInteracting || (isPointerInside && isBannerShowing))
    }
}

nonisolated extension BannerKind {
    /// Banners with their own controls (a slider, buttons). The pointer is over
    /// them to use those controls, so hovering or clicking must not expand the
    /// island out from under it.
    var isInteractive: Bool {
        switch self {
        case .level, .levelPill, .timerFinished: true
        case .power, .dropTarget, .airPods: false
        }
    }

    /// The direct answer to a key the user just pressed: shows even over a full-screen video, where
    /// nothing appears by itself. (While hidden, `AppModel` posts a level banner only for key
    /// presses, so a Control Center or AirPods change stays invisible there.)
    var showsWhileHidden: Bool {
        switch self {
        case .level, .levelPill: true
        case .power, .timerFinished, .dropTarget, .airPods: false
        }
    }
}

/// The island's policy brain: turns store state and pointer/drag events into
/// one presentation, and owns every timer that policy needs (one per concern).
@MainActor final class IslandController {
    /// While the pointer is over the space a closing island is leaving (not over the island as it now
    /// is), hover-open looks again this often until the pointer reaches the island or leaves.
    static let hoverPollInterval: TimeInterval = 0.08
    /// Pointer left the expanded island: wait this long before closing (the default of the user's
    /// `Preferences.closeDelay`).
    static let closeGrace: TimeInterval = Preferences.defaultCloseDelay
    /// Opened without the pointer: close if it has not arrived by then.
    static let unvisitedTimeout: TimeInterval = 6
    /// After a drop, stay on the shelf this long regardless of the pointer.
    static let dropLinger: TimeInterval = 1.5
    /// A drag ended elsewhere: clear the drop banner after this long, so a drop
    /// that did land on the island is handled before the banner goes away.
    static let dragEndClearDelay: TimeInterval = 0.45

    private unowned let model: AppModel
    private let pointerMonitor = PointerMonitor()

    /// Local mouse-up monitor, installed only while `isInteracting`; see `watchInteraction()`.
    private var releaseMonitor: Any?

    private let hoverDwell = DelayedAction()
    private let closeTimer = DelayedAction()
    private let unvisitedTimer = DelayedAction()
    private let dropLingerTimer = DelayedAction()
    private let dragEndTimer = DelayedAction()
    /// Re-checks the pointer against the assistant's real shape (see `updateAssistantHover`).
    private let assistantHoverCheck = DelayedAction()
    /// How often, while the pointer is in the hover region but not yet over the assistant.
    static let assistantHoverInterval: TimeInterval = 0.05

    private var isStarted = false
    /// Invalidates observation callbacks registered before the last start/stop.
    private var observationGeneration = 0

    private var wantsExpanded = false
    private var isDragInProgress = false
    private var openWasUserInitiated = false
    private var pointerHasVisited = false
    /// Set when the island closes under a resting pointer: hovering must not
    /// reopen it until the pointer has left once.
    private var suppressHoverOpenUntilExit = false
    /// `demo/hover`: a pointer that exists only for the controller, wherever the real one is.
    private var isPointerSimulated = false
    /// A full-screen window covers the notch screen (see `setHidden`).
    private var isHidden = false
    /// The assistant is open (see `openAssistant`).
    private var wantsAssistant = false
    /// Settings is open in the island (see `openSettings`).
    private var wantsSettings = false
    private let bandGuard = NotchBandGuard()

    /// Tracking-area state from the hosting view (exact island rect).
    private var trackingInside = false
    /// PointerMonitor state (rect + slack); non-nil only while expanded, and
    /// then authoritative, because tracking exits can go missing.
    private var monitorInside: Bool?

    private var pointerInside: Bool { monitorInside ?? trackingInside }

    init(model: AppModel) {
        self.model = model
        pointerMonitor.onChange = { [weak self] inside in
            self?.pointerMonitorChanged(inside)
        }
        bandGuard.screen = { [weak model] in model?.notchScreen }
        bandGuard.notchRect = { [weak model] in model?.metrics?.notchRect }
        bandGuard.isIslandOpen = { [weak model] in model?.island.presentation.isOpen ?? false }
        bandGuard.coverClicked = { [weak self] in
            guard let self, !self.model.assistant.isAwaitingFileAccess else { return }
            self.closeKeyboardOverlay()
        }
    }

    // MARK: Lifecycle

    /// Begins observing the inputs and applies the first presentation. Idempotent.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        model.banners.onExpire = { [weak self] kind in
            self?.bannerExpired(kind)
        }
        observationGeneration += 1
        observeInputs()
        inputsChanged()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        observationGeneration += 1
        model.banners.onExpire = nil
        for timer in [hoverDwell, closeTimer, unvisitedTimer, dropLingerTimer, dragEndTimer] { timer.cancel() }
        pointerMonitor.stop()
        monitorInside = nil
        setReleaseMonitor(installed: false)
    }

    // MARK: Full screen

    /// A full-screen window is on the physical notch screen and its menu bar hides there: keep it out
    /// of sight while the pointer goes into the notch (`NotchBandGuard`).
    func setFullscreenPresent(_ present: Bool) {
        bandGuard.setActive(present)
    }

    /// The notch screen moved or changed size: the menu-bar guard's band and zone follow.
    func notchGeometryChanged() {
        bandGuard.islandChanged()
    }

    // MARK: Hiding

    /// Steps aside for a video playing in full screen: nothing shows by itself, but the notch keeps its
    /// invisible hit target, so hovering, clicking or dropping a file there opens the island as
    /// usual, and it goes back to hiding when it closes. The menu-bar guard (`NotchBandGuard`)
    /// keeps the menu bar out of sight there meanwhile.
    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        // Step aside for the video, but not out from under a pointer that is using the panel: the
        // usual auto-close ends it once the pointer leaves, and hiding applies then. A panel closed
        // here gives up its pin too, so the next hover-open is not silently pinned over the video.
        if hidden, !pointerInside, !model.island.isInteracting {
            for timer in [hoverDwell, closeTimer, unvisitedTimer, dropLingerTimer] { timer.cancel() }
            if model.island.isPinned { model.island.isPinned = false }
            wantsExpanded = false
        }
        inputsChanged()
    }

    // MARK: Explicit intents

    func expand(page: ExpandedPage? = nil, pinned: Bool = false, userInitiated: Bool) {
        hoverDwell.cancel()
        if let page, model.island.page != page { model.island.page = page }
        if pinned, !model.island.isPinned { model.island.isPinned = true }
        if !wantsExpanded {
            wantsExpanded = true
            openWasUserInitiated = userInitiated
        }
        // Every open request starts the close policy afresh: whether the pointer is there now
        // decides between the grace and the never-visited timeout, and a timeout armed by an
        // earlier request (`open?page=timer`, then `open?page=shelf` 5 s later) must not cut this
        // one short.
        pointerHasVisited = pointerInside
        closeTimer.cancel()
        unvisitedTimer.cancel()
        inputsChanged()
    }

    /// Explicit close (menu, URL, a close button): also releases the pin, and closes the assistant.
    func collapse() {
        let closesOverlay = wantsAssistant || wantsSettings
        wantsAssistant = false
        wantsSettings = false
        close(releasingPin: true)
        // close() returns early when nothing was expanded (the assistant clears wantsExpanded), and
        // wantsAssistant is not observed: resolve here or the assistant stays on screen.
        if closesOverlay { inputsChanged() }
    }

    // MARK: Assistant

    /// Siri in the notch. From the open panel it takes the panel's place (and closing it goes back
    /// to the notch, not to the panel); from anywhere else it grows out of the notch. It shows even
    /// while the island is hidden for a full-screen video: the user asked for it.
    func openAssistant() {
        for timer in [hoverDwell, closeTimer, unvisitedTimer] { timer.cancel() }
        wantsExpanded = false
        if model.island.isPinned { model.island.isPinned = false }
        guard !wantsAssistant else { return }
        wantsAssistant = true
        openWasUserInitiated = true
        // The first opening sets Siri's views, the text field and the text input system up
        // (~110 ms over a few turns, Energy Impact ~110; later openings ~30 ms): on the
        // efficiency cores, a little slower, once.
        if !hasOpenedAssistant {
            hasOpenedAssistant = true
            MainThrift.lowPower(for: 0.65)
        }
        inputsChanged()
    }

    private var hasOpenedAssistant = false

    /// Settings in the island, on `pane`. It takes the open panel's or the assistant's place.
    func openSettings(pane: IslandSettingsPane? = nil) {
        for timer in [hoverDwell, closeTimer, unvisitedTimer] { timer.cancel() }
        if let pane { model.settingsPane = pane }
        wantsExpanded = false
        wantsAssistant = false
        if model.island.isPinned { model.island.isPinned = false }
        guard !wantsSettings else { return }
        wantsSettings = true
        openWasUserInitiated = true
        inputsChanged()
    }

    func closeSettings() {
        guard wantsSettings else { return }
        wantsSettings = false
        inputsChanged()
    }

    /// Esc, a click outside, or the island losing the keyboard: whichever of the two is open.
    func closeKeyboardOverlay() {
        closeAssistant()
        closeSettings()
    }

    func closeAssistant() {
        guard wantsAssistant else { return }
        wantsAssistant = false
        inputsChanged()
    }

    /// Pinning keeps the island open, so pinning a closed island opens it.
    func togglePinned() {
        if model.island.isPinned {
            model.island.isPinned = false
            reconcile()
        } else {
            expand(pinned: true, userInitiated: true)
        }
    }

    // MARK: Pointer

    /// `demo/hover`: pretend the pointer entered or left, without moving the real one.
    func simulatePointer(inside: Bool) {
        isPointerSimulated = inside
        if inside { pointerEntered() } else { pointerExited() }
    }

    func pointerEntered() {
        trackingInside = true
        // A tracking-area entry is proof enough while the monitor runs, too.
        if monitorInside != nil { monitorInside = true }
        pointerChanged()
    }

    func pointerExited() {
        trackingInside = false
        pointerChanged()
    }

    /// Expands a non-expanded island at once. Clicks while expanded belong to
    /// the panel's controls; pin is explicit (`togglePinned`), never a click.
    func clicked() {
        guard canOpenFromPointer else { return }
        expand(userInitiated: true)
    }

    // MARK: Swipe to Siri

    /// Downward scroll collected over the closed island (points; the gesture's own direction).
    private var swipeDown: CGFloat = 0
    private var swipeFired = false
    private var lastSwipeEvent: TimeInterval = 0

    /// Two fingers swiped down on the notch — or the wheel turned down over it — open Siri, once per
    /// gesture, when the user has that on (Settings ▸ Siri). Only on a closed island (idle, pill or
    /// notice): an open panel's own scroll views keep their scrolling.
    func scrolled(_ event: NSEvent) -> Bool {
        let settings = model.preferences.siri
        guard settings.swipeOpens, !model.island.presentation.isOpen else { return false }
        // A new gesture (or a wheel turned again after a pause) starts from zero.
        if event.phase == .began || (event.phase.isEmpty && event.momentumPhase.isEmpty
                                     && event.timestamp - lastSwipeEvent > 0.35) {
            swipeDown = 0
            swipeFired = false
        }
        lastSwipeEvent = event.timestamp
        if event.phase == .ended || event.phase == .cancelled || !event.momentumPhase.isEmpty {
            return swipeFired
        }
        // Fingers moving down: with natural scrolling the delta is positive.
        let delta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
        let points = event.hasPreciseScrollingDeltas ? delta : delta * 10
        swipeDown = max(0, swipeDown + points)
        if !swipeFired, swipeDown >= settings.swipeDistance {
            swipeFired = true
            openAssistant()
        }
        return true
    }

    // MARK: Drag and drop

    func dragEntered() {
        // A file dragged onto the notch goes to the shelf, over whatever the assistant was doing.
        wantsAssistant = false
        wantsSettings = false
        if !model.island.isDropTargeted { model.island.isDropTargeted = true }
        expand(page: .shelf, userInitiated: true)
    }

    func dragExited() {
        if model.island.isDropTargeted { model.island.isDropTargeted = false }
        reconcile()
    }

    func dropped(_ urls: [URL]) -> Bool {
        if model.island.isDropTargeted { model.island.isDropTargeted = false }
        guard !urls.isEmpty, model.preferences.shelfEnabled, !model.shelf.isDraggingOut else {
            reconcile()
            return false
        }
        model.shelf.add(urls)
        model.haptics.play(.drop)
        // The drag ended here; no need to wait for the monitor's end signal.
        dragEndTimer.cancel()
        isDragInProgress = false
        dropLingerTimer.schedule(after: Self.dropLinger) { [weak self] in self?.reconcile() }
        expand(page: .shelf, userInitiated: false)
        // The drop itself was the visit, wherever the pointer is reported to be.
        pointerHasVisited = true
        return true
    }

    func externalDragBegan() {
        dragEndTimer.cancel()
        guard !isDragInProgress else { return }
        isDragInProgress = true
        inputsChanged()
    }

    func externalDragEnded() {
        guard isDragInProgress else { return }
        dragEndTimer.schedule(after: Self.dragEndClearDelay) { [weak self] in
            guard let self else { return }
            self.isDragInProgress = false
            self.inputsChanged()
        }
    }

    // MARK: Resolution

    /// Recomputes the presentation from the current inputs and applies it.
    func inputsChanged() {
        let next = IslandResolver.resolve(resolverInputs())
        let from = model.island.presentation
        if next != from {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let animation = Motion.animation(
                from: from, to: next, reduceMotion: reduceMotion, duration: model.preferences.animationDuration
            )
            let spring = reduceMotion ? nil : Motion.spring(from: from, to: next, duration: model.preferences.animationDuration)
            let follows = Motion.surfaceFollowsOutline(from: from, to: next, style: model.effectiveGlassStyle)
            model.island.apply(next, animation: animation, spring: spring, surfaceFollows: follows)
            // What actually happened: a request from inside another transition is deferred.
            let applied = model.island.presentation
            if applied != from { presentationChanged(from: from, to: applied) }
            if applied.isOpen != from.isOpen { bandGuard.islandChanged() }
            // The assistant's query, search and answers live only while it is on screen.
            if applied.isAssistant, !from.isAssistant { model.assistant.begin() }
            if from.isAssistant, !applied.isAssistant {
                model.assistant.end()
                assistantHoverCheck.cancel()
                model.assistant.isPointerOver = false
            }
        }
        syncPointerMonitor()
        reconcile()
    }

    private func resolverInputs() -> IslandInputs {
        IslandInputs(
            // Read straight from the model as well: the feature loop that calls `setHidden` runs
            // on its own turn, and resolving first would flash the pill as a video goes full screen.
            isHidden: isHidden || model.hidesForFullscreenVideo,
            wantsAssistant: wantsAssistant,
            wantsSettings: wantsSettings,
            assistantRoom: model.assistant.room,
            wantsExpanded: wantsExpanded,
            page: model.island.page,
            banner: model.banners.current,
            isDragInProgress: isDragInProgress,
            countdownActive: model.timers.isCountdownActive,
            stopwatchActive: model.timers.isStopwatchActive,
            nowPlayingActive: model.preferences.showNowPlaying && model.media.isActive
        )
    }

    /// Re-arming observation of everything outside the controller that can
    /// change the presentation or the policy. `onChange` fires before the new
    /// value is stored, once per registration, so the recompute runs on the
    /// next main-actor turn — which also coalesces bursts into one pass.
    private func observeInputs() {
        let generation = observationGeneration
        withObservationTracking {
            _ = resolverInputs()
            _ = model.island.isPinned
            _ = model.island.isInteracting
            _ = model.island.isDropTargeted
            // Only reconcile writes it; any other write is undone on the next turn.
            _ = model.banners.isHeld
            _ = model.timers.countdown
            _ = model.layout
        } onChange: { [weak self] in
            Task { @MainActor in self?.observedInputsChanged(generation) }
        }
    }

    private func observedInputsChanged(_ generation: Int) {
        guard isStarted, generation == observationGeneration else { return }
        observeInputs()
        inputsChanged()
    }

    private func presentationChanged(from: IslandPresentation, to: IslandPresentation) {
        if to.isOpen, !from.isOpen {
            if openWasUserInitiated { model.haptics.play(.open) }
        } else if from.isOpen, !to.isOpen {
            model.haptics.play(.close)
            dropLingerTimer.cancel()
            if pointerInside { suppressHoverOpenUntilExit = true }
        }
    }

    // MARK: Policy

    /// Idempotent reconciliation of everything that follows from the current
    /// state: banner hold, the timer banner, hover-open and auto-close. Writes
    /// only on change, so running it from the observation loop cannot loop.
    private func reconcile() {
        let island = model.island
        let banners = model.banners
        let presentation = island.presentation

        watchInteraction()
        let hold = BannerHold.isHeld(
            hasBanner: banners.current != nil,
            isBannerShowing: presentation.isBanner,
            isPointerInside: pointerInside,
            isInteracting: island.isInteracting
        )
        if banners.isHeld != hold { banners.isHeld = hold }

        // "Done" / "+1 min" end the finished state; the banner follows the timer.
        if banners.current == .timerFinished, !isCountdownFinished {
            banners.dismiss(.timerFinished)
        }

        if pointerInside, !presentation.isExpanded { armHoverOpen() }

        switch AutoCloseDecision.decide(autoCloseInputs) {
        case .notApplicable, .keepOpen:
            closeTimer.cancel()
            unvisitedTimer.cancel()
        case .closeAfterGrace:
            unvisitedTimer.cancel()
            if !closeTimer.isPending {
                closeTimer.schedule(after: model.preferences.closeDelay) { [weak self] in self?.autoClose() }
            }
        case .closeIfNeverVisited:
            closeTimer.cancel()
            if !unvisitedTimer.isPending {
                unvisitedTimer.schedule(after: Self.unvisitedTimeout) { [weak self] in self?.autoClose() }
            }
        }
    }

    private var autoCloseInputs: AutoCloseInputs {
        AutoCloseInputs(
            isExpanded: model.island.presentation.isExpanded,
            isPinned: model.island.isPinned,
            isInteracting: model.island.isInteracting,
            isDropTargeted: model.island.isDropTargeted,
            isLingeringAfterDrop: dropLingerTimer.isPending,
            isPointerInside: pointerInside,
            pointerHasVisited: pointerHasVisited
        )
    }

    private func autoClose() {
        switch AutoCloseDecision.decide(autoCloseInputs) {
        case .closeAfterGrace, .closeIfNeverVisited: close(releasingPin: false)
        case .notApplicable, .keepOpen: break
        }
    }

    private func close(releasingPin: Bool) {
        for timer in [hoverDwell, closeTimer, unvisitedTimer, dropLingerTimer] { timer.cancel() }
        if releasingPin, model.island.isPinned { model.island.isPinned = false }
        guard wantsExpanded else { return }
        wantsExpanded = false
        inputsChanged()
    }

    /// A slider that disappears mid-drag (its banner replaced, the page switched) never reports the
    /// end of the drag, and a stale `isInteracting` would hold the banner and keep the island open
    /// for good. Drags that start in the panel deliver their mouse-up to this app, so a local
    /// monitor sees every release; it exists only while an interaction is in progress.
    private func watchInteraction() {
        setReleaseMonitor(installed: model.island.isInteracting)
    }

    private func setReleaseMonitor(installed: Bool) {
        if installed, releaseMonitor == nil {
            releaseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
                // The control handles this event after the monitor: judge on the next turn, when a
                // live slider has already ended its own drag.
                Task { @MainActor [weak self] in self?.interactionReleased() }
                return event
            }
        } else if !installed, let monitor = releaseMonitor {
            NSEvent.removeMonitor(monitor)
            releaseMonitor = nil
        }
    }

    private func interactionReleased() {
        guard model.island.isInteracting, NSEvent.pressedMouseButtons & 1 == 0 else { return }
        Log.island.notice("interaction ended without its control reporting it; releasing")
        model.island.isInteracting = false
    }

    private func pointerChanged() {
        let inside = pointerInside
        if inside != model.island.isHovering {
            Log.island.info("pointer \(inside ? "entered" : "left", privacy: .public)")
        }
        model.island.setHovering(inside)
        if inside {
            pointerHasVisited = true
        } else {
            suppressHoverOpenUntilExit = false
            hoverDwell.cancel()
        }
        if model.island.presentation.isAssistant {
            updateAssistantHover()
        } else {
            if model.assistant.isPointerOver { model.assistant.isPointerOver = false }
            reconcile()
        }
    }

    /// Over the assistant's field the suggestions come down; away, the field goes back up.
    ///
    /// "Over" is the real pointer on the assistant's current shape, not the hover region: while the
    /// suggestions fold away the region is still the larger island, and a pointer brought back
    /// quickly re-entered it and opened them again before it reached the field. While the pointer
    /// is in the region but not on the shape, this checks again every 50 ms (no tracking event
    /// comes for moves inside the region).
    private func updateAssistantHover() {
        guard model.island.presentation.isAssistant else {
            assistantHoverCheck.cancel()
            return
        }
        let over = pointerInside && isPointerOverIsland
        if model.assistant.isPointerOver != over {
            model.assistant.isPointerOver = over
            inputsChanged()
        }
        if pointerInside, !over {
            assistantHoverCheck.schedule(after: Self.assistantHoverInterval) { [weak self] in
                self?.updateAssistantHover()
            }
        } else {
            assistantHoverCheck.cancel()
        }
    }

    private func pointerMonitorChanged(_ inside: Bool) {
        // A simulated pointer (`demo/hover`) is not where the real one is: the monitor would close
        // the panel the simulation opened, and the dwell reopen it, over and over.
        guard pointerMonitor.isRunning, !isPointerSimulated else { return }
        monitorInside = inside
        pointerChanged()
    }

    /// Hover and clicks open the island except over a banner with its own controls.
    private var canOpenFromPointer: Bool {
        return switch model.island.presentation {
        case .expanded, .assistant, .settings: false
        case .banner(let kind): !kind.isInteractive
        case .idle, .compact: true
        }
    }

    private func armHoverOpen() {
        let preferences = model.preferences
        // A held button means a window drag or a selection is passing by; file
        // drags open the island through dragEntered instead.
        guard preferences.openOnHover, canOpenFromPointer, !suppressHoverOpenUntilExit,
              !hoverDwell.isPending, NSEvent.pressedMouseButtons == 0 else { return }
        scheduleHoverDwell()
    }

    /// The hover delay is counted from the moment the pointer is over the island as it now is. The
    /// hover region can be larger — while an island closes it still covers the open panel, so a click
    /// on the visibly large island is not lost — and a pointer brought back into that space must not
    /// reopen the island before it actually reaches the notch.
    private func scheduleHoverDwell() {
        let isOverIsland = isPointerOverIsland
        let delay = isOverIsland ? model.preferences.hoverDelay : Self.hoverPollInterval
        hoverDwell.schedule(after: delay) { [weak self] in
            self?.hoverDwellElapsed(wasOverIsland: isOverIsland)
        }
    }

    private func hoverDwellElapsed(wasOverIsland: Bool) {
        guard pointerInside, canOpenFromPointer, model.preferences.openOnHover, !suppressHoverOpenUntilExit else { return }
        if wasOverIsland, isPointerOverIsland {
            expand(userInitiated: true)
        } else {
            scheduleHoverDwell()
        }
    }

    /// Whether the real pointer is over the island's current shape (the notch, the pill, the banner),
    /// not merely inside the stage's hover region.
    private var isPointerOverIsland: Bool {
        guard !isPointerSimulated, let metrics = model.metrics else { return true }
        let island = StageGeometry.islandFrame(for: model.island.presentation, layout: model.layout, metrics: metrics)
        // One point taller: a pointer pushed against the top of the screen sits on the island's top
        // edge, which `contains` would exclude.
        let region = CGRect(x: island.minX, y: island.minY, width: island.width, height: island.height + 1)
        return region.contains(NSEvent.mouseLocation)
    }

    /// The monitor runs exactly while the island is expanded and a screen exists. Not for the
    /// assistant: the app is active then, and pointer moves outside our windows do not reach global
    /// monitors; the tracking area follows the assistant's field and list instead.
    /// Not while pinned: a pinned island stays open wherever the pointer is, so the monitor's one job
    /// (never leaving the island stuck open) is moot, and it would wake the app on every pointer move
    /// anywhere for as long as the pin lasts. The tracking area covers hover meanwhile, and unpinning
    /// restarts the monitor, which judges the pointer at once.
    private func syncPointerMonitor() {
        let presentation = model.island.presentation
        guard presentation.isExpanded, !model.island.isPinned, let metrics = model.metrics else {
            guard pointerMonitor.isRunning else { return }
            pointerMonitor.stop()
            monitorInside = nil
            model.island.setHovering(pointerInside)
            return
        }
        // Reports synchronously through onChange when the state differs.
        pointerMonitor.start(region: StageGeometry.islandFrame(for: presentation, layout: model.layout, metrics: metrics))
    }

    // MARK: Timer banner

    private var isCountdownFinished: Bool {
        if case .finished = model.timers.countdown { return true }
        return false
    }

    /// A finished-timer banner that times out (30 s) acknowledges the timer, so
    /// the compact bell does not linger forever.
    private func bannerExpired(_ kind: BannerKind) {
        if kind == .timerFinished, isCountdownFinished { model.timers.acknowledge() }
    }
}
