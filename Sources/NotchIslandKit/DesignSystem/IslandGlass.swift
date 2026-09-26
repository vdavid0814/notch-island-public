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
        // Fade shows its glass's own edge light where the black has cleared, like the iPhone's Siri
        // (the black keeps it out of sight around the notch).
        case .fade: 0
        case .black: 0
        }
    }

    /// The island's glass. Liquid Glass is smoked, a little darker than the CAD app's (0.5), so the
    /// surface stays closer to the black of the notch it hangs from while still showing what is
    /// behind it; under the fade's black it is perfectly clear, colourless glass.
    var material: Glass { self == .fade ? .clear : .clear.tint(Color.black.opacity(Self.smokeOpacity)) }

    /// The black of the surface glass's tint.
    static let smokeOpacity = 0.62

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

extension View {
    /// The black the island's surface wears over its glass in the `fade` style: opaque down to about
    /// two thirds of the island, then easing slowly out, and clearing towards the sides in a mild V
    /// and along the bottom (`FadeShadeMask`). Sized from the
    /// surface itself, so it follows the island while it grows.
    func islandSurfaceShade(_ style: IslandGlassStyle, solidDepth: CGFloat, in shape: some Shape) -> some View {
        background {
            if style == .fade {
                GeometryReader { proxy in
                    shape.fill(Color.black).mask {
                        FadeShadeMask(solidDepth: solidDepth, size: proxy.size)
                    }
                }
            }
        }
    }

    /// The same shade over the top `size.height` points of a larger canvas (the island's window),
    /// centred on it: the island's surface is `size` this frame, the canvas keeps its size (see
    /// `IslandRootView`).
    func islandSurfaceShade(_ style: IslandGlassStyle, solidDepth: CGFloat, size: CGSize, in shape: some Shape) -> some View {
        background {
            if style == .fade {
                shape.fill(Color.black).mask(alignment: .top) {
                    FadeShadeMask(solidDepth: solidDepth, size: size)
                }
            }
        }
    }
}

/// The fade's black as one shape: out past the sides through the notch band, then narrowing in a
/// mild V — straight sides leaning in from the band's corners to `bottomInset` from each side at
/// `inset` above the bottom — with its lower corners rounded like the island's.
nonisolated private struct FadeCore: Shape {
    let depth: CGFloat
    let inset: CGFloat
    let bottomInset: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let out = 2 * inset, top = rect.minY - 200, bend = rect.minY + depth
        let bottom = max(rect.maxY - inset, bend + 1)
        let left = rect.minX + bottomInset, right = rect.maxX - bottomInset
        let r = max(0, min(cornerRadius, (right - left) / 2, bottom - bend))
        // Where the leaning sides meet the rounded corners: `r` up each side.
        func side(_ fromX: CGFloat, _ toX: CGFloat) -> CGFloat { toX + (fromX - toX) * r / (bottom - bend) }
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - out, y: top))
        path.addLine(to: CGPoint(x: rect.maxX + out, y: top))
        path.addLine(to: CGPoint(x: rect.maxX + out, y: bend))
        path.addLine(to: CGPoint(x: side(rect.maxX + out, right), y: bottom - r))
        path.addQuadCurve(to: CGPoint(x: right - r, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left + r, y: bottom))
        path.addQuadCurve(to: CGPoint(x: side(rect.minX - out, left), y: bottom - r), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: rect.minX - out, y: bend))
        path.closeSubpath()
        return path
    }
}

/// Where the fade style's black lies over an island of `size`: solid down to `solidDepth` (the
/// notch band, plus the overdraw above the screen) across the whole width; below it solid down the
/// middle through about two thirds of the rest, easing slowly out towards the bottom (never quite
/// clear there, `floor`); and clearing along the island's sides, narrowing in a mild V, and along
/// its bottom (`FadeCore`, softened) — like the iPhone's Siri.
private struct FadeShadeMask: View {
    let solidDepth: CGFloat
    let size: CGSize

    /// Share of the island below the notch band that stays solid black down its middle.
    static let hold: CGFloat = 0.68

    /// How far in from the island's edge the black is whole.
    static let edge: CGFloat = 12

    var body: some View {
        let width = max(size.width, 1), height = max(size.height, 1)
        LinearGradient(stops: Self.verticalStops(solidDepth: solidDepth, height: height),
                       startPoint: .top, endPoint: .bottom)
            .mask {
                // One shape, blurred as one: no step anywhere along its sides.
                FadeCore(depth: solidDepth, inset: Self.edge, bottomInset: Self.edge * 0.9,
                         cornerRadius: Self.edge * 1.5)
                .blur(radius: Self.edge * 1.3)
            }
        .frame(width: width, height: height, alignment: .top)
    }

    /// How much black stays at the bottom in the middle, under the content: enough for white text
    /// over a white page. Only the edges clear completely, where the glass shows its edge light.
    static let floor: Double = 0.5

    static func verticalStops(solidDepth: CGFloat, height: CGFloat) -> [Gradient.Stop] {
        let solid = min((solidDepth + max(height - solidDepth, 0) * hold) / height, 1)
        return smoothFade(from: solid, to: 1, floor: floor)
    }

    /// Opaque black up to `start`, easing out (smoothstep, in twelve steps so none shows) to
    /// `floor` (clear by default) at `end`.
    private static func smoothFade(from start: CGFloat, to end: CGFloat, floor: Double = 0) -> [Gradient.Stop] {
        [Gradient.Stop(color: .black, location: 0)] + (0...12).map { index in
            let t = CGFloat(index) / 12
            let eased = Double(t * t * (3 - 2 * t))
            return Gradient.Stop(color: .black.opacity(1 - eased * (1 - floor)), location: start + (end - start) * t)
        }
    }
}
