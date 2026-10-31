import AppKit
import Observation
import ScreenCaptureKit
import SwiftUI

/// The anchored window shown up to the top of the screen: a live copy of it, in line with the menu
/// bar and the notch, on an island-black stage that grows out of the notch.
///
/// macOS keeps every other app's window under the menu bar, so the real window stays there (a menu
/// bar lower, right behind the copy) and the copy is what is seen: the window is streamed by itself
/// (`SCContentFilter` of one window, at its pixel size, no cursor or shadow, not opaque, so its own
/// corners come through) and each frame's surface goes straight into a layer on the stream's queue.
/// Clicks, drags, scrolls and hovering on the copy are handed to the real window where it has that
/// point (`AnchorStageLayout.forwarded`); a click brings its app to the front first, so the keyboard
/// types into it. While the app shows a sheet or another window over the stage, the stage steps
/// aside and the real window is used directly.
///
/// Only with Screen Recording (asked for the first time a window is anchored); without it the real
/// window alone, under the menu bar. The stream runs only while the stage is up; frames arrive only
/// when the window changes, as often as the notch screen shows them (60 a second, 120 on a ProMotion
/// screen; 60 in Low Power Mode), whichever app is in front: a copy that drops frames reads as a
/// stuttering window. macOS shows its screen-sharing indicator meanwhile.
///
/// The stage is on every space, full-screen ones too: in a full-screen app the copy stays over it,
/// though the real window stays on its own space (another app's window cannot be put on one). Its
/// app is not brought forward there (that would switch to the window's space): hovering and scrolls
/// reach the window as they are, a click only where the app takes the first click on an inactive
/// window, and the keyboard stays with the full-screen app.
@Observable final class AnchorMirror {
    /// Screen Recording is given to the app.
    private(set) var isAllowed = CGPreflightScreenCaptureAccess()
    /// The stage is on screen.
    private(set) var isShowing = false

    /// The least, whatever the screen or the power mode.
    static let minimumFrameRate = 60
    /// `NI_ANCHOR_FPS=<n>` (measuring only): the stream capped at n frames a second instead.
    static let forcedRate = ProcessInfo.processInfo.environment["NI_ANCHOR_FPS"].flatMap(Int.init).map { max(1, $0) }
    /// Over a full-screen app, while only unchanged frames come (the stream sends a window on
    /// another space at its full rate, changed or not): this many a second, and the full rate again
    /// at the first change. `NI_ANCHOR_QUIET_FPS=<n>` (measuring only; 0: never lowered).
    static let quietRate = ProcessInfo.processInfo.environment["NI_ANCHOR_QUIET_FPS"].flatMap(Int.init).map { max(0, $0) } ?? 10

    /// "Release" beside the notch.
    @ObservationIgnored var onRelease: (() -> Void)?
    /// The tab at the window's top was dragged (the setting follows).
    @ObservationIgnored var onRaisedChanged: ((Bool) -> Void)?

    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var isPaused = false
    /// The real window is not on the space in front (a full-screen app is).
    @ObservationIgnored private var isAway = false
    /// Only unchanged frames have come for a while.
    @ObservationIgnored private var isQuiet = false
    /// Dragged up by the tab at its top.
    @ObservationIgnored private var isRaised = false
    /// How far the island reaches out beside the notch on each side right now (its compact ears,
    /// with what is playing): the name and Release move out past it.
    @ObservationIgnored private var islandReach: CGFloat = 0
    @ObservationIgnored private var held: WindowAnchor.Held?
    @ObservationIgnored private var screen: AnchorScreen?
    /// A sheet or another window of the app lies over the stage.
    @ObservationIgnored private var isOverlaid = false
    @ObservationIgnored private var hasAsked = false

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var output: MirrorOutput?
    @ObservationIgnored private var streamedWindow: CGWindowID?
    @ObservationIgnored private var streamedSize: CGSize = .zero
    @ObservationIgnored private var streamedRate = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var overlayGeneration = 0
    @ObservationIgnored private var panel: StagePanel?
    /// The window whose sharing was stopped from macOS's indicator: not streamed again while held.
    @ObservationIgnored private var declined: CGWindowID?
    @ObservationIgnored private var stopWatch: StopWatch?
    @ObservationIgnored private var activation: (any NSObjectProtocol)?
    @ObservationIgnored private var powerState: (any NSObjectProtocol)?

