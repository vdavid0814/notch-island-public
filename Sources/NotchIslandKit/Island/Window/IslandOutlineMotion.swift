import AppKit
import QuartzCore
import SwiftUI

/// Moves the island's outline on the render server.
///
/// Animated by SwiftUI, every frame of an open or close re-evaluated the island's surface (outline,
/// glass, shade, the content's blur) and re-encoded its display list: about half of an open's CPU,
/// the rest being the content's one-time build (measured: 304 ms per open and close, 157 ms with
/// the same change unanimated). Here SwiftUI draws the surface once, still, at an outline that
/// covers the whole move (`SurfaceHold`), and a mask over the window's content shows as much of it
/// as the island has reached: a shape layer whose path is the outline at every 60 Hz frame of the
/// spring, worked out up front. The render server plays those frames; the app does nothing until
/// the outline has landed, when the surface is drawn at its presentation again and the mask goes.
///
/// A move that starts while another is under way starts where that one is, at its speed, as
/// SwiftUI's springs do.
@MainActor final class IslandOutlineMotion: IslandOutlineMover {
    private let model: AppModel
    private weak var stage: IslandStageView?
    private let mask = CALayer()
    private let shape = CAShapeLayer()
    private var flight: Flight?
    private var nextID = 0
    private let landing = DelayedAction()
    private let unmasking = DelayedAction()

    /// Frames per second of the precomputed path (the render server interpolates between them).
    static let frameRate: Double = 60
    /// How long the mask outlives the hold, so the surface drawn at its presentation is on screen
    /// before the mask stops cutting the larger one.
    static let unmaskDelay: TimeInterval = 0.05
    /// Faded out into a drawn notch: longer, so the black the hold was drawn in is gone from the
    /// window before the mask stops hiding it.
    static let fadedUnmaskDelay: TimeInterval = 0.15
    /// On a screen without a notch the island fades over this last part of its way into the notch
    /// (and the first part out of it), so no black notch is left where there is none.
    static let fadeShare: Double = 0.4

    private struct Flight {
        let id: Int
        /// `CACurrentMediaTime` at the start.
        let start: CFTimeInterval
        let origin: OutlineVector
        let delta: OutlineVector
        let velocity: OutlineVector
        let spring: Spring
        let duration: TimeInterval
        /// SwiftUI moves this one, with the surface (`handOff`): no mask to take down.
        var isDrawnBySwiftUI = false

        func state(at time: CFTimeInterval) -> (value: OutlineVector, velocity: OutlineVector)? {
            let t = time - start
            guard t < duration else { return nil }
            return (origin + spring.value(target: delta, initialVelocity: velocity, time: t),
                    spring.velocity(target: delta, initialVelocity: velocity, time: t))
        }
    }

    init(model: AppModel) {
        self.model = model
        shape.fillColor = CGColor(gray: 0, alpha: 1)
        shape.bounds = .zero
        mask.addSublayer(shape)
    }

    func attach(to stage: IslandStageView) {
        self.stage = stage
        stage.wantsLayer = true
        stage.onResize = { [weak self] in self?.place() }
    }

