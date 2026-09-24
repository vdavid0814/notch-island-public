import SwiftUI

/// The island's one Liquid Glass material — the same glass the CAD app wears.
///
/// Taken verbatim from the CAD app (`CadGlassRole.material`, `NavyGlassButtonStyle`,
/// `CadLiquidSegment.thumb`) so the two apps read as one family: a smoked, perfectly
/// clear glass that refracts what is behind it instead of frosting it. Every island
/// surface uses exactly these values, so there is one place to change them.
///
/// Like the CAD app's floating UI, the island's window is pinned to the dark
/// appearance (`IslandPanel`), because Liquid Glass samples the window's appearance
/// and a smoked glass needs light content on top of it.
enum IslandGlass {
    /// What a piece of glass is for. The material itself comes from the user's `IslandGlassStyle`,
    /// resolved where the glass is drawn (`islandGlass(_:in:)`), so call sites name a role only.
    nonisolated enum Role: Sendable {
        case surface, control, active, thumb
    }

    /// The glass every surface wears.
    static let surface = Role.surface

    /// Glass under a tappable control: the same material, responding to the pointer.
    static let control = Role.control

    /// An active, selected or primary control, tinted with the system accent colour.
    static let active = Role.active

    /// A moving selection thumb: fully clear, so the label under it stays sharp.
    static let thumb = Role.thumb

    /// The material for a role in a style. Only the surface (and the control, which is the surface
    /// responding to the pointer) follows the style; the accent and the thumb keep their own glass.
    static func material(_ role: Role, style: IslandGlassStyle) -> Glass {
        switch role {
        case .surface: style.material
        case .control: style.controlMaterial.interactive()
        case .active: Glass.clear.tint(Color.accentColor.opacity(0.62)).interactive()
        case .thumb: Glass.clear.interactive()
        }
    }

    /// The CAD app's press response (`CadMotion.press`): immediate and heavily damped, because a
    /// press must never wobble.
    static let press: Animation = .spring(response: 0.11, dampingFraction: 0.86)

    /// The selection thumb gliding to its segment: slower than a press so the backdrop can be seen
    /// flowing through the moving glass, damped enough to settle in one movement.
    static let glide: Animation = .spring(response: 0.3, dampingFraction: 0.8)
}

/// The user's choice of island surface (Settings ▸ General ▸ Surface).
///
/// The glass itself is not a choice: the CAD app's smoked Liquid Glass follows the system (with the
/// panel's active-appearance override) and is always the one used. The choice is how much black the
/// island wears over it.
nonisolated enum IslandGlassStyle: String, Sendable, CaseIterable, Identifiable, Codable {
    /// The CAD app's smoked Liquid Glass (the default). Raw value kept from the old "Smoked" choice.
    case liquidGlass = "smoked"
    /// Solid black, like the hardware island: no glass under it at all.
    case black
    /// Black where the island hugs the notch, fading into the glass below it. A pill that only
    /// reaches the notch's height is therefore entirely black; a panel shows glass towards its bottom.
    case fade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .black: "Black"
        case .fade: "Fade"
        }
    }

    /// Stored values from before the choice was narrowed map to the glass.
    init(storedValue: String?) {
        self = storedValue.flatMap(IslandGlassStyle.init(rawValue:)) ?? .liquidGlass
    }

    /// Whether the island's surface is glass at all.
    var hasGlassSurface: Bool { self != .black }

    /// How far beyond the island's outline its glass is drawn before being clipped to the outline.
    /// That puts the bright rim light the glass draws on its edge (over everything, so nothing can
    /// be laid over it) outside the island, where the clip removes it — without shrinking the
    /// island, which must stay exactly the notch's size. The rim reads as a white outline around a
    /// dark island.
    var rimInset: CGFloat {
        switch self {
        case .liquidGlass: 1.5
        // Fade is meant to read as a black island: no outline at all, also where it turns to glass.
        case .fade: 3
        case .black: 0
        }
    }

    /// The island's smoked glass: a little darker than the CAD app's (0.5), so the surface stays
    /// closer to the black of the notch it hangs from while still showing what is behind it.
    var material: Glass { .clear.tint(Color.black.opacity(0.62)) }

    /// Glass under controls: the CAD app's smoke, so buttons read a shade lighter than the surface.
    var controlMaterial: Glass { .clear.tint(Color.black.opacity(0.5)) }
}

extension EnvironmentValues {
    /// Set once at the island's root from `Preferences.glassStyle`.
    @Entry var islandGlassStyle: IslandGlassStyle = .liquidGlass
}

extension View {
    /// Puts the view on the island's glass, in the material the user chose for that role.
    /// `isEnabled: false` keeps the view where it is but draws (and samples) no glass.
    func islandGlass(_ role: IslandGlass.Role = .surface, in shape: some Shape, isEnabled: Bool = true) -> some View {
        modifier(IslandGlassModifier(role: role, shape: shape, isEnabled: isEnabled))
    }
}

private struct IslandGlassModifier<S: Shape>: ViewModifier {
    let role: IslandGlass.Role
    let shape: S
    var isEnabled = true

    @Environment(\.islandGlassStyle) private var style

    func body(content: Content) -> some View {
        // One structure for every style: switching the style must never change the content's
        // identity. A branch here rebuilt everything on the island — with Settings open, SwiftUI's
        // key-view loop over the rebuilt form never terminated and the app hung at 100% CPU.
        // Solid black draws no glass (`.identity`, nothing sampled) and a black fill instead.
        let isSolid = role == .surface && !style.hasGlassSurface
        content
            .background(Color.black.opacity(isSolid ? 1 : 0), in: shape)
            .glassEffect(isEnabled && !isSolid ? IslandGlass.material(role, style: style) : .identity, in: shape)
    }
}

private extension View {
    /// Share of the island below the notch band that stays solid black in the fade style.
    static var fadeHold: CGFloat { 0.18 }
}

extension View {
    /// The black the island's surface wears over its glass in the `fade` style: opaque down to
    /// `solidDepth` (the notch band, plus the overdraw above the screen), then easing out to clear
    /// towards the bottom. Sized from the surface itself, so it follows the island while it grows.
    func islandSurfaceShade(_ style: IslandGlassStyle, solidDepth: CGFloat, in shape: some Shape) -> some View {
        background {
            if style == .fade {
                GeometryReader { proxy in
                    let height = max(proxy.size.height, 1)
                    // A little below the notch band before the fade starts, so the black reads as
                    // hanging from the notch rather than ending exactly at its edge.
                    let solid = min((solidDepth + (height - solidDepth) * Self.fadeHold) / height, 1)
                    let clear = solid + (1 - solid) * 0.85
                    shape.fill(Color.black).mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: solid),
                                .init(color: .black.opacity(0.7), location: solid + (clear - solid) * 0.3),
                                .init(color: .black.opacity(0.25), location: solid + (clear - solid) * 0.7),
                                .init(color: .clear, location: clear),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            }
        }
    }
}