    init() {}

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }

    /// macOS's own prompt, once per launch at most.
    func requestAccess() {
        hasAsked = true
        isAllowed = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        reconcile()
    }

    func refreshAccess() {
        let allowed = CGPreflightScreenCaptureAccess()
        if allowed != isAllowed { isAllowed = allowed }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled { refreshAccess() }
        reconcile()
    }

    /// A full-screen app in front: the real window is on another space.
    func setAway(_ away: Bool) {
        guard away != isAway else { return }
        isAway = away
        updateRate()
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        reconcile()
    }

    /// The picture as high as it goes, or exactly over the real window (redrawn at once while it is up).
    func setRaised(_ raised: Bool) {
        guard raised != isRaised else { return }
        isRaised = raised
        if isShowing { reconcile() }
    }

    /// The island's compact ears came or went: the name and Release beside the notch make room.
    func setIslandReach(_ reach: CGFloat) {
        guard reach != islandReach else { return }
        islandReach = reach
        if isShowing { reconcile() }
    }

    /// The anchored window (nil: none) on the notch screen.
    func update(held: WindowAnchor.Held?, screen: AnchorScreen?) {
        if held?.window.windowID != self.held?.window.windowID {
            isOverlaid = false
            declined = nil
        }
        self.held = held
        self.screen = screen
        if held != nil, isEnabled, !isAllowed, !hasAsked { requestAccess() }
        reconcile()
    }

    /// The app opened, closed or focused a window: the stage steps aside while one lies over it.
    func appWindowsChanged() {
        guard let held, let layout = layout(held) else { return }
        overlayGeneration += 1
        let generation = overlayGeneration
        let pid = held.window.pid, own = held.window.windowID
        Task.detached(priority: .userInitiated) {
            // Its other windows in front of it (a sheet, a dialog): the list is front to back. Not on
            // this space (a full-screen app in front), nothing of the app lies over it here.
            let windows = AXWorker.serverWindows()
            let front = windows.contains { $0.id == own } ? windows.prefix { $0.id != own } : []
            let overlaid = front.contains { $0.pid == pid && layout.isOverlaid(by: $0.frame) }
            await MainActor.run { [weak self] in
                guard let self, self.overlayGeneration == generation, overlaid != self.isOverlaid else { return }
                self.isOverlaid = overlaid
                self.reconcile()
            }
        }
    }

    private func layout(_ held: WindowAnchor.Held) -> AnchorStageLayout? {
        screen.map { AnchorStageLayout(screen: $0, rest: held.rest, placement: isRaised ? .belowWindow : .menuBar) }
    }

    private func reconcile() {
        guard isEnabled, isAllowed, !isPaused, let held, !held.isDormant, let windowID = held.window.windowID,
              let screen, let layout = layout(held), windowID != declined else {
            return tearDown()
        }
        if isOverlaid {
            hide(animated: true)
            return
        }
        if streamedWindow != windowID || streamedSize != held.rest.size { start(windowID, held: held) }
        show(layout, screen: screen, held: held)
    }

    // MARK: The stream

    /// The stream's cap, in frames a second: what the copy shows is the notch screen's refresh rate
    /// (60 at least; 60 in Low Power Mode). Asked for exactly that, a frame that comes a hair early
    /// is dropped (57–58 of a window's 60 were shown); twice the screen's rate lets every one
    /// through, as the window cannot change faster than the screen. Below the screen's rate (Low
    /// Power Mode on a 120 Hz screen) a fifth more.
    private var rate: Int {
        if let forced = Self.forcedRate { return forced }
        if isAway, isQuiet, Self.quietRate > 0 { return Self.quietRate }
        let notch = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        let screen = max(Self.minimumFrameRate, notch?.maximumFramesPerSecond ?? 0)
        let shown = ProcessInfo.processInfo.isLowPowerModeEnabled ? Self.minimumFrameRate : screen
        return shown < screen ? shown * 6 / 5 : screen * 2
    }

    private static func configuration(size: CGSize, rate: Int) -> SCStreamConfiguration {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let configuration = SCStreamConfiguration()
        configuration.width = Int((size.width * scale).rounded())
        configuration.height = Int((size.height * scale).rounded())
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(rate))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.shouldBeOpaque = false
        configuration.backgroundColor = .clear
        configuration.queueDepth = 3
        return configuration
    }

    private func updateRate() {
        guard let stream, let held else { return }
        let rate = rate
        guard rate != streamedRate else { return }
        streamedRate = rate
        let configuration = Self.configuration(size: held.rest.size, rate: rate)
        Task { try? await stream.updateConfiguration(configuration) }
    }

    private func start(_ windowID: CGWindowID, held: WindowAnchor.Held) {
        stopStream()
        generation += 1
        let generation = generation
        streamedWindow = windowID
        streamedSize = held.rest.size
        let panel = panel ?? StagePanel()
        self.panel = panel
        isQuiet = false
        let output = MirrorOutput(layer: panel.stage.surface) { [weak self] quiet in
            Task { @MainActor in self?.quietChanged(quiet, generation: generation) }
        }
        self.output = output
        streamedRate = rate
        let configuration = Self.configuration(size: held.rest.size, rate: streamedRate)
        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    Log.anchor.notice("mirror: the window is not shareable")
                    return
                }
                let watch = StopWatch { [weak self] in self?.stopped(windowID, generation: generation) }
                let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: watch)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: MirrorOutput.queue)
                try await stream.startCapture()
                guard let self, self.generation == generation else {
                    try? await stream.stopCapture()
                    return
                }
                self.stream = stream
                self.stopWatch = watch
                Log.anchor.notice("mirror: streaming window \(windowID, privacy: .public)")
            } catch {
                Log.anchor.notice("mirror: \(error.localizedDescription, privacy: .public)")
                guard let self, self.generation == generation else { return }
                self.streamedWindow = nil
                self.refreshAccess()
            }
        }
        if activation == nil {
            activation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appWindowsChanged() }
            }
        }
        // The frame rate follows Low Power Mode.
        if powerState == nil {
            powerState = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateRate() }
            }
        }
    }

    /// Unchanged frames only for a while, or the first change after them.
    private func quietChanged(_ quiet: Bool, generation: Int) {
        guard generation == self.generation, quiet != isQuiet else { return }
        isQuiet = quiet
        updateRate()
    }

    /// macOS ended the stream: its sharing was stopped from the window's indicator (or the window
    /// can no longer be shared). The real window is used, under the menu bar.
    private func stopped(_ windowID: CGWindowID, generation: Int) {
        guard generation == self.generation else { return }
        Log.anchor.notice("mirror: the stream was stopped by the system")
        declined = windowID
        stream = nil
        reconcile()
    }

    private func stopStream() {
        generation += 1
        stopWatch = nil
        if let stream { Task { try? await stream.stopCapture() } }
        stream = nil
        output = nil
        streamedWindow = nil
        streamedSize = .zero
    }

    // MARK: The stage

    private func notchRect(_ screen: AnchorScreen, in layout: AnchorStageLayout) -> CGRect {
        CGRect(x: screen.frame.midX - screen.notch.width / 2 - layout.frame.minX, y: 0,
               width: screen.notch.width, height: screen.notch.height)
    }

    private func show(_ layout: AnchorStageLayout, screen: AnchorScreen, held: WindowAnchor.Held) {
        guard let panel else { return }
        let app = NSRunningApplication(processIdentifier: held.window.pid)
        panel.stage.onRelease = { [weak self] in self?.onRelease?() }
        panel.stage.onRaised = { [weak self] raised in
            self?.setRaised(raised)
            self?.onRaisedChanged?(raised)
        }
        panel.stage.configure(layout: layout, target: StageTarget(pid: held.window.pid, windowID: held.window.windowID ?? 0),
                              appName: app?.localizedName ?? "", icon: app?.icon, notch: notchRect(screen, in: layout), islandReach: islandReach)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = CGRect(x: layout.frame.minX, y: top - layout.frame.maxY, width: layout.frame.width, height: layout.frame.height)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        guard !(panel.isVisible && isShowing) else { return }
        let notch = notchRect(screen, in: layout)
        // Up only with a frame in it: never an empty stage over the menu bar.
        output?.whenFirstFrame { [weak self, weak panel] in
            guard let self, let panel, self.panel === panel, !self.isOverlaid, self.held != nil else { return }
            panel.orderFrontRegardless()
            panel.stage.grow(from: notch)
            if !self.isShowing { self.isShowing = true }
        }
    }

    private func hide(animated: Bool) {
        guard let panel, panel.isVisible else {
            if isShowing { isShowing = false }
            return
        }
        if animated, let screen, let held, let layout = layout(held) {
            panel.stage.shrink(into: notchRect(screen, in: layout)) { [weak panel] in panel?.orderOut(nil) }
        } else {
            panel.orderOut(nil)
        }
        if isShowing { isShowing = false }
    }

    private func tearDown() {
        hide(animated: false)
        if stream != nil || streamedWindow != nil {
            stopStream()
            Log.anchor.notice("mirror: stopped")
        }
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        if let powerState { NotificationCenter.default.removeObserver(powerState) }
        powerState = nil
        panel = nil
    }
}

