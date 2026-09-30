import SwiftUI

/// Something the user added to a custom layout (the grid inside a widget), on its rectangle: a
/// label, a symbol, a divider or a shape, styled like any element — a label's type and colour, a
/// symbol's weight and colours, a divider's and a shape's fill, border and opacity. Nothing in it
/// ticks or reads the system.
struct DecorationView: View {
    let id: ElementID
    let decoration: Decoration
    /// Its rectangle in the widget.
    let frame: CGRect

    @Environment(\.widgetPlan) private var plan
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetArtworkColor) private var artwork
    @Environment(\.elementCorners) private var corners

    /// A label as it is added, before it is reworded.
    static let labelType = TypeSpec(points: 13, weight: .medium)

    var body: some View {
        let element = style.element(id)
        let planned = plan?.elements[id]
        switch decoration {
        case .label(let text):
            let type = Self.labelType.at(planned?.points ?? Self.labelType.points)
            Text(element?.text.labelOverride ?? text)
                .widgetText(id, type, in: style)
                .lineLimit(element?.text.lineLimit ?? 1)
                .frame(width: frame.width, height: frame.height, alignment: element?.text.alignment?.frameAlignment ?? .center)
        case .symbol(let name):
            Image(systemName: name)
                .widgetSymbol(id, points: planned?.points ?? 13, weight: .medium, in: style)
                .frame(width: frame.width, height: frame.height)
        case .divider:
            // The whole rectangle: as thick as it is drawn.
            Capsule()
                .fill(fill(element, standard: .white.opacity(0.22)))
                .opacity(element?.image.opacity ?? 1)
                .frame(width: frame.width, height: frame.height)
        case .shape(let shape):
            DecorationShapeView(shape: shape, corners: corners, fill: fill(element, standard: .white.opacity(0.12)),
                                border: element?.colors[.border]?.color(artwork: artwork),
                                borderWidth: CGFloat(element?.image.borderWidth ?? 0))
                .opacity(element?.image.opacity ?? 1)
                .frame(width: frame.width, height: frame.height)
        }
    }

    private func fill(_ element: ElementStyle?, standard: Color) -> Color {
        element?.colors[.fill]?.color(artwork: artwork) ?? standard
    }
}

private struct DecorationShapeView: View {
    let shape: DecorationShape
    /// Set where the shape reaches a corner of the widget.
    let corners: RectangleCornerRadii?
    let fill: Color
    let border: Color?
    let borderWidth: CGFloat

    var body: some View {
        switch shape {
        case .circle:
            Circle().fill(fill).overlay { if let border, borderWidth > 0 { Circle().strokeBorder(border, lineWidth: borderWidth) } }
        case .capsule:
            Capsule().fill(fill).overlay { if let border, borderWidth > 0 { Capsule().strokeBorder(border, lineWidth: borderWidth) } }
        case .rectangle:
            outline(corners ?? RectangleCornerRadii())
        case .roundedRectangle:
            // Its own corners, and the widget's where it lies in one.
            outline(RectangleCornerRadii(topLeading: max(corners?.topLeading ?? 0, 8), bottomLeading: max(corners?.bottomLeading ?? 0, 8),
                                         bottomTrailing: max(corners?.bottomTrailing ?? 0, 8), topTrailing: max(corners?.topTrailing ?? 0, 8)))
        }
    }

    private func outline(_ radii: RectangleCornerRadii) -> some View {
        let shape = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
        return shape.fill(fill).overlay { if let border, borderWidth > 0 { shape.strokeBorder(border, lineWidth: borderWidth) } }
    }
}

nonisolated extension ElementDemand {
    /// A decoration as the custom layout's planner asks for it: a label and a symbol take their
    /// size from their rectangle (or the style's fixed size), a divider and a shape are boxes.
    init(decoration: Decoration, id: ElementID, input: PlanInput) {
        let style = input.style.elements[id]
        let content: Content = switch decoration {
        case .label(let text):
            .text(samples: [style?.text.labelOverride ?? text], type: DecorationView.labelType.applying(style?.text ?? TextStyle()),
                  lines: style?.text.lineLimit ?? 1)
        case .symbol(let name):
            .symbol(name: name, weight: style?.symbol.weight ?? .medium)
        case .divider, .shape:
            .box(.zero)
        }
        let size: TextSize = switch decoration {
        case .label: style?.text.points.map { .fixed($0) } ?? .auto(.medium)
        case .symbol: style?.symbol.points.map { .fixed($0) } ?? .auto(.medium)
        case .divider, .shape: .auto(.medium)
        }
        self.init(id: id, content: content, design: DecorationView.labelType.points * input.scale, size: size, priority: 10, minRoom: nil)
    }
}
