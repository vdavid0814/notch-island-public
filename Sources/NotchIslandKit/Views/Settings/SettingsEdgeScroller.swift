import AppKit

/// Widgets' scroller, out of the pages' room: in the gap the room keeps to the island's side, where
/// nothing else is. The room's own scroller ran over the cards at its edge.
///
/// A view over the room and the gap, as tall as the island: its lower outer corner is the island's
/// own, so the knob at the end of its way is cut round that corner and never stands out of the
/// island. Only the strip in the gap takes the pointer; everything else passes through to the page.
///
/// It is shown as the system's overlay scrollers are: while the page scrolls, while the pointer is
/// on its strip and while it is dragged; a moment later it fades.
final class SettingsEdgeScroller: NSView {
    /// The scroll view it stands for now; nil: none (another page).
    var source: () -> NSScrollView? = { nil }
    /// The gap's width: the strip at this view's right the knob runs in.
    var gap: CGFloat = 8 {
        didSet { if gap != oldValue { place() } }
    }
    /// The island's lower corner.
    var islandRadius: CGFloat = 0 {
        didSet { if islandRadius != oldValue { roundCorner() } }
    }

    private let knob = NSView()
    private weak var scroll: NSScrollView?
    private var observers: [any NSObjectProtocol] = []
    private var fading: DispatchWorkItem?
    private var isHovered = false
    /// While dragged: from the knob's top to the pointer.
    private var grip: CGFloat?
    private var strip: NSTrackingArea?

    private static let knobWidth: CGFloat = 5
    private static let shortestKnob: CGFloat = 28
    /// From the strip's ends to the knob's way.
    private static let inset: CGFloat = 3
    private static let rest: CGFloat = 0.42
    private static let lit: CGFloat = 0.68
    private static let linger: TimeInterval = 1.2

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        knob.wantsLayer = true
        knob.layer?.backgroundColor = CGColor(gray: 1, alpha: Self.rest)
        knob.layer?.cornerRadius = Self.knobWidth / 2
        knob.alphaValue = 0
        knob.isHidden = true
        addSubview(knob)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Follows the scroll view `source` names now (another page shown, the page built).
    func refresh() {
        let next = source()
        if next !== scroll {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            scroll = next
            if let next {
                next.contentView.postsBoundsChangedNotifications = true
                next.documentView?.postsFrameChangedNotifications = true
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: next.contentView, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.place()
                            self?.flash()
                        }
                    })
                if let document = next.documentView {
                    observers.append(NotificationCenter.default.addObserver(
                        forName: NSView.frameDidChangeNotification, object: document, queue: .main) { [weak self] _ in
                            MainActor.assumeIsolated { self?.place() }
                        })
                }
            }
        }
        place()
    }

    override func layout() {
        super.layout()
        roundCorner()
        place()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        roundCorner()
    }

    /// Set again whenever it is laid out: made before the view is in a window, the layer does not
    /// yet know which way it runs.
    private func roundCorner() {
        guard let layer else { return }
        let corner: CACornerMask = layer.isGeometryFlipped || layer.contentsAreFlipped() ? .layerMaxXMaxYCorner : .layerMaxXMinYCorner
        guard layer.cornerRadius != islandRadius || layer.maskedCorners != corner || !layer.masksToBounds else { return }
        clipsToBounds = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.cornerRadius = islandRadius
        layer.cornerCurve = .continuous
        layer.maskedCorners = corner
        layer.masksToBounds = true
        CATransaction.commit()
    }

    // MARK: Where the knob is

    /// The strip in the gap, as tall as the scroll view.
    private var track: CGRect {
        guard let scroll, scroll.window != nil, scroll.window === window else { return .zero }
        let frame = convert(scroll.bounds, from: scroll)
        return CGRect(x: bounds.width - gap, y: frame.minY, width: gap, height: frame.height)
    }

    private struct Way {
        /// The knob's way in the strip, and its length.
        var top: CGFloat
        var height: CGFloat
        var length: CGFloat
        /// How far the page scrolls, and how much of that it has: 0…1.
        var range: CGFloat
        var fraction: CGFloat
    }

    private func way() -> Way? {
        guard let scroll, let document = scroll.documentView else { return nil }
        let visible = scroll.contentView.bounds.height
        let content = document.frame.height
        let range = content - visible
        let track = track.insetBy(dx: 0, dy: Self.inset)
        guard range > 1, visible > 0, track.height > Self.shortestKnob * 1.5 else { return nil }
        let length = max(Self.shortestKnob, track.height * visible / content)
        let offset = scroll.contentView.bounds.minY
        let fraction = min(max((document.isFlipped ? offset : range - offset) / range, 0), 1)
        return Way(top: track.minY, height: track.height, length: length, range: range, fraction: fraction)
    }

    private func place() {
        guard let way = way() else {
            if !knob.isHidden { knob.isHidden = true }
            return
        }
        if knob.isHidden { knob.isHidden = false }
        let frame = CGRect(x: bounds.width - gap / 2 - Self.knobWidth / 2, y: way.top + (way.height - way.length) * way.fraction,
                           width: Self.knobWidth, height: way.length)
        if knob.frame != frame { knob.frame = frame }
    }

    // MARK: Shown and faded

    private func flash() {
        fading?.cancel()
        if knob.alphaValue != 1 { knob.alphaValue = 1 }
        guard !isHovered, grip == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isHovered, self.grip == nil else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    self.knob.animator().alphaValue = 0
                }
            }
        }
        fading = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.linger, execute: work)
    }

    private func light(_ lit: Bool) {
        knob.layer?.backgroundColor = CGColor(gray: 1, alpha: lit ? Self.lit : Self.rest)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let strip { removeTrackingArea(strip) }
        let area = NSTrackingArea(rect: CGRect(x: bounds.width - gap, y: 0, width: gap, height: bounds.height),
                                  options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        strip = area
    }

    override func mouseEntered(with event: NSEvent) {
        refresh()
        isHovered = true
        light(true)
        flash()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if grip == nil { light(false) }
        flash()
    }

    // MARK: Dragged

    /// Only the strip, and only while there is something to scroll.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, way() != nil else { return nil }
        let local = convert(point, from: superview)
        return track.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let way = way() else { return }
        let y = convert(event.locationInWindow, from: nil).y
        // On the knob: taken where it is held; beside it: the knob comes under the pointer.
        grip = knob.frame.insetBy(dx: -4, dy: 0).contains(CGPoint(x: knob.frame.midX, y: y)) ? y - knob.frame.minY : way.length / 2
        light(true)
        flash()
        move(to: y)
    }

    override func mouseDragged(with event: NSEvent) {
        move(to: convert(event.locationInWindow, from: nil).y)
    }

    override func mouseUp(with event: NSEvent) {
        grip = nil
        if !isHovered { light(false) }
        flash()
    }

    private func move(to y: CGFloat) {
        guard let grip, let way = way(), let scroll, let document = scroll.documentView, way.height > way.length else { return }
        let fraction = min(max((y - grip - way.top) / (way.height - way.length), 0), 1)
        let offset = document.isFlipped ? fraction * way.range : (1 - fraction) * way.range
        guard abs(scroll.contentView.bounds.minY - offset) > 0.25 else { return }
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: offset))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