/// Hears the stream end without being asked to.
nonisolated final class StopWatch: NSObject, SCStreamDelegate, @unchecked Sendable {
    private let stopped: @MainActor @Sendable () -> Void

    init(_ stopped: @escaping @MainActor @Sendable () -> Void) {
        self.stopped = stopped
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let stopped = stopped
        Task { @MainActor in stopped() }
    }
}

/// Takes the stream's frames on its own queue and hands each surface to the layer there.
///
/// A frame that is the same, pixel for pixel, as the one on screen is not put in:
/// the copy lies over the real window, so the window server counts every frame the copy shows as a
/// change of the window under it, and the stream would send it back as a new frame, a loop at the
/// stream's full rate (60 a second of an unchanged window: twice the energy of the copy at rest).
nonisolated final class MirrorOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    static let queue = DispatchQueue(label: "notchisland.anchor.mirror", qos: .userInitiated)

    /// `NI_TRACE=1`: frames put in and frames left out as unchanged, logged every two seconds while they come.
    static let counts = ProcessInfo.processInfo.environment["NI_TRACE"] == "1"
    /// `NI_ANCHOR_COMPARE=0` (measuring only): every frame put in, unchanged or not.
    static let compares = ProcessInfo.processInfo.environment["NI_ANCHOR_COMPARE"] != "0"

    /// Unchanged frames only for this long: quiet.
    static let quietAfter: CFTimeInterval = 0.5

    private let layer: CALayer
    /// Called on `queue`: only unchanged frames for `quietAfter` (true), the first change after them (false).
    private let onQuiet: @Sendable (Bool) -> Void
    /// All only touched on `queue`.
    private var hasFrame = false
    private var waiting: [@MainActor @Sendable () -> Void] = []
    /// The frame in the layer, kept so the stream does not reuse its surface while it is shown.
    private var shown: CVPixelBuffer?
    /// Where the last frame differed from the one before: looked at first.
    private var hint = 0
    private var unchangedSince: CFTimeInterval?
    private var isQuiet = false
    /// `NI_TRACE`: the first change after a quiet spell, until the frames come at full rate again.
    private var wake: (start: CFTimeInterval, last: CFTimeInterval, frames: Int)?
    private var counted = (shown: 0, same: 0)
    private var countStart: CFTimeInterval = 0

    init(layer: CALayer, onQuiet: @escaping @Sendable (Bool) -> Void = { _ in }) {
        self.layer = layer
        self.onQuiet = onQuiet
    }

    /// Runs on the main actor once a frame is in the layer (at once if one already is).
    func whenFirstFrame(_ work: @escaping @MainActor @Sendable () -> Void) {
        Self.queue.async {
            if self.hasFrame { Task { @MainActor in work() } } else { self.waiting.append(work) }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first, let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(buffer), let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue() else { return }
        if Self.compares, let shown {
            let dirty = (info[.dirtyRects] as? [NSDictionary] ?? []).compactMap { CGRect(dictionaryRepresentation: $0) }
            let row = Self.difference(pixels, shown, hint: hint, rects: dirty)
            guard let row else {
                if Self.counts { count(same: true) }
                unchanged()
                return
            }
            hint = row
        }
        changed()
        shown = pixels
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = surface
        CATransaction.commit()
        if Self.counts { count(same: false) }
        guard !hasFrame else { return }
        hasFrame = true
        let waiting = waiting
        self.waiting = []
        Task { @MainActor in waiting.forEach { $0() } }
    }

    private func unchanged() {
        let now = CACurrentMediaTime()
        guard let since = unchangedSince else {
            unchangedSince = now
            return
        }
        guard !isQuiet, now - since >= Self.quietAfter else { return }
        isQuiet = true
        onQuiet(true)
    }

    private func changed() {
        unchangedSince = nil
        let now = CACurrentMediaTime()
        if isQuiet {
            isQuiet = false
            onQuiet(false)
            if Self.counts {
                wake = (now, now, 1)
                Log.anchor.notice("mirror: changed after quiet at \(now, privacy: .public)")
            }
        } else if Self.counts, let wake {
            // Full rate again: two frames less than 25 ms apart.
            if now - wake.last < 0.025 {
                Log.anchor.notice("mirror: full rate \(Int((now - wake.start) * 1000), privacy: .public) ms after the first change, \(wake.frames + 1, privacy: .public) frames")
                self.wake = nil
            } else {
                self.wake = (wake.start, now, wake.frames + 1)
            }
        }
    }

    /// The first row (pixels, from the top) where the two frames differ; nil: none, the frames are
    /// the same. Every row counts: the stream's changed rectangles leave out what an app draws in a
    /// layer of its own (Safari's video and scrolling), so they only say where to look first —
    /// after `hint` (where the last frame differed). A frame that changed costs a row or two of
    /// comparing; an unchanged one the whole frame, once (left out, it ends the loop).
    static func difference(_ new: CVPixelBuffer, _ old: CVPixelBuffer, hint: Int = 0, rects: [CGRect] = []) -> Int? {
        let width = CVPixelBufferGetWidth(new), height = CVPixelBufferGetHeight(new)
        guard width == CVPixelBufferGetWidth(old), height == CVPixelBufferGetHeight(old), height > 0,
              CVPixelBufferGetPixelFormatType(new) == kCVPixelFormatType_32BGRA,
              CVPixelBufferGetPixelFormatType(old) == kCVPixelFormatType_32BGRA else { return 0 }
        CVPixelBufferLockBaseAddress(new, .readOnly)
        CVPixelBufferLockBaseAddress(old, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(new, .readOnly)
            CVPixelBufferUnlockBaseAddress(old, .readOnly)
        }
        guard let a = CVPixelBufferGetBaseAddress(new), let b = CVPixelBufferGetBaseAddress(old) else { return 0 }
        let rowA = CVPixelBufferGetBytesPerRow(new), rowB = CVPixelBufferGetBytesPerRow(old), length = width * 4
        func differs(_ y: Int) -> Bool { memcmp(a + y * rowA, b + y * rowB, length) != 0 }
        if hint >= 0, hint < height, differs(hint) { return hint }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        for rect in rects {
            let area = rect.integral.intersection(bounds)
            guard !area.isNull, area.height > 0 else { continue }
            if let y = (Int(area.minY)..<Int(area.maxY)).first(where: differs) { return y }
        }
        return (0..<height).first(where: differs)
    }

    private func count(same: Bool) {
        let now = CACurrentMediaTime()
        if same { counted.same += 1 } else { counted.shown += 1 }
        if countStart == 0 || now - countStart > 4 {
            // After a pause (nothing came): a new count, not an average with the pause in it.
            countStart = now
            counted = same ? (0, 1) : (1, 0)
            return
        }
        let elapsed = now - countStart
        guard elapsed >= 2 else { return }
        let shown = Int((Double(counted.shown) / elapsed).rounded()), left = Int((Double(counted.same) / elapsed).rounded())
        Log.anchor.notice("mirror: \(shown, privacy: .public) frames/s shown, \(left, privacy: .public) unchanged left out")
        countStart = now
        counted = (0, 0)
    }
}

