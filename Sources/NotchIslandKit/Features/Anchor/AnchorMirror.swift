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
/// when the window changes, at most 30 a second while its app is in front, 15 behind, 8 in Low Power
/// Mode or under 30 % of battery. macOS shows its screen-sharing indicator meanwhile.
@Observable final class AnchorMirror {
    /// Screen Recording is given to the app.
    private(set) var isAllowed = CGPreflightScreenCaptureAccess()
    /// The stage is on screen.
    private(set) var isShowing = false

    static let activeFrameRate = 30
    static let frameRate = 15
    static let reducedFrameRate = 8

    /// "Release" on the stage's bar.
    @ObservationIgnored var onRelease: (() -> Void)?

    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var isPaused = false
    @ObservationIgnored private var isReduced = false
    @ObservationIgnored private var bar: AnchorBarPlacement = .belowWindow
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

    func setPaused(_ paused: Bool) {
        isPaused = paused
        reconcile()
    }

    /// Where the stage shows the app's name and Release (redrawn at once while it is up).
    func setBar(_ placement: AnchorBarPlacement) {
        guard placement != bar else { return }
        bar = placement
        if isShowing { reconcile() }
    }

    /// The island's compact ears came or went: the name and Release beside the notch make room.
    func setIslandReach(_ reach: CGFloat) {
        guard reach != islandReach else { return }
        islandReach = reach
        if isShowing, bar == .menuBar { reconcile() }
    }

    /// Low Power Mode or a low battery: fewer frames.
    func setReduced(_ reduced: Bool) {
        guard reduced != isReduced else { return }
        isReduced = reduced
        updateRate()
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
            // Its other windows in front of it (a sheet, a dialog): the list is front to back.
            let front = AXWorker.serverWindows().prefix { $0.id != own }
            let overlaid = front.contains { $0.pid == pid && layout.isOverlaid(by: $0.frame) }
            await MainActor.run { [weak self] in
                guard let self, self.overlayGeneration == generation, overlaid != self.isOverlaid else { return }
                self.isOverlaid = overlaid
                self.reconcile()
            }
        }
    }

    private func layout(_ held: WindowAnchor.Held) -> AnchorStageLayout? {
        screen.map { AnchorStageLayout(screen: $0, rest: held.rest, placement: bar) }
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

    private var rate: Int {
        if isReduced || ProcessInfo.processInfo.isLowPowerModeEnabled { return Self.reducedFrameRate }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return front == held?.window.pid ? Self.activeFrameRate : Self.frameRate
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
        let output = MirrorOutput(layer: panel.stage.surface)
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
        // The frame rate follows whether the app is in front.
        if activation == nil {
            activation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateRate()
                    self?.appWindowsChanged()
                }
            }
        }
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
        panel.stage.configure(layout: layout, target: StageTarget(pid: held.window.pid, windowID: held.window.windowID ?? 0),
                              appName: app?.localizedName ?? "", icon: app?.icon, notch: notchRect(screen, in: layout), placement: bar,
                              islandReach: islandReach)
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
nonisolated final class MirrorOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    static let queue = DispatchQueue(label: "notchisland.anchor.mirror", qos: .userInitiated)

    private let layer: CALayer
    /// Both only touched on `queue`.
    private var hasFrame = false
    private var waiting: [@MainActor @Sendable () -> Void] = []

    init(layer: CALayer) {
        self.layer = layer
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
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(buffer), let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = surface
        CATransaction.commit()
        guard !hasFrame else { return }
        hasFrame = true
        let waiting = waiting
        self.waiting = []
        Task { @MainActor in waiting.forEach { $0() } }
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
        collectionBehavior = [.transient, .ignoresCycle]
        contentView = stage
        setAccessibilityLabel(String(localized: "Anchored window, live copy"))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The stage: the island-black backdrop with the shoulders, the window's picture flush with the
/// screen's top, and the bar under it. Events on the picture go to the real window.
final class StageView: NSView {
    /// Where the frames go.
    let surface = CALayer()
    private let container = CALayer()
    private let backdrop = CAShapeLayer()
    private var bar: NSHostingView<StageBar>?
    private var leadingEar: NSHostingView<StageEar>?
    private var trailingEar: NSHostingView<StageEar>?
    private var layout: AnchorStageLayout?
    private var target: StageTarget?
    private var tracking: NSTrackingArea?
    /// A press on the picture: its drag and release go to the real window too, wherever the pointer goes.
    private var isForwarding = false
    /// While its app comes to the front: the events to send once it is there (nil: none held).
    private var queued: [CGEvent]?
    var onRelease: (() -> Void)?

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
                   placement: AnchorBarPlacement, islandReach: CGFloat = 0) {
        self.target = target
        if layout != self.layout {
            self.layout = layout
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let bounds = CGRect(origin: .zero, size: layout.frame.size)
            container.frame = bounds
            backdrop.frame = bounds
            backdrop.path = IslandShapeGeometry(rect: bounds, bottomRadius: layout.bottomRadius, shoulderRadius: layout.shoulder,
                                                topInset: 0).path().cgPath
            surface.frame = layout.copy
            CATransaction.commit()
        }
        let release: () -> Void = { [weak self] in self?.onRelease?() }
        // Under the window: a bar in the chin. Beside the notch: the name to its left, Release to its right.
        let bar = host(self.bar, StageBar(appName: appName, icon: icon, release: release))
        self.bar = bar
        bar.frame = layout.chin
        bar.isHidden = placement != .belowWindow || layout.chin.height == 0
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
        leading.isHidden = placement != .menuBar
        trailing.isHidden = placement != .menuBar
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
        for view in [bar, leadingEar, trailingEar] as [NSView?] { view?.alphaValue = CGFloat(opacity.1) }
        CATransaction.commit()
    }

    // MARK: Handing events to the real window

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { press(event) }
    override func rightMouseDown(with event: NSEvent) { press(event) }
    override func otherMouseDown(with event: NSEvent) { press(event) }
    override func mouseDragged(with event: NSEvent) { if isForwarding { forward(event) } }
    override func rightMouseDragged(with event: NSEvent) { if isForwarding { forward(event) } }
    override func otherMouseDragged(with event: NSEvent) { if isForwarding { forward(event) } }
    override func mouseUp(with event: NSEvent) { release(event) }
    override func rightMouseUp(with event: NSEvent) { release(event) }
    override func otherMouseUp(with event: NSEvent) { release(event) }
    override func mouseMoved(with event: NSEvent) { if onPicture(event) { forward(event) } }
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

/// Under the picture: the app's icon and name, and Release.
struct StageBar: View {
    let appName: String
    let icon: NSImage?
    let release: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(appName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: release) {
                Label("Release", systemImage: "rectangle.topthird.inset.filled")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
            .help("Let the window go")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }
}
