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
        if isPrestaged {
            isPrestaged = false
            alphaValue = 1
            ignoresMouseEvents = false
        }
        if isRehearsing {
            isRehearsing = false
            alphaValue = 1
            ignoresMouseEvents = false
        }
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
        super.sendEvent(event)
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