/// Whose window the stage stands for.
nonisolated struct StageTarget: Equatable, Sendable {
    var pid: pid_t
    var windowID: CGWindowID
}

/// The stage's window: over the menu bar (under the island, which draws the notch over it), never
/// key, never activating: the real window's app is the one that takes the keyboard.
final class StagePanel: NSPanel {
    let stage = StageView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        // On every space and over full-screen apps, like the island (the level alone does not put
        // it there); stationary keeps Mission Control from moving it.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = stage
        setAccessibilityLabel(String(localized: "Anchored window, live copy"))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The stage: the island-black backdrop with the shoulders, the window's picture, the app's name
/// and Release beside the notch, and a tab at the picture's top that raises it. Events on the rest of
/// the picture go to the real window.
final class StageView: NSView {
    /// Where the frames go.
    let surface = CALayer()
    private let container = CALayer()
    private let backdrop = CAShapeLayer()
    private var raiseTab: UnclickableHosting<StageRaiseTab>?
    private var leadingEar: NSHostingView<StageEar>?
    private var trailingEar: NSHostingView<StageEar>?
    private var layout: AnchorStageLayout?
    private var target: StageTarget?
    private var tracking: NSTrackingArea?
    private var raiseDwell: Timer?
    /// A press on the picture: its drag and release go to the real window too, wherever the pointer goes.
    private var isForwarding = false
    /// The notch in the stage, which the tab hangs under.
    private var notch: CGRect = .zero
    /// A drag of the tab: where it started and how far the picture is up now.
    private var tabDrag: (startY: CGFloat, startRaise: CGFloat, raise: CGFloat)?
    /// While its app comes to the front: the events to send once it is there (nil: none held).
    private var queued: [CGEvent]?
    var onRelease: (() -> Void)?
    var onRaised: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isGeometryFlipped = true
        backdrop.fillColor = NSColor.black.cgColor
        surface.contentsGravity = .resize
        container.addSublayer(backdrop)
        container.addSublayer(surface)
        layer?.addSublayer(container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(layout: AnchorStageLayout, target: StageTarget, appName: String, icon: NSImage?, notch: CGRect,
                   islandReach: CGFloat = 0) {
        self.target = target
        self.notch = notch
        if layout != self.layout {
            self.layout = layout
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let bounds = CGRect(origin: .zero, size: layout.frame.size)
            container.frame = bounds
            backdrop.frame = bounds
            backdrop.path = IslandShapeGeometry(rect: bounds, bottomRadius: layout.bottomRadius, shoulderRadius: layout.shoulder,
                                                topInset: 0).path().cgPath
            if tabDrag == nil { surface.frame = layout.copy }
            CATransaction.commit()
        }
        let release: () -> Void = { [weak self] in self?.onRelease?() }
        placeRaiseTab(layout)
        // Beside the notch: the name to its left, Release to its right.
        // Past the island's own ears when they are out (what is playing beside the notch): the
        // notch reads as widened by them, the name and Release just outside.
        let reach = islandReach
        let leading = host(leadingEar, StageEar(side: .leading, appName: appName, icon: icon, inset: reach, release: release))
        let trailing = host(trailingEar, StageEar(side: .trailing, appName: appName, icon: icon, inset: reach, release: release))
        leadingEar = leading
        trailingEar = trailing
        // Measured from the content (a hosting view with no sizing options reports no fitting size).
        let room = max(0, (layout.copy.width - notch.width) / 2)
        let height = max(notch.height, layout.band)
        let leadingWidth = min(StageEar.width(side: .leading, appName: appName, hasIcon: icon != nil, inset: reach), room)
        let trailingWidth = min(StageEar.width(side: .trailing, appName: appName, hasIcon: icon != nil, inset: reach), room)
        // Each reaches under the notch (behind its rounded bottom corners), so no title bar shows between.
        let under = StageEar.underNotch
        leading.frame = CGRect(x: notch.minX + under - leadingWidth, y: 0, width: leadingWidth, height: height)
        trailing.frame = CGRect(x: notch.maxX - under, y: 0, width: trailingWidth, height: height)
    }

    // MARK: The tab at the window's top

    /// How long the pointer rests on the window's top edge before the tab comes: passing over the
    /// edge on the way to the menu bar brings nothing up.
    private static let raiseDwell: TimeInterval = 0.2

    /// Where the tab stays once it is up: the picture's top, down to just under the tab.
    private func raiseZone(_ layout: AnchorStageLayout) -> CGRect {
        CGRect(x: layout.copy.minX, y: layout.copy.minY, width: layout.copy.width,
               height: raiseTabFrame(layout).maxY + 6 - layout.copy.minY)
    }

    /// Centred under the notch, on the window's title bar.
    private func raiseTabFrame(_ layout: AnchorStageLayout) -> CGRect {
        let size = StageRaiseTab.size
        return CGRect(x: layout.frame.width / 2 - size.width / 2, y: max(notch.maxY, layout.copy.minY) + 3,
                      width: size.width, height: size.height)
    }

    private func placeRaiseTab(_ layout: AnchorStageLayout) {
        let root = StageRaiseTab(isRaised: layout.offset > 0)
        let tab: UnclickableHosting<StageRaiseTab>
        if let raiseTab {
            tab = raiseTab
            tab.rootView = root
        } else {
            tab = UnclickableHosting(rootView: root)
            tab.sizingOptions = []
            tab.alphaValue = 0
            addSubview(tab)
            raiseTab = tab
        }
        tab.frame = raiseTabFrame(layout)
    }

    /// The pointer moved: on the window's very edge beside the notch the tab comes after
    /// `raiseDwell`; once up, it stays while the pointer is on its way to it.
    private func followPointerForRaiseTab(_ point: CGPoint) {
        guard let layout, let raiseTab else { return }
        if raiseTab.alphaValue > 0.5 {
            if !raiseZone(layout).contains(point) { showRaiseTab(false) }
            return
        }
        guard layout.isOnRaiseEdge(point, notch: notch) else {
            raiseDwell?.invalidate()
            raiseDwell = nil
            return
        }
        guard raiseDwell == nil else { return }
        let timer = Timer(timeInterval: Self.raiseDwell, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                self.raiseDwell = nil
                let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if self.layout?.isOnRaiseEdge(point, notch: self.notch) == true { self.showRaiseTab(true) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        raiseDwell = timer
    }

    private func showRaiseTab(_ shown: Bool) {
        guard let raiseTab, shown != (raiseTab.alphaValue > 0.5) else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            raiseTab.animator().alphaValue = shown ? 1 : 0
        }
    }

    private func onRaiseTab(_ event: NSEvent) -> Bool {
        guard let raiseTab, raiseTab.alphaValue > 0 else { return false }
        return raiseTab.frame.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil))
    }

