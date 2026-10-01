import SwiftUI

// The knob a bar may wear where its fill ends (`LineStyle.knob`): drawn by SwiftUI on a still bar
// and on the canvas, by Core Animation on Now Playing's moving line (`PlayedLineView`) — the same
// size and corners in both.

nonisolated extension KnobShape {
    /// Its size on a line `thickness` thick.
    func size(thickness: CGFloat) -> CGSize {
        let side = max(thickness * 2.2, 10)
        switch self {
        case .none: return .zero
        case .circle, .square: return CGSize(width: side, height: side)
        case .pill: return CGSize(width: side * 0.55, height: side)
        case .line: return CGSize(width: max(thickness * 0.5, 2.5), height: side)
        }
    }

    func cornerRadius(_ size: CGSize) -> CGFloat {
        switch self {
        case .none: 0
        case .circle, .pill, .line: min(size.width, size.height) / 2
        case .square: min(size.width, size.height) * 0.22
        }
    }

    /// Where its centre is on a line `width` long filled to `fraction` (the end of the fill's round cap).
    static func centre(_ fraction: Double, in width: CGFloat, thickness: CGFloat) -> CGFloat {
        max(thickness, width * CGFloat(min(max(fraction, 0), 1))) - thickness / 2
    }
}

/// The knob on a still bar (or on the canvas), centred where the fill ends.
struct LineKnob: View {
    let shape: KnobShape
    let thickness: CGFloat
    let color: Color

    var body: some View {
        let size = shape.size(thickness: thickness)
        if shape != .none {
            RoundedRectangle(cornerRadius: shape.cornerRadius(size), style: .continuous)
                .fill(color)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                .frame(width: size.width, height: size.height)
        }
    }
}

extension ResolvedLine {
    /// The knob as the style sets it; nil without one.
    var knobShape: KnobShape? { knob.flatMap { $0 == .none ? nil : $0 } }

    /// Its colour (white unless set).
    func knobColor(artwork: Color?) -> Color { knobFill?.color(artwork: artwork) ?? .white }
}
