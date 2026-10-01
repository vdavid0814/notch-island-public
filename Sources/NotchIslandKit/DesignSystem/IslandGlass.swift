import SwiftUI

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
    var material: Glass { self == .fade ? .clear.tint(Self.fadeTint) : .clear.tint(Color.black.opacity(Self.smokeOpacity)) }

    /// A trace of colour in the fade style's otherwise clear glass: the dark warm brown in the
    /// folds of the macOS 27 light wallpaper (its darkest browns averaged), at 25 %.
    static let fadeTint = Color(red: 106 / 255, green: 89 / 255, blue: 75 / 255).opacity(0.25)

    /// The black of the surface glass's tint.
    static let smokeOpacity = 0.62
    /// How far the fade style's black reaches past the island's outline (clipped by it). The glass's
    /// edge light sits right on the outline (`rimInset` 0); a black ending on the same edge left its
    /// anti-aliased edge pixels half-covered, and the light showed through as a line around the
    /// compact pill.
    static let shadeBleed: CGFloat = 2
}

extension EnvironmentValues {
    /// Set once at the island's root from `Preferences.glassStyle`.
    @Entry var islandGlassStyle: IslandGlassStyle = .liquidGlass
}

extension View {
    /// Puts the view on the island's glass, in the style the user chose (`IslandGlassStyle.material`):
    /// the CAD app's smoked, perfectly clear glass, which refracts what is behind it instead of
    /// frosting it. Like the CAD app's floating UI, the island's window is pinned to the dark
    /// appearance (`IslandPanel`): Liquid Glass samples the window's appearance, and a smoked glass
    /// needs light content on top of it. `isEnabled: false` keeps the view where it is but draws
    /// (and samples) no glass.
    func islandGlass(in shape: some Shape, isEnabled: Bool = true) -> some View {
        modifier(IslandGlassModifier(shape: shape, isEnabled: isEnabled))
    }
}