    private func beginTabDrag(_ event: NSEvent) {
        guard let layout else { return }
        let raise = layout.offset
        tabDrag = (startY: event.locationInWindow.y, startRaise: raise, raise: raise)
    }

    /// The picture follows the pointer, only one way: up from where it was not raised, down from raised.
    private func moveTabDrag(_ event: NSEvent) {
        guard let layout, let drag = tabDrag else { return }
        let moved = event.locationInWindow.y - drag.startY
        let raise = drag.startRaise > 0 ? min(drag.startRaise, drag.startRaise + moved) : max(0, moved)
        tabDrag?.raise = raise
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.frame = layout.copy(raisedBy: raise)
        CATransaction.commit()
    }

    /// Past a quarter of the way it goes all the way (a short tug is enough); else back.
    private func endTabDrag() {
        guard let layout, let drag = tabDrag else { return }
        tabDrag = nil
        let moved = abs(drag.raise - drag.startRaise)
        let raised = moved > AnchorStageLayout.barHeight / 4 ? drag.startRaise == 0 : drag.startRaise > 0
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        surface.frame = layout.copy(raisedBy: raised ? AnchorStageLayout.barHeight : 0)
        CATransaction.commit()
        if raised != (drag.startRaise > 0) { onRaised?(raised) }
    }

