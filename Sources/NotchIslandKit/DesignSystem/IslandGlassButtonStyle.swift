import SwiftUI

/// The island's button: a capsule (or circle) of the island's own glass, as in the CAD app's
/// `NavyGlassButtonStyle`.
///
/// Not the native `.glass` style, because its glass is `.regular` and its height follows the
/// control size by the system's own metrics; here every control wears `IslandGlass` and takes its
/// height from `Metrics.Control`, so buttons, chips and the segmented switcher line up in one row.
struct IslandGlassButtonStyle: ButtonStyle {
    nonisolated enum Shape: Sendable {
        /// Text (or text and symbol) padded inside a capsule.
        case capsule
        /// A capsule that takes the width it is offered, so a row of chips shares its row equally
        /// and ends flush with its neighbours. The width, not the padding, sets its size.
        case chip
        /// A lone symbol in a circle as wide as it is tall.
        case circle
    }

    var shape: Shape = .capsule
    /// The row's primary action (Start, Done, play/pause): accent-tinted glass with a white label.
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        // A nested view, because a `ButtonStyle` itself does not receive environment updates.
        IslandGlassButton(configuration: configuration, shape: shape, isProminent: isProminent)
    }
}

extension ButtonStyle where Self == IslandGlassButtonStyle {
    static var islandGlass: IslandGlassButtonStyle { IslandGlassButtonStyle() }

    static func islandGlass(_ shape: IslandGlassButtonStyle.Shape = .capsule, prominent: Bool = false) -> IslandGlassButtonStyle {
        IslandGlassButtonStyle(shape: shape, isProminent: prominent)
    }
}

private struct IslandGlassButton: View {
    let configuration: ButtonStyleConfiguration
    let shape: IslandGlassButtonStyle.Shape
    let isProminent: Bool

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let height = Metrics.Control.height(controlSize)
        let isCircle = shape == .circle
        let padding: CGFloat = switch shape {
        case .capsule: Metrics.Control.horizontalPadding(controlSize)
        case .chip: Metrics.Spacing.xSmall
        case .circle: 0
        }
        configuration.label
            .labelStyle(IslandButtonLabelStyle(iconOnly: isCircle))
            .font(Metrics.Control.font(controlSize))
            .lineLimit(1)
            .foregroundStyle(isProminent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            // Dim the label, not the glass: a disabled control is still a piece of the surface.
            .opacity(isEnabled ? 1 : 0.4)
            .frame(maxWidth: shape == .chip ? .infinity : nil)
            .padding(.horizontal, padding)
            .frame(width: isCircle ? height : nil, height: height)
            .frame(minWidth: height)
            .contentShape(.capsule)
            // A circle is a capsule as wide as it is tall, so one shape serves both.
            .islandGlass(isProminent ? IslandGlass.active : IslandGlass.control, in: .capsule)
            .modifier(IslandPressFeedback(isPressed: configuration.isPressed))
    }
}

/// Symbol and title closer together than the default label spacing, as in the CAD buttons; a
/// circle shows the symbol alone (the title stays the accessibility label).
private struct IslandButtonLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: Metrics.Spacing.xSmall) {
                configuration.icon
                configuration.title
            }
        }
    }
}

/// The CAD app's press feedback (`CadPressFeedback`): a slight shrink and fade while held. Under
/// Reduce Motion there is no shrink and the fade is immediate.
struct IslandPressFeedback: ViewModifier {
    let isPressed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(isPressed ? 0.84 : 1)
            .animation(reduceMotion ? nil : IslandGlass.press, value: isPressed)
    }
}
