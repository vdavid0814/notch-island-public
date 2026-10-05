import AppKit
import QuartzCore

/// Settings' pages in a window of their own, over the island, built once and kept for as long as
/// the app runs.
///
/// Built at every opening, Settings' pages were most of what it cost (~1.2 s of main thread per
/// opening and change of page, Energy Impact ~400, measured). Kept inside the island's window they
/// cost the island instead: every resize of that window (each open, close and Siri step) and every
/// change of its key state made AppKit and SwiftUI go over the hidden pages and their native
/// controls (Siri's opening ~5× the main-thread time, measured). Moved in and out of the island's
/// window, every page was laid out again on its return (~1 s). In a window of their own that is
/// only ordered in and out, they are untouched while Settings is closed, and an opening only shows
/// them.
///
/// The window lies exactly over the island's page area (`SettingsSurfaceAnchor`) and is clipped to
/// the island's outline — the same one the island's window is (`IslandOutlineMotion`), also while
/// it closes — so on screen it is the island's content as before.
final class SettingsWindow: NSPanel {
    private(set) static var current: SettingsWindow?
    static var isPrepared: Bool { current != nil }

    let surface: SettingsSurfaceView
    private let model: AppModel
    private let root = SettingsWindowRoot()
    private let clip = CALayer()
    private let outline = CAShapeLayer()
    /// Ordering out after the fade.
    private var orderingOut: DispatchWorkItem?

    /// The kept window with its surface (as it was left), or a new one, over `frame`.
    static func reused(model: AppModel, placement: SettingsPlacement, frame: CGRect) -> SettingsWindow {
        if let current, current.model === model {
            current.place(frame)
            current.surface.reattach(placement: placement)
            return current
        }
        let window = SettingsWindow(model: model, placement: placement, frame: frame)
        current = window
        return window
    }

    /// Builds Settings unseen ahead of its first opening (after launch, while the island is
    /// closed), at the size and place it will be shown at: the sidebar first, then one page per
    /// call of `prepareNextPage`, so no single turn holds the main thread long.
    static func prepare(model: AppModel, frame: CGRect) {
        guard current == nil, frame.width > 0, frame.height > 0 else { return }
        let window = SettingsWindow(model: model, placement: IslandSettingsView.placement(model.layout), frame: frame)
        current = window
        window.root.layoutSubtreeIfNeeded()
        window.surface.sidebarHost.forcesLayout = true
        window.surface.sidebarHost.layoutSubtreeIfNeeded()
        window.surface.sidebarHost.forcesLayout = false
    }

    /// The next step of `prepare`: builds and lays out the next page Settings has not built yet,
    /// then draws each page once, unseen; false when all is done (or Settings is open).
    static func prepareNextPage(model: AppModel) -> Bool {
        guard let current, !current.isVisible || current.isRehearsing else { return false }
        let order = [model.settingsPane] + IslandSettingsPane.allCases.filter { $0 != model.settingsPane }
        if let pane = order.first(where: { !current.surface.deck.isBuilt($0) }) {
            current.surface.deck.prepare(pane)
            return true
        }
        return current.rehearse(order)
    }

    /// Pages drawn once in the window ordered in at no opacity (`rehearse`).
    private var rehearsed: Set<IslandSettingsPane> = []
    private(set) var isRehearsing = false

    /// One page drawn in the window ordered in, invisible and letting every click through: what a
    /// page does the first time it is on screen (drawing its layers, its controls taking the
    /// window's state) is done ahead too. Ordered out again after the last one.
    private func rehearse(_ order: [IslandSettingsPane]) -> Bool {
        guard let pane = order.first(where: { !rehearsed.contains($0) }) else {
            if isRehearsing { endRehearsal() }
            return false
        }
        if !isRehearsing {
            isRehearsing = true
            SettingsPresence.shared.isShown = true
            alphaValue = 0
            ignoresMouseEvents = true
            orderFrontRegardless()
        }
        rehearsed.insert(pane)
        surface.deck.show(pane)
        root.layoutSubtreeIfNeeded()
        displayIfNeeded()
        return true
    }

    private func endRehearsal() {
        isRehearsing = false
        SettingsPresence.shared.isShown = false
        orderOut(nil)
        alphaValue = 1
        ignoresMouseEvents = false
        surface.deck.show(model.settingsPane)
        surface.deck.closed()
    }