    func move(from: IslandPresentation, to: IslandPresentation, spring: Spring) -> SurfaceHold? {
        guard let stage, stage.content.layer != nil else { return nil }
        let layout = model.layout
        let start = layout.outline(for: from), end = layout.outline(for: to)
        let now = CACurrentMediaTime()
        var origin = OutlineVector(start), velocity = OutlineVector.zero
        let live = flight.flatMap { $0.state(at: now) }
        if let live {
            origin = live.value
            velocity = live.velocity
        }
        let delta = OutlineVector(end) - origin
        let distance = delta.magnitudeSquared.squareRoot()
        guard distance > 0.1 || velocity.magnitudeSquared > 1 else { return nil }

        let duration = min(
            spring.settlingDuration(target: delta, initialVelocity: velocity,
                                    epsilon: max(distance * LeanSpring.settledFraction, 0.05)),
            spring.duration * 4
        )
        let count = max(2, Int((duration * Self.frameRate).rounded(.up)) + 1)
        var outlines: [IslandOutline] = []
        outlines.reserveCapacity(count)
        for index in 0..<count {
            let t = min(Double(index) / Self.frameRate, duration)
            let value = index == count - 1 ? origin + delta : origin + spring.value(target: delta, initialVelocity: velocity, time: t)
            outlines.append(value.outline)
        }

        // The surface covers both ends of the move and whatever it held already (a move reversed
        // half-way keeps the surface it had rather than redrawing it smaller). Not the open's
        // overshoot: drawn larger for it, the surface had to be redrawn at its own size once the
        // outline landed, and the glass visibly clicked into place. The overshoot runs past the
        // surface instead, where there is nothing to show, so the island lands without it.
        var covered = [origin.outline, start, end]
        if live != nil, let hold = model.island.surfaceHold { covered.append(hold.outline) }
        let tallest = covered.max { $0.size.height < $1.size.height } ?? end
        let size = CGSize(width: covered.map(\.size.width).max() ?? end.size.width,
                          height: covered.map(\.size.height).max() ?? end.size.height)
        nextID += 1
        let hold = SurfaceHold(
            id: nextID,
            outline: IslandOutline(size: size, bottomRadius: tallest.bottomRadius, shoulderRadius: tallest.shoulderRadius,
                                   shoulderDrop: tallest.shoulderDrop),
            presentation: to.isIdle ? from : to
        )
        flight = Flight(id: nextID, start: now, origin: origin, delta: delta, velocity: velocity,
                        spring: spring, duration: duration)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.content.layer?.mask = mask
        place()
        shape.path = Self.path(outlines[count - 1])
        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = outlines.map(Self.path)
        animation.keyTimes = (0..<count).map { NSNumber(value: min(Double($0) / Self.frameRate, duration) / max(duration, 0.001)) }
        animation.duration = duration
        animation.calculationMode = .linear
        // `demo/freeze`: the outline held at that moment of the move.
        if let frozen = LeanSpring.frozenTime {
            animation.speed = 0
            animation.timeOffset = min(frozen, duration)
            animation.fillMode = .both
            animation.isRemovedOnCompletion = false
        }
        shape.add(animation, forKey: "outline")
        // On a screen without a notch: the same move, fading out as it closes into the notch and in
        // as it comes out of it, in step with the outline (the share of the way left, or gone).
        let fades = model.metrics?.isPhysical == false && (to.isIdle || from.isIdle) && to != from
        if fades {
            let total = max(delta.magnitudeSquared.squareRoot(), 0.001)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = outlines.map { outline -> Float in
                let way = (OutlineVector(outline) - (to.isIdle ? origin + delta : origin)).magnitudeSquared.squareRoot() / total
                return Float(min(max(way / Self.fadeShare, 0), 1))
            }
            fade.keyTimes = animation.keyTimes
            fade.duration = duration
            fade.calculationMode = .linear
            mask.opacity = to.isIdle ? 0 : 1
            mask.add(fade, forKey: "fade")
        } else {
            mask.removeAnimation(forKey: "fade")
            mask.opacity = 1
        }
        // Settings' own window over the island clips to the same outline (`SettingsWindow`).
        SettingsWindow.current?.followOutline(animation, final: shape.path)
        CATransaction.commit()

        unmasking.cancel()
        guard LeanSpring.frozenTime == nil else { return hold }
        landing.schedule(after: duration) { [weak self] in
            guard let self else { return }
            self.flight = nil
            self.model.island.releaseSurface(hold)
            self.unmasking.schedule(after: fades && to.isIdle ? Self.fadedUnmaskDelay : Self.unmaskDelay) { [weak self] in
                guard let self, self.flight == nil else { return }
                self.stage?.content.layer?.mask = nil
                self.mask.opacity = 1
            }
        }
        return hold
    }

    func handOff(from: IslandPresentation, to: IslandPresentation, spring: Spring) -> SurfaceHold? {
        let layout = model.layout
        let now = CACurrentMediaTime()
        let previous = flight
        let live = previous.flatMap { $0.state(at: now) }
        landing.cancel()
        unmasking.cancel()
        if let stage, stage.content.layer?.mask != nil {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shape.removeAnimation(forKey: "outline")
            mask.removeAnimation(forKey: "fade")
            mask.opacity = 1
            stage.content.layer?.mask = nil
            CATransaction.commit()
        }
        // SwiftUI starts a spring from rest, at the outline the render server had reached; one of
        // its own springs under way it carries on from where it is, at its speed.
        let fromRenderServer = live != nil && previous?.isDrawnBySwiftUI == false
        let origin = live?.value ?? OutlineVector(layout.outline(for: from))
        let velocity = fromRenderServer ? .zero : live?.velocity ?? .zero
        let delta = OutlineVector(layout.outline(for: to)) - origin
        let distance = delta.magnitudeSquared.squareRoot()
        let duration = min(
            spring.settlingDuration(target: delta, initialVelocity: velocity,
                                    epsilon: max(distance * LeanSpring.settledFraction, 0.05)),
            spring.duration * 4
        )
        nextID += 1
        flight = Flight(id: nextID, start: now, origin: origin, delta: delta, velocity: velocity,
                        spring: spring, duration: duration, isDrawnBySwiftUI: true)
        guard fromRenderServer else { return nil }
        return SurfaceHold(id: nextID, outline: origin.outline, presentation: from)
    }

    /// Keeps the mask over the window's content and the outline top-centred on it (the island is
    /// top-centred on its canvas), also when the stage is resized under a move.
    private func place() {
        guard let stage else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = stage.bounds
        mask.frame = bounds
        // The path runs down from the top edge: flip it onto an unflipped view.
        shape.position = CGPoint(x: bounds.midX, y: stage.isFlipped ? bounds.minY : bounds.maxY)
        shape.setAffineTransform(stage.isFlipped ? .identity : CGAffineTransform(scaleX: 1, y: -1))
        CATransaction.commit()
    }

