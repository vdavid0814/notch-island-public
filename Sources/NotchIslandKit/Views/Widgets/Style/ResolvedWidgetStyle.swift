import Synchronization
import SwiftUI

/// A widget's style as its elements draw it: read from `\.widgetStyle` once by each element's view
/// and handed to `.widgetText`, `.widgetSymbol`, `.widgetImage`, `.widgetButton` and `ResolvedLine`.
///
/// Only what changes pixels is kept (not the behaviour), and elements whose style is empty are left
/// out, so two styles that draw alike compare equal and an edit that draws nothing new re-renders
/// nothing. `IslandWidgetView` resolves it once per body evaluation; resolving is memoised.
nonisolated struct ResolvedWidgetStyle: Equatable, Sendable {
    var elements: [ElementID: ElementStyle]
    var surface: SurfaceStyle
    var layout: LayoutStyle
    var format: FormatStyle

    static let empty = ResolvedWidgetStyle(WidgetStyle())

    init(_ style: WidgetStyle) {
        elements = style.elements.filter { $0.value != ElementStyle() }
        surface = style.surface
        layout = style.layout
        format = style.format
    }

    /// The element's style; nil when it has none, so it draws exactly as the kind draws it.
    func element(_ id: ElementID) -> ElementStyle? { elements[id] }

    /// Some colour follows the playing track's cover: only then does the widget read it.
    var usesArtwork: Bool {
        surface.fill == .artwork || surface.fillEnd == .artwork || surface.border == .artwork
            || elements.values.contains { $0.colors.values.contains(.artwork) }
    }

    /// The same style resolved before, while it is among the last 256 (an empty style is never
    /// looked up).
    static func resolve(_ style: WidgetStyle) -> ResolvedWidgetStyle {
        if style.isEmpty { return .empty }
        if let resolved = cache.withLock({ $0[style] }) { return resolved }
        let resolved = ResolvedWidgetStyle(style)
        cache.withLock { $0[style] = resolved }
        return resolved
    }

    private static let cache = Mutex(MeasureCache<WidgetStyle, ResolvedWidgetStyle>())
}

/// A widget's corners and its padding: what an element in a corner is concentric with.
nonisolated struct WidgetCorners: Equatable, Sendable {
    var outer: RectangleCornerRadii
    var padding: CGFloat

    /// The corners of what fills the padded content (the cover in Cover).
    var inner: RectangleCornerRadii { ConcentricGeometry.inner(outer, inset: padding) }

    static let standard = WidgetCorners(outer: .uniform(WidgetMetrics.cornerRadius), padding: WidgetMetrics.padding)
}

/// Where the widgets are drawn on the panel's board: its grid, and its bottom corners' radius
/// (`ConcentricGeometry.boardCornerRadius`), so a widget in a bottom corner is concentric with the
/// panel. Without it (a picture in Settings) every corner is the standard one.
nonisolated struct WidgetBoardShape: Equatable, Sendable {
    var grid: BoardGrid
    var cornerRadius: CGFloat
}

extension EnvironmentValues {
    @Entry var widgetStyle = ResolvedWidgetStyle.empty
    @Entry var widgetCorners = WidgetCorners.standard
    @Entry var widgetBoard: WidgetBoardShape?
    /// The cover's colour, given only to a widget whose style uses it (`usesArtwork`).
    @Entry var widgetArtworkColor: Color?
}

nonisolated extension RectangleCornerRadii {
    static func uniform(_ radius: CGFloat) -> RectangleCornerRadii {
        RectangleCornerRadii(topLeading: radius, bottomLeading: radius, bottomTrailing: radius, topTrailing: radius)
    }

    /// The one radius of all four corners, if they share one.
    var uniformRadius: CGFloat? {
        topLeading == bottomLeading && topLeading == bottomTrailing && topLeading == topTrailing ? topLeading : nil
    }
}

extension View {
    /// Clipped to corners that may differ (a widget in the panel's bottom corner); the plain
    /// rounded rectangle when all four are one.
    @ViewBuilder func clipShape(corners radii: RectangleCornerRadii) -> some View {
        if let radius = radii.uniformRadius {
            clipShape(.rect(cornerRadius: radius, style: .continuous))
        } else {
            clipShape(UnevenRoundedRectangle(cornerRadii: radii, style: .continuous))
        }
    }
}

extension StyleColor {
    /// What an element is painted with; nil for `automatic` (the kind's own colour).
    func shapeStyle(artwork: Color?) -> AnyShapeStyle? {
        switch self {
        case .accent: AnyShapeStyle(.tint)
        case .semantic(let semantic): semantic.shapeStyle
        default: color(artwork: artwork).map(AnyShapeStyle.init)
        }
    }

    /// As a colour (a gradient's stop, a button's tint); nil for `automatic`, and for `accent`,
    /// which is the tint already there. `value` is the reading a value scale colours by (0…1).
    func color(artwork: Color?, value: Double? = nil) -> Color? {
        switch self {
        case .automatic, .accent: nil
        case .theme: .islandAccent
        // Nothing playing (or a cover without a colour): the theme's, so the choice still shows.
        case .artwork: artwork ?? .islandAccent
        case .semantic(let semantic): semantic.color
        case .named(let tint): tint.color
        case .rgb(let rgb, let alpha): Color(red: rgb.red, green: rgb.green, blue: rgb.blue).opacity(alpha)
        case .valueScale(let scale): value.map(scale.color)
        }
    }
}

extension SemanticColor {
    var color: Color {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        case .tertiary: Color(nsColor: .tertiaryLabelColor)
        case .positive: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    /// The hierarchical styles for the three levels of text, so they follow the scheme as text does.
    var shapeStyle: AnyShapeStyle {
        switch self {
        case .primary: AnyShapeStyle(.primary)
        case .secondary: AnyShapeStyle(.secondary)
        case .tertiary: AnyShapeStyle(.tertiary)
        case .positive: AnyShapeStyle(.green)
        case .warning: AnyShapeStyle(.yellow)
        case .critical: AnyShapeStyle(.red)
        }
    }
}

extension ValueScale {
    /// A charge red below 20 %, as the battery reads; a load as the Mac's readings colour it.
    func color(_ value: Double) -> Color {
        switch self {
        case .rising: value < 0.2 ? .red : value < 0.4 ? .yellow : .green
        case .falling: value < 0.6 ? .green : value < 0.85 ? .yellow : .red
        }
    }
}
