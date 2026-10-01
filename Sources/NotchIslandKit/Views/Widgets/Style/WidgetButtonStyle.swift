import SwiftUI

// A widget's button, one way wherever it is drawn. What it looks like is said in three places —
// the island's own (`islandButton`: glass or prominent, a circle or a capsule), a Now Playing
// button's colour (`transportGlass`), the element's style (`widgetButton`: its look, shape and
// colour) — and each only says it in the environment, the nearer winning; the one style below
// draws from all of it, reading it where the button is. (Each set a button style of its own
// before, and the innermost won: a colour or a look set in Settings could go missing.)

/// A button's look as said so far; nil: not said.
struct ButtonAppearance: Equatable {
    var look: ButtonLookChoice?
    var shape: ButtonShapeChoice?
    /// The face's colour (the glass's tint, the prominent fill, the bordered face).
    var tint: Color?
    /// A rounded rectangle's corners (nil: its own).
    var radius: CGFloat?
    /// The symbol's and title's colour (nil: the look's own).
    var icon: Color?

    /// The shape the system's button styles draw.
    var borderShape: ButtonBorderShape {
        let shape = shape ?? .capsule
        if shape == .roundedRectangle, let radius { return .roundedRectangle(radius: radius) }
        return shape.borderShape
    }
}

extension EnvironmentValues {
    @Entry var widgetButtonAppearance = ButtonAppearance()
}

extension View {
    /// Says what the button looks like where it is not said nearer to it.
    func buttonAppearance(look: ButtonLookChoice? = nil, shape: ButtonShapeChoice? = nil, tint: Color? = nil,
                          radius: CGFloat? = nil, icon: Color? = nil) -> some View {
        transformEnvironment(\.widgetButtonAppearance) { appearance in
            if let look { appearance.look = look }
            if let shape { appearance.shape = shape }
            if let tint { appearance.tint = tint }
            if let radius { appearance.radius = radius }
            if let icon { appearance.icon = icon }
        }
    }
}

/// Draws a widget's button as its appearance says: on the island the system's own glass,
/// prominent glass, bordered or plain button, in its shape and colour; on the editor's canvas and
/// in pictures a drawing of the same (no glass is kept there); in a custom layout's rectangle,
/// filling it (`FilledButtonStyle`).
struct WidgetButtonStyle: PrimitiveButtonStyle {
    @Environment(\.widgetButtonAppearance) private var appearance
    @Environment(\.widgetRenderMode) private var renderMode
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.elementFill) private var fill

    func makeBody(configuration: Configuration) -> some View {
        let look = appearance.look ?? .glass
        let shape = appearance.shape ?? .capsule
        // The icon's colour on the label itself: nearer than any style's own.
        let button = Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.modifier(OptionalIconColor(color: appearance.icon))
        }
        Group {
            if let fill {
                button.buttonStyle(FilledButtonStyle(size: fill, face: FilledButtonStyle.Face(look), shape: shape, tint: appearance.tint,
                                                     radius: appearance.radius))
            } else if renderMode == .canvas || look == .solid {
                // A solid face is drawn, never glass: the same on the island as on the canvas.
                button.buttonStyle(GlassButtonPicture(look: look, shape: shape, fill: appearance.tint, radius: appearance.radius))
            } else if isPreview {
                // A picture (the gallery): each glass there would keep its own backdrop buffers
                // (~130 MB for sixteen widgets): the system's bordered buttons, but a coloured glass.
                switch look {
                case .plain: button.buttonStyle(.plain)
                case .bordered: button.buttonStyle(.bordered).modifier(OptionalTint(color: appearance.tint))
                case .prominent, .solid: button.buttonStyle(.borderedProminent).modifier(OptionalTint(color: appearance.tint))
                case .glass:
                    if let tint = appearance.tint {
                        button.buttonStyle(.glass(Glass.regular.tint(tint).interactive()))
                    } else {
                        button.buttonStyle(.bordered)
                    }
                }
            } else {
                switch look {
                case .plain: button.buttonStyle(.plain)
                case .bordered: button.buttonStyle(.bordered).modifier(OptionalTint(color: appearance.tint))
                case .prominent, .solid: button.buttonStyle(.glassProminent).modifier(OptionalTint(color: appearance.tint))
                case .glass:
                    // The glass as it is made: a new colour is a new button (a glass already drawn
                    // keeps its tint).
                    button.buttonStyle(.glass(Glass.regular.tint(appearance.tint).interactive())).id(appearance.tint)
                }
            }
        }
        .buttonBorderShape(appearance.borderShape)
    }
}

/// The icon's colour where one is set.
private struct OptionalIconColor: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color { content.foregroundStyle(color) } else { content }
    }
}

extension FilledButtonStyle.Face {
    init(_ look: ButtonLookChoice) {
        switch look {
        case .glass: self = .glass
        case .prominent: self = .prominent
        case .solid: self = .solid
        case .plain: self = .plain
        case .bordered: self = .bordered
        }
    }
}
