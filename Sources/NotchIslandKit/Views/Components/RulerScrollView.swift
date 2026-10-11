import AppKit
import SwiftUI

/// The ruler's live scale as layers in an AppKit scroll view: its ticks are drawn once, a swipe
/// moves the scroll view's clip (no SwiftUI update, where SwiftUI's own scroll view laid the
/// island's whole view tree out again at every frame, ~5 ms of a performance core), and the app
/// works only when another tick comes under the marker: the tick takes its colour and the value is
/// handed on (`onValue`).
///
/// The motion is the system's, as SwiftUI's scroll view had it (it is an `NSScrollView` too):
/// the fingers' scroll, AppKit's momentum and its rubber band at both ends. The momentum ends on a
/// whole tick as `viewAligned` made it: AppKit asks where it may end
/// (`scrollViewBeganMomentum:withVelocity:targetContentOffset:`).
struct RulerScale: NSViewRepresentable {
    /// The value under the marker.
    let value: Int
    let range: ClosedRange<Int>
    /// The first value the ruler settles on; the ones under it are landmarks beside the scale.
    let first: Int
    let isEditable: Bool
    let showsLabels: Bool
    let tint: Color
    let ends: ButtonLook.Corners
    /// The user moved the ruler onto this value.
    let onValue: (Int) -> Void
    let onInteraction: (Bool) -> Void

    func makeNSView(context: Context) -> RulerScrollView { RulerScrollView() }

    func updateNSView(_ view: RulerScrollView, context: Context) {
        view.onValue = onValue
        view.onInteraction = onInteraction
        view.show(RulerScrollView.Scale(range: range, first: first, isEditable: isEditable, showsLabels: showsLabels,
                                        tint: tint.resolve(in: context.environment), ends: ends), value: value)
    }
}

final class RulerScrollView: NSScrollView {
    struct Scale: Equatable {
        var range: ClosedRange<Int>
        var first: Int
        var isEditable: Bool
        var showsLabels: Bool
        var tint: Color.Resolved
        var ends: ButtonLook.Corners

        /// The value under the marker when the scale is scrolled to `offset`.
        func value(at offset: CGFloat) -> Int {
            min(max(first + Int((offset / TimerRuler.tickSpacing).rounded()), first), range.upperBound)
        }

        func offset(of value: Int) -> CGFloat { CGFloat(value - first) * TimerRuler.tickSpacing }

        func clamp(_ value: Int) -> Int { min(max(value, first), range.upperBound) }
    }

    var onValue: (Int) -> Void = { _ in }
    var onInteraction: (Bool) -> Void = { _ in }

