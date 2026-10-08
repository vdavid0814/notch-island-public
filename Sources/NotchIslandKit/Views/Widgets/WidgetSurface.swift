import SwiftUI

/// What the widget sits on: nothing, a faint plate, or a plate in its colour
/// (`IslandWidget.background`, at its strength), in the widget's corners.
struct WidgetSurface: View {
    let widget: IslandWidget
    let size: CGSize
    let accent: Color?
    let corners: RectangleCornerRadii

    var body: some View {
        // A one-cell widget is always a circle, whatever the cell's proportions at this island
        // size (a cell a little wider than tall would otherwise make a capsule).
        if WidgetMetrics.isRound(widget) {
            let side = min(size.width, size.height)
            fill(Circle())
                .frame(width: side, height: side)
                .frame(width: size.width, height: size.height)
        } else if let radius = corners.uniformRadius {
            fill(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            fill(UnevenRoundedRectangle(cornerRadii: corners, style: .continuous))
        }
    }

    @ViewBuilder private func fill<S: Shape>(_ shape: S) -> some View {
        let strength = widget.effectiveBackgroundOpacity
        switch widget.background {
        case .none:
            Color.clear
        case .plate:
            // 0.4, its default, is the plate it always was.
            shape.fill(.white.opacity(0.28 * strength))
        case .tinted:
            let color = widget.backgroundColor?.color ?? accent ?? .islandAccent
            shape.fill(LinearGradient(colors: [color.opacity(strength), color.opacity(0.44 * strength)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}