    /// A SwiftUI part of the stage, made once, its content replaced after.
    private func host<Content: View>(_ existing: NSHostingView<Content>?, _ root: Content) -> NSHostingView<Content> {
        if let existing {
            existing.rootView = root
            return existing
        }
        let view = NSHostingView(rootView: root)
        view.sizingOptions = []
        addSubview(view)
        return view
    }

    // MARK: Growing out of the notch

    /// From the notch's rectangle (in the stage) to the whole stage, as the island opens.
    func grow(from notch: CGRect) {
        animate(from: transform(to: notch), to: CATransform3DIdentity, opacity: (0, 1), completion: nil)
    }

    func shrink(into notch: CGRect, completion: @escaping () -> Void) {
        animate(from: CATransform3DIdentity, to: transform(to: notch), opacity: (1, 0), completion: completion)
    }

    private func transform(to notch: CGRect) -> CATransform3D {
        let bounds = container.bounds
        guard bounds.width > 0, bounds.height > 0 else { return CATransform3DIdentity }
        let scale = CATransform3DMakeScale(notch.width / bounds.width, max(notch.height, 1) / bounds.height, 1)
        return CATransform3DConcat(scale, CATransform3DMakeTranslation(notch.midX - bounds.midX, notch.midY - bounds.midY, 0))
    }

