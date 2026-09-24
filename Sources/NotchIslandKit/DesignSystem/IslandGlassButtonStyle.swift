import SwiftUI

/// The island's buttons are the system's own Liquid Glass buttons (`.glass`, `.glassProminent`):
/// native metrics, press feedback, hover and accessibility, sized by the control size like any
/// other macOS button. A circle shows its symbol only (the title stays the accessibility label).
nonisolated enum IslandButtonShape: Sendable {
    case capsule, circle
}

extension View {
    func islandButton(_ shape: IslandButtonShape = .capsule, prominent: Bool = false) -> some View {
        modifier(IslandButtonModifier(shape: shape, prominent: prominent))
    }

    /// The timer's one action (Start, Pause, Done): prominent glass in the timer's colour, like the
    /// iPhone's orange "Start Timer"; a circle with the symbol when there is no room for the title.
    func timerAction(iconOnly: Bool, tint: Color) -> some View {
        islandButton(iconOnly ? .circle : .capsule, prominent: true)
            .tint(tint)
    }
}

private struct IslandButtonModifier: ViewModifier {
    let shape: IslandButtonShape
    let prominent: Bool

    /// A widget drawn as a picture (Settings' gallery): each glass button there would keep its own
    /// backdrop buffers (sixteen widgets of them cost ~130 MB of graphics memory, measured), so the
    /// pictures use the system's plain bordered buttons in the same shape.
    @Environment(\.isWidgetPreview) private var isPreview

    func body(content: Content) -> some View {
        Group {
            if isPreview {
                if prominent {
                    content.buttonStyle(.borderedProminent)
                } else {
                    content.buttonStyle(.bordered)
                }
            } else if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        }
        .buttonBorderShape(shape == .circle ? .circle : .capsule)
        .labelStyle(IslandButtonLabelStyle(iconOnly: shape == .circle))
    }
}

/// A circle shows the symbol alone; a capsule its symbol and title.
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

extension View {
    /// Every row of mutually exclusive choices (pages, sizes, backgrounds, categories): the
    /// system's tab bar — a segmented control in the tabs role — with the capsule corners of the
    /// system's buttons.
    func choiceBar() -> some View {
        pickerStyle(.tabs)
            .buttonBorderShape(.capsule)
    }
}
