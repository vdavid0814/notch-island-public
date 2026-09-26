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

    private struct Flight {
        let id: Int
        /// `CACurrentMediaTime` at the start.
        let start: CFTimeInterval
        let origin: OutlineVector
        let delta: OutlineVector
        let velocity: OutlineVector
        let spring: Spring
        let duration: TimeInterval

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
        guard let stage, stage.layer != nil else { return nil }
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
            outline: IslandOutline(size: size, bottomRadius: tallest.bottomRadius, shoulderRadius: tallest.shoulderRadius),
            presentation: to.isIdle ? from : to
        )
        flight = Flight(id: nextID, start: now, origin: origin, delta: delta, velocity: velocity,
                        spring: spring, duration: duration)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.layer?.mask = mask
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
        CATransaction.commit()

        unmasking.cancel()
        guard LeanSpring.frozenTime == nil else { return hold }
        landing.schedule(after: duration) { [weak self] in
            guard let self else { return }
            self.flight = nil
            self.model.island.releaseSurface(hold)
            self.unmasking.schedule(after: Self.unmaskDelay) { [weak self] in
                guard let self, self.flight == nil else { return }
                self.stage?.layer?.mask = nil
            }
        }
        return hold
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
    private static func path(_ outline: IslandOutline) -> CGPath {
        outline.path(in: CGRect(x: -0.5, y: 0, width: 1, height: 1)).cgPath
    }
}

/// The island window's content view: a plain view the hosting view fills, which reports its resizes
/// (the outline mask follows them).
final class IslandStageView: NSView {
    var onResize: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }
}

/// An outline's size and radii as one vector, for the spring.
nonisolated struct OutlineVector: VectorArithmetic {
    var width: Double
    var height: Double
    var bottomRadius: Double
    var shoulderRadius: Double

    init(width: Double, height: Double, bottomRadius: Double, shoulderRadius: Double) {
        self.width = width
        self.height = height
        self.bottomRadius = bottomRadius
        self.shoulderRadius = shoulderRadius
    }

    init(_ outline: IslandOutline) {
        self.init(width: outline.size.width, height: outline.size.height,
                  bottomRadius: outline.bottomRadius, shoulderRadius: outline.shoulderRadius)
    }

    /// Radii never below zero (the open's overshoot can carry them past it), as `IslandOutline.mixed`.
    var outline: IslandOutline {
        IslandOutline(size: CGSize(width: max(0, width), height: max(0, height)),
                      bottomRadius: max(0, bottomRadius), shoulderRadius: max(0, shoulderRadius))
    }

    static var zero: OutlineVector { OutlineVector(width: 0, height: 0, bottomRadius: 0, shoulderRadius: 0) }

    static func + (a: OutlineVector, b: OutlineVector) -> OutlineVector {
        OutlineVector(width: a.width + b.width, height: a.height + b.height,
                      bottomRadius: a.bottomRadius + b.bottomRadius, shoulderRadius: a.shoulderRadius + b.shoulderRadius)
    }

    static func - (a: OutlineVector, b: OutlineVector) -> OutlineVector {
        OutlineVector(width: a.width - b.width, height: a.height - b.height,
                      bottomRadius: a.bottomRadius - b.bottomRadius, shoulderRadius: a.shoulderRadius - b.shoulderRadius)
    }

    mutating func scale(by rhs: Double) {
        width *= rhs
        height *= rhs
        bottomRadius *= rhs
        shoulderRadius *= rhs
    }

    var magnitudeSquared: Double {
        width * width + height * height + bottomRadius * bottomRadius + shoulderRadius * shoulderRadius
    }
}
