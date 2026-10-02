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
            alphaValue = 0
            ignoresMouseEvents = true
            DeferredLayouts.resume(in: self)
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
        root.layer?.mask = clip
        root.onLayout = { [weak self] in self?.placeClip() }
        placeClip()
    }

    /// Over the island's page area: only a new size lays anything out.
    func place(_ frame: CGRect) {
        guard frame != self.frame else { return }
        setFrame(frame, display: false)
    }

    /// Settings has grown: the pages fade in over the island and take the keyboard from it.
    func show() {
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
        DeferredLayouts.resume(in: self)
        surface.show()
        orderFrontRegardless()
        if model.island.presentation.isSettings { makeKey() }
    }

    /// Settings closes: out of sight after `fade` (at once without), then ordered out.
    func hide(fade: TimeInterval?) {
        surface.hide(fade: fade)
        orderingOut?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.orderingOut = nil
            self.orderOut(nil)
        }
        orderingOut = work
        if let fade {
            DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.02, execute: work)
        } else {
            work.perform()
        }
    }

    /// The island's outline moves (`IslandOutlineMotion`): the pages are cut by it too.
    func followOutline(_ animation: CAKeyframeAnimation, final: CGPath?) {
        guard isVisible else { return }
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