private struct IslandGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    var isEnabled = true

    @Environment(\.islandGlassStyle) private var style

    func body(content: Content) -> some View {
        // One structure for every style: switching the style must never change the content's
        // identity. A branch here rebuilt everything on the island — with Settings open, SwiftUI's
        // key-view loop over the rebuilt form never terminated and the app hung at 100% CPU.
        // Solid black draws no glass (`.identity`, nothing sampled) and a black fill instead.
        let isSolid = !style.hasGlassSurface
        content
            .background(Color.black.opacity(isSolid ? 1 : 0), in: shape)
            .glassEffect(isEnabled && !isSolid ? style.material : .identity, in: shape)
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
    ///
    /// `isSettled`: the surface is at its own size, not being sized frame by frame by a SwiftUI
    /// animation. The black is then drawn once into a picture of its own: as layers, its soft sides
    /// are a live blur filter the window server runs again in every frame the island moves or
    /// anything on it changes (~0.08 J per open and close, measured; the same pixels within 4/255).
    /// A surface SwiftUI sizes frame by frame keeps the layers: as a picture it would be drawn again
    /// on the CPU in every frame.
    func islandSurfaceShade(_ style: IslandGlassStyle, solidDepth: CGFloat, size: CGSize, fadeStretch: CGFloat = 1,
                            isSettled: Bool = false, in shape: some Shape) -> some View {
        background {
            if style == .fade {
                shape.fill(Color.black).mask(alignment: .top) {
                    if isSettled {
                        FadeShadeMask(solidDepth: solidDepth, size: size, stretch: fadeStretch)
                            .drawingGroup()
                    } else {
                        FadeShadeMask(solidDepth: solidDepth, size: size, stretch: fadeStretch)
                    }
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

/// Where the fade style's black starts to clear down the island's middle, and where it ends, in
/// points from the top of the shade (which starts `IslandLayout.overdraw` above the screen).
nonisolated enum IslandFade {
    static func span(solidDepth: CGFloat, height: CGFloat, stretch: CGFloat = 1) -> (start: CGFloat, end: CGFloat) {
        let height = max(height, 1)
        let below = max(height - solidDepth, 0)
        let ramp = below * (1 - FadeShadeMask.hold) * FadeShadeMask.reach
        let end = solidDepth + below * FadeShadeMask.hold + ramp
        let start = min(max(end - ramp * FadeShadeMask.rampStretch * stretch, solidDepth), height)
        return (start, end)
    }

    /// The covering volume banner's fade runs longer and starts earlier (asked for, v0.4.7): a fifth,
    /// then more again on the lower banner.
    static let coveringStretch: CGFloat = 1.45
}

/// Where the fade style's black lies over an island of `size`: solid down to `solidDepth` (the
/// notch band, plus the overdraw above the screen) across the whole width; below it solid down the
/// middle through about two thirds of the rest, easing slowly out towards the bottom (never quite
/// clear there, `floor`); and clearing along the island's sides, narrowing in a mild V, and along
/// its bottom (`FadeCore`, softened) — like the iPhone's Siri.
private struct FadeShadeMask: View {
    let solidDepth: CGFloat
    let size: CGSize
    /// The fade to clear runs this much longer, starting earlier and ending where it did.
    var stretch: CGFloat = 1

    /// Share of the island below the notch band that stays solid black down its middle. The fade
    /// starts there and runs the remaining 35.552% (a tenth and a hundredth longer than the earlier
    /// 32%), times `reach`.
    static let hold: CGFloat = 0.64448

    /// How far the fade runs past the island's bottom, as a share of its length: 1.02 starts it
    /// where it did but ends it 2% lower, so the bottom edge keeps a little more black and the
    /// ramp is 2% longer (the stops are cut at the edge, `verticalStops`).
    static let reach: CGFloat = 1.02

    /// How far in from the island's edge the black is whole.
    static let edge: CGFloat = 12

    /// The fade to clear down the middle runs this much longer than `hold` and `reach` alone make
    /// it, starting earlier and ending where it did.
    static let rampStretch: CGFloat = 1.05

    /// The same along the sides: the blur that softens them is this much wider, and their black
    /// sits in by the difference, so the fade starts further in and ends where it did.
    static let sideStretch: CGFloat = 1.02

    /// The sides' black (and with it their fade to clear) sits this share of the island's width
    /// further in on each side than `edge` alone would put it.
    static let sideShift: CGFloat = 0.01

    var body: some View {
        let width = max(size.width, 1), height = max(size.height, 1)
        LinearGradient(stops: Self.verticalStops(solidDepth: solidDepth, height: height, stretch: stretch),
                       startPoint: .top, endPoint: .bottom)
            .mask {
                ZStack(alignment: .top) {
                    // One shape, blurred as one: no step anywhere along its sides.
                    let blur = Self.edge * 1.3 * Self.sideStretch
                    FadeCore(depth: solidDepth, inset: Self.edge,
                             bottomInset: Self.edge * 0.9 + width * Self.sideShift + (blur - Self.edge * 1.3),
                             cornerRadius: Self.edge * 1.5)
                    .blur(radius: blur)
                    // The notch band stays whole black, edge to edge and down to its bottom: the blur
                    // alone softened the band's lower edge and ends, so the compact pill — which is
                    // only the band — showed its glass and rim light while that glass was still
                    // held after a close (`IslandRootView.glassRetirement`). Below the band the
                    // core is black as well, so the open island looks the same.
                    Rectangle()
                        .frame(width: width + 2 * IslandGlassStyle.shadeBleed,
                               height: min(solidDepth, height) + IslandGlassStyle.shadeBleed)
                }
            }
        .frame(width: width, height: height, alignment: .top)
    }

    /// How much black stays at the bottom in the middle, under the content: enough for white text
    /// over a white page. Only the edges clear completely, where the glass shows its edge light.
    static let floor: Double = 0.5

    static func verticalStops(solidDepth: CGFloat, height: CGFloat, stretch: CGFloat = 1) -> [Gradient.Stop] {
        let (start, end) = IslandFade.span(solidDepth: solidDepth, height: height, stretch: stretch)
        return smoothFade(from: start / height, to: end / height, floor: floor)
    }

    /// Opaque black up to `start`, easing out (smoothstep, in twelve steps so none shows) to
    /// `floor` (clear by default) at `end`. An `end` past 1 is cut at the bottom edge: the last
    /// stop is the ramp's value there (a gradient's stops must lie within 0…1).
    private static func smoothFade(from start: CGFloat, to end: CGFloat, floor: Double = 0) -> [Gradient.Stop] {
        func opacity(_ t: CGFloat) -> Double {
            let t = min(max(t, 0), 1)
            return 1 - Double(t * t * (3 - 2 * t)) * (1 - floor)
        }
        let span = max(end - start, 0.0001)
        var stops = [Gradient.Stop(color: .black, location: 0)]
        for index in 0...12 {
            let t = CGFloat(index) / 12
            let location = start + span * t
            guard location < 1 else { break }
            stops.append(Gradient.Stop(color: .black.opacity(opacity(t)), location: location))
        }
        stops.append(Gradient.Stop(color: .black.opacity(opacity((1 - start) / span)), location: 1))
        return stops
    }
}
