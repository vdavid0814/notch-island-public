import SwiftUI

/// The pointer's rectangle while a handle is dragged: a thin dashed line with the size it will
/// take — accent when it fits, red when it would cover something.
struct ResizeOutline: View {
    let frame: CGRect
    let cornerRadius: CGFloat
    /// The size it lands on ("2 × 1").
    let badge: String
    /// The badge on the lower edge, away from what covers the top one.
    let badgeAtBottom: Bool
    let isValid: Bool

    var body: some View {
        let tint = isValid ? Color.islandAccent : .red
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .sizeBadge(badge, tint: tint, atBottom: badgeAtBottom)
            .frame(width: max(frame.width, 1), height: max(frame.height, 1))
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
    }
}

/// A size on a capsule of the outline's colour.
struct SizeBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint, in: Capsule())
            // On the accent, the colour that reads on it (black on the white theme's).
            .foregroundStyle(tint == Color.islandAccent ? Color.onIslandAccent : .white)
            .fixedSize()
    }
}

extension View {
    /// A `SizeBadge` straddling the top edge, or the bottom one.
    func sizeBadge(_ text: String, tint: Color, atBottom: Bool) -> some View {
        overlay(alignment: atBottom ? .bottom : .top) {
            SizeBadge(text: text, tint: tint)
                .offset(y: atBottom ? 9 : -9)
        }
    }
}

/// A snapping guide: a 1 pt line across an area of `length`, running `overshoot` past both ends.
/// Placed in a top-leading stack of the area's size.
struct GuideLine: View {
    /// `.vertical`: a vertical line at x = `position`.
    let axis: Axis
    let position: CGFloat
    let length: CGFloat
    var color: Color = .yellow
    var overshoot: CGFloat = 8

    var body: some View {
        let vertical = axis == .vertical
        Rectangle().fill(color.opacity(0.85))
            .frame(width: vertical ? 1 : length + 2 * overshoot, height: vertical ? length + 2 * overshoot : 1)
            .offset(x: vertical ? position - 0.5 : -overshoot, y: vertical ? -overshoot : position - 0.5)
    }
}