    private func animate(from: CATransform3D, to: CATransform3D, opacity: (Float, Float), completion: (() -> Void)?) {
        let growing = completion == nil
        let move = CASpringAnimation(perceptualDuration: 0.45, bounce: growing ? 0.14 : 0)
        move.keyPath = "transform"
        move.fromValue = from
        move.toValue = to
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity.0
        fade.toValue = opacity.1
        fade.duration = growing ? 0.16 : 0.3
        fade.fillMode = .both
        if let frozen = LeanSpring.frozenTime {
            for animation in [move, fade] as [CAAnimation] {
                animation.speed = 0
                animation.timeOffset = frozen
            }
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        container.transform = to
        container.opacity = opacity.1
        container.add(move, forKey: "grow")
        container.add(fade, forKey: "fade")
        for view in [leadingEar, trailingEar] as [NSView?] { view?.alphaValue = CGFloat(opacity.1) }
        CATransaction.commit()
    }

    // MARK: Handing events to the real window

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if onRaiseTab(event) { beginTabDrag(event) } else { press(event) }
    }
    override func rightMouseDown(with event: NSEvent) { press(event) }
    override func otherMouseDown(with event: NSEvent) { press(event) }
    override func mouseDragged(with event: NSEvent) {
        if tabDrag != nil { moveTabDrag(event) } else if isForwarding { forward(event) }
    }
    override func rightMouseDragged(with event: NSEvent) { if isForwarding { forward(event) } }
    override func otherMouseDragged(with event: NSEvent) { if isForwarding { forward(event) } }
    override func mouseUp(with event: NSEvent) {
        if tabDrag != nil { endTabDrag() } else { release(event) }
    }
    override func rightMouseUp(with event: NSEvent) { release(event) }
    override func otherMouseUp(with event: NSEvent) { release(event) }
    override func mouseMoved(with event: NSEvent) {
        followPointerForRaiseTab(convert(event.locationInWindow, from: nil))
        if onRaiseTab(event) {
            (layout?.offset ?? 0 > 0 ? NSCursor.frameResize(position: .top, directions: .inward) : NSCursor.frameResize(position: .top, directions: .outward)).set()
        } else if onPicture(event) {
            forward(event)
        }
    }

    override func mouseExited(with event: NSEvent) {
        raiseDwell?.invalidate()
        raiseDwell = nil
        if tabDrag == nil { showRaiseTab(false) }
    }
    override func scrollWheel(with event: NSEvent) { if onPicture(event) { forward(event) } }
    override func magnify(with event: NSEvent) { if onPicture(event) { forward(event) } }

    private func onPicture(_ event: NSEvent) -> Bool {
        guard let layout else { return false }
        return layout.copy.contains(convert(event.locationInWindow, from: nil))
    }

    private func press(_ event: NSEvent) {
        guard onPicture(event), let target else { return }
        isForwarding = true
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != target.pid else { return forward(event) }
        // The real window on another space (a full-screen app in front): bringing its app forward
        // would switch to that space. The click goes to it where it is, and the user stays here.
        guard Self.isOnActiveSpace(target.windowID) else { return forward(event) }
        // Its app in front first: an inactive window takes a click only as a way to come forward,
        // and the keyboard then types into it. The press and what follows wait (a few frames).
        queued = []
        forward(event)
        let pid = target.pid
        Task { [weak self] in
            await AXWorker.shared.makeFrontmost(pid: pid)
            for _ in 0..<12 where NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                try? await Task.sleep(for: .milliseconds(16))
            }
            self?.flush()
        }
    }