    private let scaleView = RulerScaleView()
    private var scale: Scale?
    /// The value the ticks are coloured for: the one under the marker.
    private var value = 0
    private var builtSize = CGSize.zero
    /// The fingers or the momentum are moving it.
    private var isLive = false
    /// Where a press began (in the view's own points: the widget may be drawn scaled, and a tick
    /// then follows the pointer as it is drawn), and the value a drag started from once it is one.
    private var press: CGFloat?
    private var dragStart: Int?
    nonisolated(unsafe) private var observers: [any NSObjectProtocol] = []

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = false
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .none
        automaticallyAdjustsContentInsets = false
        contentView.drawsBackground = false
        contentView.postsBoundsChangedNotifications = true
        documentView = scaleView
        // Where the momentum may end (AppKit's own, not in the headers): on a whole tick.
        let setDelegate = NSSelectorFromString("setDelegate:")
        if responds(to: setDelegate) { perform(setDelegate, with: self) }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.scrolled() }
            },
            center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: self, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.liveScroll(began: true) }
            },
            center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: self, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.liveScroll(began: false) }
            },
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RulerScrollView is created in code only")
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// The panel never becomes key: the first press already drags.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: The scale and its value

    func show(_ new: Scale, value newValue: Int) {
        let target = new.isEditable ? new.clamp(newValue) : min(max(newValue, new.range.lowerBound), new.range.upperBound)
        guard new != scale else {
            // Set from elsewhere (a reset, the running countdown): glide there. Not while the user
            // moves the ruler — that is where the value came from.
            guard target != value, !isLive, dragStart == nil else { return }
            let from = contentView.bounds.origin.x
            mark(target)
            scroll(to: new.offset(of: target))
            scaleView.glide(by: new.offset(of: target) - from)
            return
        }
        scale = new
        value = target
        build()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize != builtSize { build() }
    }

    /// The ticks for this size, the scale on its value: from the first frame, and again while the
    /// island grows around it.
    private func build() {
        guard let scale, bounds.width > 0, bounds.height > 0 else { return }
        builtSize = bounds.size
        let spacing = TimerRuler.tickSpacing
        let margin = max(0, bounds.width / 2 - spacing / 2)
        let count = scale.range.upperBound - scale.first + 1
        scaleView.frame = CGRect(x: 0, y: 0, width: margin * 2 + CGFloat(count) * spacing, height: bounds.height)
        scaleView.draw(scale, value: value, margin: margin, pixel: 1 / (window?.backingScaleFactor ?? 2))
        guard !isLive, dragStart == nil else { return }
        scroll(to: scale.offset(of: value))
    }

    override func layout() {
        super.layout()
        align()
    }

    private func scroll(to offset: CGFloat) {
        if contentView.bounds.origin.x != offset {
            contentView.setBoundsOrigin(CGPoint(x: offset, y: 0))
            reflectScrolledClipView(contentView)
        }
        align()
    }

    /// At rest the ticks are exactly where the resting picture has them. The scroll view keeps its
    /// clip on whole device pixels, and the widget is drawn scaled: that is up to a quarter of a
    /// point off the tick, either way and up or down — the ticks would shift under the pointer as
    /// the picture gives way to them. The scale is drawn that much the other way.
    private func align() {
        guard let scale, !isLive else { return }
        let origin = contentView.bounds.origin
        scaleView.shift = CGPoint(x: origin.x - scale.offset(of: value), y: origin.y)
    }

    /// The ticks' colours for `new` under the marker.
    private func mark(_ new: Int) {
        guard new != value else { return }
        scaleView.mark(from: value, to: new)
        value = new
    }

    // MARK: Scrolling

    override func scrollWheel(with event: NSEvent) {
        // A countdown's ruler only shows: the scroll is the panel's (its pages).
        guard scale?.isEditable == true else {
            nextResponder?.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    private func scrolled() {
        guard isLive, let scale else { return align() }
        let new = scale.value(at: contentView.bounds.origin.x)
        guard new != value else { return }
        mark(new)
        onValue(new)
    }

    private func liveScroll(began: Bool) {
        isLive = began
        onInteraction(began)
        guard !began, let scale else { return }
        // Settled: the tick under the marker is the value.
        let offset = contentView.bounds.origin.x
        let new = scale.value(at: offset)
        if new != value {
            mark(new)
            onValue(new)
        }
        // AppKit's momentum left it within a pixel of the tick (`align`); let go further off, it
        // glides onto it.
        let rest = scale.offset(of: new)
        if abs(rest - offset) > 1 {
            scroll(to: rest)
            scaleView.glide(by: rest - offset)
        } else {
            align()
        }
    }

    /// AppKit's momentum is about to start for `target`: it ends on the nearest whole tick.
    @objc(scrollViewBeganMomentum:withVelocity:targetContentOffset:)
    func momentumBegan(_ scrollView: NSScrollView, velocity: CGPoint, target: UnsafeMutablePointer<CGPoint>) {
        guard let scale else { return }
        target.pointee.x = scale.offset(of: scale.value(at: target.pointee.x))
    }

    // MARK: Dragging

    // The mouse has no scroll gesture of its own: a drag moves the ruler a tick per tick's width.

    override func mouseDown(with event: NSEvent) {
        guard scale?.isEditable == true else { return super.mouseDown(with: event) }
        press = convert(event.locationInWindow, from: nil).x
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press, let scale else { return super.mouseDragged(with: event) }
        let moved = convert(event.locationInWindow, from: nil).x - press
        if dragStart == nil {
            guard abs(moved) >= 2 else { return }
            dragStart = value
            onInteraction(true)
        }
        let target = scale.clamp((dragStart ?? value) - Int((moved / TimerRuler.tickSpacing).rounded()))
        guard target != value else { return }
        mark(target)
        scroll(to: scale.offset(of: target))
        onValue(target)
    }

    override func mouseUp(with event: NSEvent) {
        guard press != nil else { return super.mouseUp(with: event) }
        press = nil
        guard dragStart != nil else { return }
        dragStart = nil
        onInteraction(false)
    }
}

/// The scale's ticks as layers, each where SwiftUI puts its `Tick` (on whole pixels) and coloured as
/// it colours them: full up to the value, dimmed past it. Only the ticks between two values change
/// when the value does.
final class RulerScaleView: NSView {
    private var scale: RulerScrollView.Scale?
    /// The ticks' own layer, moved by `shift` under the view's.
    private let content = CALayer()
    private var ticks: [Int: CALayer] = [:]
    private var labels: [Int: CALayer] = [:]
    private var pixel: CGFloat = 0.5

    /// How far the ticks are drawn from where the view has them (`RulerScrollView.align`).
    var shift = CGPoint.zero {
        didSet {
            guard shift != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            content.position = shift
            CATransaction.commit()
        }
    }

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        content.anchorPoint = .zero
        layer?.addSublayer(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RulerScaleView is created in code only")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func draw(_ scale: RulerScrollView.Scale, value: Int, margin: CGFloat, pixel: CGFloat) {
        self.scale = scale
        self.pixel = pixel
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        ticks.values.forEach { $0.removeFromSuperlayer() }
        labels.values.forEach { $0.removeFromSuperlayer() }
        ticks.removeAll(keepingCapacity: true)
        labels.removeAll(keepingCapacity: true)
        let spacing = TimerRuler.tickSpacing
        let top = scale.showsLabels ? Tick.labelHeight + Tick.labelGap : 0
        let radius = scale.ends.radius(height: Tick.width)
        for minute in scale.range {
            let left = margin + CGFloat(minute - scale.first) * spacing
            let inset = minute % 5 == 0 ? 0 : Tick.minorInset
            let tick = CALayer()
            tick.frame = whole(CGRect(x: left + (spacing - Tick.width) / 2, y: top + inset,
                                      width: Tick.width, height: max(0, bounds.height - top - 2 * inset)))
            tick.cornerRadius = radius
            tick.cornerCurve = .continuous
            tick.backgroundColor = tickColor(scale, isPast: minute > value)
            tick.contentsScale = 1 / pixel
            content.addSublayer(tick)
            ticks[minute] = tick
            guard scale.showsLabels, minute % 5 == 0, let number = Self.number(minute, tint: scale.tint, isPast: minute > value, pixel: pixel) else { continue }
            // Its text centred in its column, over the tick, as the resting picture has it.
            let label = CALayer()
            label.frame = whole(CGRect(x: left + (spacing - number.size.width) / 2, y: (Tick.labelHeight - number.size.height) / 2,
                                       width: number.size.width, height: number.size.height))
            label.contentsScale = 1 / pixel
            label.contents = number.image
            content.addSublayer(label)
            labels[minute] = label
        }
    }

    func mark(from old: Int, to new: Int) {
        guard let scale else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        // Past the value: dimmed. The ticks in (lower, upper] change sides.
        for minute in (min(old, new) + 1)...max(old, new) where scale.range.contains(minute) {
            ticks[minute]?.backgroundColor = tickColor(scale, isPast: minute > new)
            if let label = labels[minute] {
                label.contents = Self.number(minute, tint: scale.tint, isPast: minute > new, pixel: pixel)?.image
            }
        }
    }

    // MARK: The numbers

    private struct NumberKey: Hashable {
        let minute: Int
        let tint: Color.Resolved
        let isPast: Bool
        let pixel: CGFloat
    }

    /// Drawn once each (a scale's numbers are the same every time it wakes).
    private static var numbers: [NumberKey: (image: CGImage, size: CGSize)] = [:]

    /// `TickLabel`'s type: 10-point rounded semibold, its figures all as wide.
    private static let numberFont: NSFont = {
        let base = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 10) } ?? base
    }()

    /// A fifth minute's number as `TickLabel` draws it: a picture of its text and its size in points.
    private static func number(_ minute: Int, tint: Color.Resolved, isPast: Bool, pixel: CGFloat) -> (image: CGImage, size: CGSize)? {
        let key = NumberKey(minute: minute, tint: tint, isPast: isPast, pixel: pixel)
        if let number = numbers[key] { return number }
        var color = tint
        color.opacity *= isPast ? 0.4 : 0.9
        let text = NSAttributedString(string: "\(minute)", attributes: [
            .font: numberFont, .foregroundColor: NSColor(cgColor: color.cgColor) ?? .orange,
        ])
        let bounds = text.boundingRect(with: CGSize(width: 1000, height: 1000), options: [.usesLineFragmentOrigin])
        func up(_ value: CGFloat) -> CGFloat { (value / pixel).rounded(.up) * pixel }
        let size = CGSize(width: up(bounds.width), height: up(bounds.height))
        let scale = 1 / pixel
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        text.draw(with: CGRect(origin: .zero, size: size), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        if numbers.count > 400 { numbers.removeAll(keepingCapacity: true) }
        numbers[key] = (image, size)
        return (image, size)
    }

    /// The scale shown `distance` before where it is, onto it over three frames: as SwiftUI's
    /// scroll view came to a value set from outside (measured: about three fifths of the way a
    /// frame in, there at the next, whatever animation it was asked with).
    func glide(by distance: CGFloat) {
        guard distance != 0 else { return }
        let move = CABasicAnimation(keyPath: "position.x")
        move.isAdditive = true
        move.fromValue = distance
        move.toValue = 0
        move.duration = 0.05
        move.timingFunction = CAMediaTimingFunction(name: .easeOut)
        content.add(move, forKey: "glide")
    }

    private func tickColor(_ scale: RulerScrollView.Scale, isPast: Bool) -> CGColor {
        var color = scale.tint
        if isPast { color.opacity *= 0.35 }
        return color.cgColor
    }

    /// On whole pixels, as SwiftUI places a view's edges.
    private func whole(_ rect: CGRect) -> CGRect {
        func snap(_ value: CGFloat) -> CGFloat { (value / pixel).rounded(.toNearestOrAwayFromZero) * pixel }
        let minX = snap(rect.minX), minY = snap(rect.minY)
        return CGRect(x: minX, y: minY, width: snap(rect.maxX) - minX, height: snap(rect.maxY) - minY)
    }
}