    /// The outline with its top centre at the origin, y running down.
    static func path(_ outline: IslandOutline) -> CGPath {
        outline.path(in: CGRect(x: -0.5, y: 0, width: 1, height: 1)).cgPath
    }
}

/// The island window's content view: a plain view the hosting view fills (inside `content`, which
/// the outline mask cuts), which reports its resizes (the mask follows them), and the line that
/// stands for the island at rest on a screen without a notch, over the content and outside the
/// mask: as the island fades into the notch it fades too, and the line stays (it went with the
/// island and flashed back once the mask was taken away).
final class IslandStageView: NSView {
    var onResize: (() -> Void)?
    /// What the outline mask cuts: the hosting view.
    let content = NSView()
    private let restLine = RestLineStrip()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        addSubview(content)
        restLine.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        restLine.isHidden = true
        addSubview(restLine)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }

    /// The line at the top centre (nil: none), shown or faded out.
    func showRestLine(_ line: RestLine?, visible: Bool, fades: Bool) {
        guard let line, line.isShown else {
            // At every transition on a notched screen: nothing to touch.
            if !restLine.isHidden { restLine.isHidden = true }
            return
        }
        let width = CGFloat(min(line.length, RestLine.lengthRange.upperBound))
        let height = CGFloat(line.thickness)
        let frame = CGRect(x: ((bounds.width - width) / 2).rounded(), y: bounds.height - RestLine.topInset - height,
                           width: width, height: height)
        if restLine.frame != frame { restLine.frame = frame }
        restLine.paint(opacity: line.opacity)
        if visible {
            restLine.layer?.removeAnimation(forKey: "fade")
            restLine.alphaValue = 1
            restLine.isHidden = false
        } else if !restLine.isHidden {
            guard fades else {
                restLine.isHidden = true
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                restLine.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.restLine.alphaValue == 0 else { return }
                    self.restLine.isHidden = true
                }
            }
        }
    }
}

/// The rest line itself: a grey stroke with round ends, which takes no clicks (the notch's hover
/// target under it does).
private final class RestLineStrip: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layer?.cornerRadius = newSize.height / 2
    }

    /// Grey, not white or black, so it reads on a light menu bar and a dark one alike.
    func paint(opacity: Double) {
        let color = CGColor(gray: 0.5, alpha: opacity)
        if layer?.backgroundColor != color { layer?.backgroundColor = color }
    }
}

/// An outline's size and radii as one vector, for the spring.
nonisolated struct OutlineVector: VectorArithmetic {
    var width: Double
    var height: Double
    var bottomRadius: Double
    var shoulderRadius: Double
    var shoulderDrop: Double

    init(width: Double, height: Double, bottomRadius: Double, shoulderRadius: Double, shoulderDrop: Double = 0) {
        self.width = width
        self.height = height
        self.bottomRadius = bottomRadius
        self.shoulderRadius = shoulderRadius
        self.shoulderDrop = shoulderDrop
    }

    init(_ outline: IslandOutline) {
        self.init(width: outline.size.width, height: outline.size.height,
                  bottomRadius: outline.bottomRadius, shoulderRadius: outline.shoulderRadius,
                  shoulderDrop: outline.shoulderDrop)
    }

    /// Radii never below zero (the open's overshoot can carry them past it), as `IslandOutline.mixed`.
    var outline: IslandOutline {
        IslandOutline(size: CGSize(width: max(0, width), height: max(0, height)),
                      bottomRadius: max(0, bottomRadius), shoulderRadius: max(0, shoulderRadius),
                      shoulderDrop: max(0, shoulderDrop))
    }

    static var zero: OutlineVector { OutlineVector(width: 0, height: 0, bottomRadius: 0, shoulderRadius: 0) }

    static func + (a: OutlineVector, b: OutlineVector) -> OutlineVector {
        OutlineVector(width: a.width + b.width, height: a.height + b.height,
                      bottomRadius: a.bottomRadius + b.bottomRadius, shoulderRadius: a.shoulderRadius + b.shoulderRadius,
                      shoulderDrop: a.shoulderDrop + b.shoulderDrop)
    }

    static func - (a: OutlineVector, b: OutlineVector) -> OutlineVector {
        OutlineVector(width: a.width - b.width, height: a.height - b.height,
                      bottomRadius: a.bottomRadius - b.bottomRadius, shoulderRadius: a.shoulderRadius - b.shoulderRadius,
                      shoulderDrop: a.shoulderDrop - b.shoulderDrop)
    }

    mutating func scale(by rhs: Double) {
        width *= rhs
        height *= rhs
        bottomRadius *= rhs
        shoulderRadius *= rhs
        shoulderDrop *= rhs
    }

    var magnitudeSquared: Double {
        width * width + height * height + bottomRadius * bottomRadius + shoulderRadius * shoulderRadius
            + shoulderDrop * shoulderDrop
    }
}