    private init(model: AppModel, placement: SettingsPlacement, frame: CGRect) {
        self.model = model
        surface = SettingsSurfaceView(model: model, placement: placement)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Over the island (its own level), under open menus and Control Center.
        level = NSWindow.Level(rawValue: IslandPanel.restingLevel.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
        isMovableByWindowBackground = false
        isRestorable = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        tabbingMode = .disallowed
        depthLimit = .twentyfourBitRGB

        root.frame = CGRect(origin: .zero, size: frame.size)
        root.autoresizingMask = [.width, .height]
        contentView = root
        surface.frame = root.bounds
        surface.autoresizingMask = [.width, .height]
        root.addSubview(surface)

        clip.isGeometryFlipped = true
        outline.fillColor = CGColor(gray: 0, alpha: 1)
        clip.addSublayer(outline)
        root.onLayout = { [weak self] in self?.placeClip() }
        placeClip()
        clipsToOutline(false)
    }

    /// At rest the window is cut by its own rounded lower corners (the island's, continuous like
    /// SwiftUI's): the window server draws those as cheaply as any corner. A mask layer in the
    /// island's outline (needed only while the outline moves, as Settings closes) had it render
    /// the whole window offscreen at every frame of anything moving in it (General's looping
    /// picture: ~10 mW more in the window server, measured).
    private func clipsToOutline(_ moving: Bool) {
        guard let layer = root.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if moving {
            layer.cornerRadius = 0
            layer.masksToBounds = false
            layer.mask = clip
        } else {
            layer.mask = nil
            layer.cornerRadius = model.layout.bottomRadius(for: .settings)
            layer.cornerCurve = .continuous
            // The lower corners, whichever way the view's layer runs.
            layer.maskedCorners = layer.isGeometryFlipped || layer.contentsAreFlipped()
                ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            layer.masksToBounds = true
        }
        CATransaction.commit()
    }

    /// Over the island's page area: only a new size lays anything out.
    func place(_ frame: CGRect) {
        guard frame != self.frame else { return }
        setFrame(frame, display: false)
    }

    /// Ordered in, invisible and letting every click through, as Settings starts to grow: what the
    /// window does as it comes on screen again (laying out what changed while it was away, its
    /// controls taking the window's state; one ~250 ms turn, measured) happens while the island
    /// grows on the render server, not in the frame the pages should start to fade in.
    private(set) var isPrestaged = false

    func prestage() {
        guard !isVisible, !isRehearsing else { return }
        orderingOut?.cancel()
        orderingOut = nil
        isPrestaged = true
        alphaValue = 0
        ignoresMouseEvents = true
        // Its pictures pick up the live readings now too (clocks, monitors, levels), not in the
        // frame the pages fade in.
        SettingsPresence.shared.isShown = true
        orderFrontRegardless()
    }

    /// Settings closed before it had grown: the prestaged window goes again.
    func endPrestage() {
        guard isPrestaged else { return }
        isPrestaged = false
        SettingsPresence.shared.isShown = false
        orderOut(nil)
        alphaValue = 1
        ignoresMouseEvents = false
    }

    /// Settings has grown: the pages fade in over the island.
    func show() {
        SettingsPresence.shared.isShown = true
        if alphaValue != 1 || ignoresMouseEvents, !isPrestaged, !isRehearsing {
            Log.window.error("settings window shown from alpha \(self.alphaValue, privacy: .public), ignoring clicks \(self.ignoresMouseEvents, privacy: .public), neither prestaged nor rehearsing")
        }
        // Whatever left it see-through (prestaged, rehearsing, or anything else): seen now.
        isPrestaged = false
        isRehearsing = false
        alphaValue = 1
        ignoresMouseEvents = false
        orderingOut?.cancel()
        orderingOut = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.removeAnimation(forKey: "outline")
        outline.path = Self.settingsPath(model.layout)
        CATransaction.commit()
        clipsToOutline(false)
        surface.show()
        orderFrontRegardless()
        // Not made key: the island keeps the keyboard (Esc closes Settings from there), and this
        // window takes it with the first click in it (a field, the sidebar). Made key at every
        // opening, every control of the page and the sidebar took the key state, and gave it back
        // at the close: four fifths of what an opening cost (170 → 31 mJ, measured).
    }

    /// Settings has grown and its pages should be in: whether they can be seen. Settings now and
    /// then grew empty until the app was restarted (Oct 2026, not reproduced): what the window and
    /// its pages were then goes to the log, and the window is shown again.
    static func verifyShown(model: AppModel) {
        guard model.island.presentation.isSettings else { return }
        let islands = NSApp.windows.compactMap { $0 as? IslandPanel }.filter(\.isVisible)
            .map { "island level \($0.level.rawValue) \($0.frame)" }.joined(separator: ", ")
        guard let current else {
            Log.window.error("settings grew without its window (never built); \(islands, privacy: .public)")
            return
        }
        let seen = current.isVisible && current.occlusionState.contains(.visible) && current.alphaValue > 0
            && current.surface.alphaValue > 0 && !current.surface.pagesView.isHidden
        let state = "visible \(current.isVisible), on screen \(current.occlusionState.contains(.visible)), "
            + "level \(current.level.rawValue), alpha \(current.alphaValue), ignores clicks \(current.ignoresMouseEvents), "
            + "frame \(current.frame), prestaged \(current.isPrestaged), rehearsing \(current.isRehearsing), "
            + "ordering out \(current.orderingOut != nil), mask \(current.root.layer?.mask != nil); "
            + "\(current.surface.visibilityDescription); \(islands)"
        guard !seen else {
            Log.window.notice("settings shown: \(state, privacy: .public)")
            return
        }
        Log.window.fault("settings grew but its pages cannot be seen: \(state, privacy: .public)")
        current.show()
    }

    /// Settings closes: out of sight after `fade` (at once without), then ordered out.
    func hide(fade: TimeInterval?) {
        surface.hide(fade: fade)
        orderingOut?.cancel()
        // Its pictures stand still once it is out of sight, not in the frame the island starts
        // to shrink in.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.orderingOut = nil
            SettingsPresence.shared.isShown = false
            self.orderOut(nil)
        }
        orderingOut = work
        if let fade {
            DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.02, execute: work)
        } else {
            work.perform()
        }
    }

    /// Out of the window list with the island while the session is locked or the screens sleep;
    /// back with it if Settings is still open.
    private var wasShownBeforeSuspension = false

    func setSuspended(_ suspended: Bool) {
        if suspended {
            wasShownBeforeSuspension = isVisible && !isRehearsing
            if isVisible { orderOut(nil) }
        } else if wasShownBeforeSuspension {
            wasShownBeforeSuspension = false
            if model.island.presentation.isSettings { orderFrontRegardless() }
        }
    }

    /// The island's outline moves (`IslandOutlineMotion`): the pages are cut by it too.
    func followOutline(_ animation: CAKeyframeAnimation, final: CGPath?) {
        guard isVisible else { return }
        clipsToOutline(true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.path = final
        outline.add(animation, forKey: "outline")
        CATransaction.commit()
    }

    /// The outline's top centre where the island's is: the window starts under the band at the
    /// notch's height, centred on the island.
    private func placeClip() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clip.frame = root.bounds
        outline.position = CGPoint(x: root.bounds.midX, y: -model.layout.notch.height)
        CATransaction.commit()
    }

    private static func settingsPath(_ layout: IslandLayout) -> CGPath {
        IslandOutlineMotion.path(layout.outline(for: .settings))
    }

    // MARK: Keyboard

    /// The first click in the window makes it key and is handled as any other: as a window that
    /// was not key, it went only to making the window key, and the sidebar or a field missed it.
    override func sendEvent(_ event: NSEvent) {
        if !isKeyWindow, canBecomeKey, [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            makeKey()
        }
        // A wheel or trackpad scroll goes straight to the scroll view under the pointer. Routed by
        // AppKit, every event of a scroll (120 a second on a trackpad) hit-tested the whole page
        // through SwiftUI first (~a third of a scroll's main-thread time, measured).
        if event.type == .scrollWheel {
            ScrollActivity.mark()
            if let target = scrollTarget(for: event) {
                if coalescer.scroll(target, with: event) { return }
                target.scrollWheel(with: event)
                return
            }
        }
        // A click (or a key) lands where the page is drawn: the scroll is handed over first.
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown].contains(event.type) { coalescer.commit() }
        super.sendEvent(event)
    }

    private let coalescer = ScrollCoalescer()

    /// The innermost scroll view under the event that can scroll its way; nil leaves it to AppKit.
    private func scrollTarget(for event: NSEvent) -> NSScrollView? {
        guard let root = contentView else { return nil }
        let point = event.locationInWindow
        let vertical = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
        var found: NSScrollView?
        func visit(_ view: NSView) {
            guard !view.isHidden, view.alphaValue > 0 else { return }
            if let scroll = view as? NSScrollView, scroll.convert(scroll.bounds, to: nil).contains(point),
               let document = scroll.documentView {
                let room = vertical ? document.frame.height - scroll.contentView.bounds.height
                                    : document.frame.width - scroll.contentView.bounds.width
                if room > 1 { found = scroll }
            }
            for subview in view.subviews { visit(subview) }
        }
        visit(root)
        return found
    }

    override var canBecomeKey: Bool { isVisible && !isRehearsing }
    override var canBecomeMain: Bool { false }

    /// As the island's panel: app-level shortcuts would act on NotchIsland itself.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if IslandPanel.isSwallowedShortcut(event) {
            _ = super.performKeyEquivalent(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Drawn active whatever has the keyboard, as the island's panel (`IslandPanel`).
    @objc(_hasActiveAppearanceIgnoringKeyFocus) private func settingsHasActiveAppearanceIgnoringKeyFocus() -> Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The settings window's content: top-left origin, layer-backed (its layer carries the clip).
private final class SettingsWindowRoot: NSView {
    var onLayout: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// When Settings was last scrolled: while it scrolls, hit tests that AppKit makes only to update the
/// cursor (not for a click) stop at the page's hosting view (`DeferringHostingView`).
@MainActor enum ScrollActivity {
    private static var last: CFTimeInterval = 0
    static func mark() { last = CACurrentMediaTime() }
    static var isActive: Bool { CACurrentMediaTime() - last < 0.2 }
}

/// A trackpad scroll of a Settings page, moved on the render server and handed to the scroll view
/// once it stops.
///
/// Moved by AppKit at every event (120 a second), the page's scroll view had SwiftUI update the
/// whole page each time — every hosting view in it (each gallery preview is one) told its place in
/// the window changed, hover hit-tested again through every card, the keyboard loop rebuilt —
/// ~40 % of a core while scrolling the Widgets page (Activity Monitor ~1300–1500, measured). Here
/// each event only shifts the clip view's layer (`sublayerTransform`), which the window server
/// draws, and moves the scroller's knob; the scroll view itself is scrolled to where the page is
/// when the scroll (with its momentum) stops — one SwiftUI update per scroll, ~7 % of a core.
///
/// Every page in a scroll view here is built whole (no lazy stacks or grids: `GalleryGrid`,
/// `SwatchGrid`), so the parts a shift brings into view are already drawn. The ends stretch and
/// spring back as AppKit's rubber band does (its curves measured on this page), on the layer too:
/// handed to AppKit, a scroll held at an end updated the page at every frame again. A click, a key
/// or another scroll view takes the scroll over first. Wheel (line) scrolling is left to AppKit's
/// own smooth scroll, and scroll views that are not SwiftUI's (a `List`'s table builds only its
/// visible rows).
@MainActor final class ScrollCoalescer {
    /// After the last event of a scroll, the scroll view is scrolled to where the page is.
    static let settle: TimeInterval = 0.12
    /// AppKit's stretch past an end: `h·(1 − 1/(stretch·x/h + 1))` for `x` points pulled, `h` the
    /// visible height (fitted within half a point to 140–2240 pt pulled).
    static let stretch: CGFloat = 0.146
    /// AppKit's spring back to an end: exponential with this time constant, after the fingers lift;
    /// momentum that runs into an end bounces out and back at the same pace.
    static let springBack: CFTimeInterval = 0.1
    private static let springKey = "settingsScrollSpring"

    private weak var scroll: NSScrollView?
    /// How far the page is drawn past where the scroll view is.
    private var pending: CGFloat = 0
    /// How far past an end the fingers have pulled (points of scroll; past the bottom positive).
    private var excess: CGFloat = 0
    /// This gesture's momentum ended in a bounce: the rest of it is dropped.
    private var momentumSpent = false
    private var lastEvent: TimeInterval = 0
    private var ending: DispatchWorkItem?
    private var lastFlash: CFTimeInterval = 0

    /// Takes a precise (trackpad) vertical scroll; false leaves it to AppKit.
    func scroll(_ target: NSScrollView, with event: NSEvent) -> Bool {
        let momentum = !event.momentumPhase.isEmpty
        if event.phase == .began || event.phase == .mayBegin { momentumSpent = false }
        guard event.hasPreciseScrollingDeltas, abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
              NSStringFromClass(type(of: target)).contains("HostingScrollView"),
              let document = target.documentView, let layer = target.contentView.layer else {
            commit()
            return false
        }
        if scroll !== target {
            commit()
            scroll = target
        }
        let interval = min(max(event.timestamp - lastEvent, 1.0 / 240), 1.0 / 30)
        lastEvent = event.timestamp
        if momentum && momentumSpent { return true }
        if !momentum, layer.animation(forKey: Self.springKey) != nil {
            layer.removeAnimation(forKey: Self.springKey)
        }
        let clip = target.contentView
        let height = clip.bounds.height
        let origin = clip.bounds.origin.y
        let limit = max(0, document.frame.height - height)
        // Down the page is a growing origin in the flipped document.
        let direction: CGFloat = document.isFlipped ? -1 : 1
        let delta = direction * event.scrollingDeltaY
        var position = origin + pending
        if excess != 0 {
            let pulled = excess + delta
            if pulled != 0, (pulled > 0) == (excess > 0) {
                excess = pulled
            } else {
                excess = 0
                position += pulled
            }
        } else {
            position += delta
        }
        var crossed: CGFloat = 0
        if position < 0 {
            crossed = -1
            if !momentum { excess += position }
            position = 0
        } else if position > limit {
            crossed = 1
            if !momentum { excess += position - limit }
            position = limit
        }
        pending = position - origin
        draw(layer, Self.layerShift(pending + Self.stretched(excess, height), layer: layer))
        if let scroller = target.verticalScroller, limit > 0 {
            scroller.doubleValue = Double((document.isFlipped ? position : limit - position) / limit)
            let now = CACurrentMediaTime()
            if now - lastFlash > 0.3 {
                lastFlash = now
                target.flashScrollers()
            }
        }
        var wait = Self.settle
        if momentum, crossed != 0 {
            // Out by the momentum's speed, as stretched, and back.
            let speed = abs(delta) / CGFloat(interval) * Self.stretch
            wait = spring(layer, from: { t in crossed * speed * CGFloat(t) * CGFloat(exp(-t / Self.springBack)) })
            momentumSpent = true
        } else if excess != 0, event.phase == .ended || event.phase == .cancelled {
            let start = Self.stretched(excess, height)
            excess = 0
            wait = spring(layer, from: { t in start * CGFloat(exp(-t / Self.springBack)) })
            momentumSpent = true
        }
        ending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commit() }
        ending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
        return true
    }

    /// AppKit's stretch for `excess` points pulled past an end.
    static func stretched(_ excess: CGFloat, _ height: CGFloat) -> CGFloat {
        guard excess != 0, height > 0 else { return 0 }
        let pulled = abs(excess)
        return (excess > 0 ? 1 : -1) * height * (1 - 1 / (stretch * pulled / height + 1))
    }

    /// The page's layer moved by `pending` points of scroll: up the screen as the page scrolls down.
    private static func layerShift(_ pending: CGFloat, layer: CALayer) -> CGFloat {
        layer.isGeometryFlipped || layer.contentsAreFlipped() ? -pending : pending
    }

    private func draw(_ layer: CALayer, _ shift: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = CATransform3DMakeTranslation(0, shift, 0)
        CATransaction.commit()
    }

    /// The page drawn at its end plus `offset(t)` points past it, from `offset(0)` back to the end;
    /// returns how long that takes.
    private func spring(_ layer: CALayer, from offset: (Double) -> CGFloat) -> TimeInterval {
        let duration = 8 * Self.springBack
        let steps = 48
        let animation = CAKeyframeAnimation(keyPath: "sublayerTransform.translation.y")
        animation.values = (0...steps).map { step in
            let t = duration * Double(step) / Double(steps)
            return Self.layerShift(pending + (step == steps ? 0 : offset(t)), layer: layer)
        }
        animation.duration = duration
        animation.calculationMode = .linear
        draw(layer, Self.layerShift(pending, layer: layer))
        layer.add(animation, forKey: Self.springKey)
        return duration
    }

    /// The scroll view scrolled to where the page is drawn, and the shift taken off, in one frame.
    func commit() {
        ending?.cancel()
        ending = nil
        guard let scroll else { return }
        let layer = scroll.contentView.layer
        layer?.removeAnimation(forKey: Self.springKey)
        let stretch = Self.stretched(excess, scroll.contentView.bounds.height)
        guard pending != 0 || layer?.sublayerTransform.m42 != 0 else { return }
        let clip = scroll.contentView
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if pending != 0 {
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: clip.bounds.origin.y + pending))
            scroll.reflectScrolledClipView(clip)
        }
        if let layer {
            // Held past an end, it stays stretched.
            layer.sublayerTransform = CATransform3DMakeTranslation(0, Self.layerShift(stretch, layer: layer), 0)
        }
        CATransaction.commit()
        pending = 0
    }
}