    /// The window is on the space in front (one look at the window list, per press).
    private static func isOnActiveSpace(_ window: CGWindowID) -> Bool {
        let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], window) as? [[String: Any]])?.first
        return info?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    private func release(_ event: NSEvent) {
        guard isForwarding else { return }
        forward(event)
        isForwarding = false
    }

    /// The event as it came, sent to the real window's app at the point where the window has it.
    private func forward(_ event: NSEvent) {
        guard let layout, let target, let copy = event.cgEvent?.copy() else { return }
        let point = copy.location
        copy.location = layout.forwarded(point)
        EventAddress.address(copy, to: target.windowID, at: layout.inWindow(point))
        if queued != nil { queued?.append(copy) } else { copy.postToPid(target.pid) }
    }

    private func flush() {
        guard let events = queued else { return }
        queued = nil
        guard let target else { return }
        for event in events { event.postToPid(target.pid) }
    }
}

/// What the window server writes into a mouse event it routes to a window, written by hand for one
/// sent straight to the app (`postToPid`): without its window and its point in that window an app
/// takes the event for none of its windows (hovering works, a click does not).
nonisolated enum EventAddress {
    private typealias SetWindowLocation = @convention(c) (CGEvent, CGPoint) -> Void

    /// `CGEventSetWindowLocation`, not in the headers: looked up once, absent on a system without it.
    private static let setWindowLocation: SetWindowLocation? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventSetWindowLocation") else { return nil }
        return unsafeBitCast(symbol, to: SetWindowLocation.self)
    }()

    /// The event's window number field (not among `CGEventField`'s names).
    private static let windowNumber = CGEventField(rawValue: 51)!

    static func address(_ event: CGEvent, to window: CGWindowID, at point: CGPoint) {
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        event.setIntegerValueField(windowNumber, value: Int64(window))
        setWindowLocation?(event, point)
    }
}

/// Beside the notch, in the menu bar: the app's icon and name on its left, Release on its right,
/// each on black that widens the notch (its outer bottom corner rounded).
struct StageEar: View {
    enum Side { case leading, trailing }

    /// How far each reaches under the notch.
    static let underNotch: CGFloat = 10
    /// Between the notch (or the island's ears) and the content, and at the outer end.
    static let innerPadding: CGFloat = 10
    static let outerPadding: CGFloat = 12
    static let nameFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let releaseFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let iconSide: CGFloat = 15
    static let spacing: CGFloat = 6

    let side: Side
    let appName: String
    let icon: NSImage?
    /// Kept clear next to the notch: the island's ears, when they are out.
    var inset: CGFloat = 0
    let release: () -> Void

    /// The whole ear's width, `underNotch` included: what its content needs, measured as drawn.
    static func width(side: Side, appName: String, hasIcon: Bool, inset: CGFloat) -> CGFloat {
        let content: CGFloat
        switch side {
        case .leading:
            let name = (appName as NSString).size(withAttributes: [.font: nameFont]).width
            content = (hasIcon ? iconSide + spacing : 0) + name
        case .trailing:
            let title = (String(localized: "Release") as NSString).size(withAttributes: [.font: releaseFont]).width
            content = 14 + 5 + title
        }
        return (underNotch + inset + innerPadding + content + outerPadding).rounded(.up)
    }

    var body: some View {
        Group {
            switch side {
            case .leading:
                HStack(spacing: Self.spacing) {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: Self.iconSide, height: Self.iconSide)
                    }
                    Text(appName)
                        .font(Font(Self.nameFont))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .fixedSize()
                }
            case .trailing:
                Button(action: release) {
                    HStack(spacing: 5) {
                        Image(systemName: "rectangle.topthird.inset.filled")
                            .frame(width: 14)
                        Text("Release").fixedSize()
                    }
                    .font(Font(Self.releaseFont))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.75))
                .help("Let the window go")
            }
        }
        .padding(.leading, side == .leading ? Self.outerPadding : Self.underNotch + inset + Self.innerPadding)
        .padding(.trailing, side == .leading ? Self.underNotch + inset + Self.innerPadding : Self.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: side == .leading ? .trailing : .leading)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: side == .leading ? 10 : 0, bottomTrailingRadius: side == .trailing ? 10 : 0,
                                   style: .continuous)
                .fill(.black)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// A hosting view the stage's own events pass through: the stage takes the drag of the tab.
final class UnclickableHosting<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The tab at the anchored window's top: it says the one way it goes.
struct StageRaiseTab: View {
    static let size = CGSize(width: 132, height: 20)

    let isRaised: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isRaised ? "arrow.down" : "arrow.up")
            Text(isRaised ? "Move window down" : "Move window up").fixedSize()
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: Self.size.width, height: Self.size.height)
        // See-through, readable on a light title bar and a dark one alike.
        .background(.black.opacity(0.45), in: .capsule)
        .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
        .environment(\.colorScheme, .dark)
    }
}
