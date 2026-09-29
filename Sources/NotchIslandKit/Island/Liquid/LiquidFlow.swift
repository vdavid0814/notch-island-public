import SwiftUI

/// A rounded rectangle of the liquid, in global AppKit coordinates (y up).
nonisolated struct LiquidBlob: Sendable, Equatable {
    var rect: CGRect
    var radius: CGFloat

    func mixed(with other: LiquidBlob, by t: Double) -> LiquidBlob {
        let t = CGFloat(t)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        return LiquidBlob(rect: CGRect(x: mix(rect.minX, other.rect.minX), y: mix(rect.minY, other.rect.minY),
                                       width: mix(rect.width, other.rect.width), height: mix(rect.height, other.rect.height)),
                          radius: mix(radius, other.radius))
    }
}

/// The shapes of the liquid that runs out of the notch to macOS's volume card and back: the notch
/// swelling, a drop leaving its side along the menu bar, the neck between them thinning until it
/// parts, and the drop spreading into the card's shape where the card comes up.
///
/// Drawn blurred and cut at half alpha (`LiquidCardView`), so shapes near each other merge with a
/// liquid's concave fillets and a neck thinner than the blur parts by itself. Pure: frames can be
/// drawn and checked without a window.
nonisolated enum LiquidFlow {
    /// The blur the shapes merge by: the fillets' size.
    static let blur: CGFloat = 7
    /// The way out, timed to macOS's card, which comes up ~170 ms after the island hears of an
    /// AirPods change and grows from 93 % over 0.3 s (measured): the drop is on it as it comes
    /// up, overshooting a little. The way back, and a move to where the card really came up.
    /// 0.05 s slower each way than first tuned (asked for).
    static let out = LiquidCurve(duration: 0.25, overshoot: 0.035)
    static let back = LiquidCurve(duration: 0.35, overshoot: 0)
    static let move = LiquidCurve(duration: 0.22, overshoot: 0.02)

    /// The liquid lands on the card's own outline, edge on edge: the fade style's glass clears
    /// towards the edges, and a cover any larger would show macOS's card's edge through it.
    static func cover(overCardWindow window: CGRect, kind: SystemVolumeCard.Kind = .volume) -> LiquidBlob {
        LiquidBlob(rect: SystemVolumeCard.card(inWindow: window, kind: kind), radius: kind.radius)
    }

    /// The drop as it leaves: inside the notch, at the side facing where it goes.
    static func start(notch: CGRect, towards end: CGRect) -> LiquidBlob {
        let height = notch.height * 0.9
        let width = notch.height * 1.4
        let right = end.midX >= notch.midX
        let x = right ? notch.maxX - width - 2 : notch.minX + 2
        return LiquidBlob(rect: CGRect(x: x, y: notch.maxY - notch.height * 0.5 - height / 2, width: width, height: height),
                          radius: height / 2)
    }

    /// The drop `progress` of the way (past 1 in the spring's overshoot): first along the menu bar,
    /// then down into place, stretched while it runs and spreading to the card's size as it lands.
    static func drop(_ progress: Double, from start: LiquidBlob, to end: LiquidBlob) -> LiquidBlob {
        let p = CGFloat(progress)
        let clamped = min(max(p, 0), 1)
        // The overshoot spreads the drop past the card's edges rather than carrying it past: moved,
        // it would bare the card's far edge.
        let splash = max(0, p - 1)
        let down = smoothstep(0.12, 0.9, clamped)
        let center = CGPoint(x: start.rect.midX + (end.rect.midX - start.rect.midX) * clamped,
                             y: start.rect.midY + (end.rect.midY - start.rect.midY) * down)
        let grow = smoothstep(0.25, 0.9, clamped)
        let stretch = 34 * sin(.pi * clamped) * (1 - grow)
        let width = start.rect.width + (end.rect.width - start.rect.width) * grow + stretch + end.rect.width * splash * 1.2
        let height = start.rect.height + (end.rect.height - start.rect.height) * smoothstep(0.35, 1, clamped)
            + end.rect.height * splash * 1.6
        // Round-ended while it runs; the card's corners only as it lands.
        let radius = min(height / 2 + (end.radius - height / 2) * smoothstep(0.6, 1, clamped), height / 2, width / 2)
        return LiquidBlob(rect: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
                          radius: radius)
    }

    /// The notch, swollen by `swell` (0…1) as the drop gathers in it or runs back into it; drawn up
    /// past the screen's top edge, so the blur never rounds the island off there.
    static func notch(_ notch: CGRect, swell: CGFloat, overdraw: CGFloat) -> Path {
        let grow = 12 * swell
        let rect = CGRect(x: notch.minX - grow, y: notch.minY - grow * 0.5, width: notch.width + 2 * grow,
                          height: notch.height + grow * 0.5 + overdraw)
        let radius = min(8 + grow, notch.height / 2)
        return Path(roundedRect: rect, cornerRadii: .init(topLeading: radius, bottomLeading: 0, bottomTrailing: 0, topTrailing: radius),
                    style: .continuous)
    }

    /// The neck from the notch's side to the drop, `thickness` wide at its ends and thinner in the
    /// middle, where it parts as it thins (a chain of discs the blur melts into one).
    static func neck(notch: CGRect, to drop: CGRect, thickness: CGFloat) -> Path? {
        guard thickness >= 1 else { return nil }
        let right = drop.midX >= notch.midX
        let anchor = CGPoint(x: right ? notch.maxX - notch.height * 0.6 : notch.minX + notch.height * 0.6,
                             y: notch.maxY - notch.height * 0.45)
        let end = CGPoint(x: drop.midX, y: drop.midY)
        let length = hypot(end.x - anchor.x, end.y - anchor.y)
        let count = max(4, Int(length / 6))
        var path = Path()
        for index in 0...count {
            let s = CGFloat(index) / CGFloat(count)
            let radius = thickness / 2 * (1 - 0.55 * sin(.pi * s))
            guard radius > 0.3 else { continue }
            let center = CGPoint(x: anchor.x + (end.x - anchor.x) * s, y: anchor.y + (end.y - anchor.y) * s)
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }
        return path
    }

    static func path(_ blob: LiquidBlob) -> Path {
        Path(roundedRect: blob.rect, cornerRadius: max(0, blob.radius), style: .continuous)
    }

    static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Up and back down over `duration` (0 before and after).
    static func bump(_ t: CGFloat, over duration: CGFloat) -> CGFloat {
        guard t > 0, t < duration else { return 0 }
        return sin(.pi * t / duration)
    }
}

/// Progress over time: slow to leave (the liquid gathers), quick in the middle, easing into place,
/// with a small overshoot that settles back.
nonisolated struct LiquidCurve: Sendable, Equatable {
    /// When it first reaches 1.
    var duration: TimeInterval
    /// How far past 1 it swings.
    var overshoot: Double

    /// Until it is still.
    var total: TimeInterval { overshoot > 0 ? duration * 1.4 : duration }

    func value(at t: TimeInterval) -> Double {
        guard t > 0 else { return 0 }
        let x = min(t / duration, 1)
        let base = x * x * x * (x * (6 * x - 15) + 10)
        guard overshoot > 0 else { return base }
        // A swell centred on the arrival, from 0.6 to 1.4 of `duration`.
        let swing = min(max((t - duration * 0.6) / (duration * 0.8), 0), 1)
        return base + overshoot * sin(.pi * swing)
    }
}
