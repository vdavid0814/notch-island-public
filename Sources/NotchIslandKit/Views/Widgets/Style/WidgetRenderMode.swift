import SwiftUI

/// How a widget is drawn: `live` on the island, or `canvas` — the Customize editor's canvas and the
/// stage — where it is a picture: its glass buttons and sliders drawn as plain shapes that take
/// exactly their room (`GlassButtonPicture`, `SliderPicture`), no clock or line ticking, and
/// nothing read from the system (`isWidgetPreview`). Laid out alike, so what the editor measures
/// on the canvas is where the elements are on the island.
nonisolated enum WidgetRenderMode: Sendable {
    case live, canvas
}

extension EnvironmentValues {
    @Entry var widgetRenderMode = WidgetRenderMode.live
    /// Set by the editor (and tests): where each tagged element (`editorElement`) is drawn. Nil on
    /// the island, where tagging costs nothing.
    @Entry var widgetFrameProbe: WidgetFrameProbe?
}

/// Where each element of one widget is, in the widget's own space (its top-left corner at 0, 0,
/// padding included), as laid out: an unobserved sink, so recording a frame redraws nothing.
final class WidgetFrameProbe {
    /// The coordinate space `IslandWidgetView` names on its full frame in canvas mode.
    nonisolated static let space = "widgetFrameProbe"

    private(set) var frames: [ElementID: CGRect] = [:]

    func record(_ id: ElementID, _ frame: CGRect) { frames[id] = frame }

    /// Laid out again without the element (hidden, no room): it has no frame.
    func remove(_ id: ElementID) { frames[id] = nil }
}

extension View {
    /// Tags an element for the editor: with a probe (`\.widgetFrameProbe`, read once by the
    /// element's view) its frame is recorded; without one — the island — this is the view itself.
    @ViewBuilder func editorElement(_ id: ElementID, in probe: WidgetFrameProbe?) -> some View {
        if let probe {
            onGeometryChange(for: CGRect.self) { $0.frame(in: .named(WidgetFrameProbe.space)) } action: { probe.record(id, $0) }
                .onDisappear { probe.remove(id) }
        } else {
            self
        }
    }
}

/// A glass button at rest, drawn with plain shapes: the label in the control size's font and the
/// system button's own padding (measured: every glass and bordered button of one control size takes
/// the same room), on a faint circle, capsule or rounded rectangle — or the tint, prominent.
struct GlassButtonPicture: ButtonStyle {
    let prominent: Bool
    let shape: ButtonShapeChoice
    /// The glass's own tint (a Now Playing button's look); nil is the plain glass, or the tint.
    var fill: Color?

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let (vertical, horizontal, round) = Self.padding(controlSize)
        configuration.label
            // The system button's own font where the button has none: AppKit's for its size (a
            // picture rendered off screen gets no font from the control size).
            .transformEnvironment(\.font) { font in
                if font == nil { font = .system(size: NSFont.systemFontSize(for: Self.appKitSize(controlSize))) }
            }
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.vertical, vertical)
            .padding(.horizontal, shape == .circle ? round : horizontal)
            .background { face }
            .opacity(isEnabled ? 1 : 0.5)
    }

    @ViewBuilder private var face: some View {
        let fill = fill.map(AnyShapeStyle.init) ?? (prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.14)))
        switch shape {
        case .circle: Circle().fill(fill)
        case .capsule: Capsule().fill(fill)
        case .roundedRectangle: RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill)
        }
    }

    static func appKitSize(_ size: ControlSize) -> NSControl.ControlSize {
        switch size {
        case .mini: .mini
        case .small: .small
        case .large: .large
        case .extraLarge: .extraLarge
        default: .regular
        }
    }

    /// Around the label: above and below, beside it in a capsule, beside it in a circle.
    static func padding(_ size: ControlSize) -> (CGFloat, CGFloat, CGFloat) {
        switch size {
        case .mini: (1, 8, 1)
        case .small: (3, 10, 3)
        case .large: (6, 14, 6)
        case .extraLarge: (8, 16, 8)
        default: (4, 12, 4)
        }
    }
}
