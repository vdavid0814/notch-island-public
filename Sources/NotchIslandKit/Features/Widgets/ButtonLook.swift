import CoreGraphics
import Foundation

/// How a button of a widget (Now Playing's play, previous and next) is drawn, from Customize: what
/// it is made of, its shape and corners, what fills it, and its symbol inside — how large, where,
/// with what edges and in what colour. Every field left at its default is the button as the widget
/// draws it on its own: the symbol alone.
nonisolated struct ButtonLook: Sendable, Codable, Hashable {
    var material: Material = .regular
    var shape: Shape = .circle
    var corners: Corners = .round
    var fill: Fill = .plate
    /// The Colour fill's colour; nil: the theme's.
    var fillColor: IslandTheme.RGB?
    /// The shape's size, as a share of its own (1: about as large as the symbol alone was).
    var size: Double = 1
    /// The symbol's size, as a share of its own (1: as the widget sets it).
    var iconScale: Double = 1
    /// How far the symbol is from the button's middle, as a share of the button's width and height.
    var iconOffset: ElementOffset = .zero
    var iconEdges: IconEdges = .rounded
    var iconFill: IconFill = .automatic
    /// The Colour symbol's colour; nil: the theme's.
    var iconColor: IslandTheme.RGB?

    static let plain = ButtonLook()

    /// Drawn on Liquid Glass: a shape of glass with a fill.
    static func isGlass(_ look: ButtonLook) -> Bool {
        look.material == .glass && look.fill != .none
    }

    init() {}

    static let iconScales = 0.4...2.0

    /// How large its symbol may be: up to twice its own size, and on a shape made larger, as much
    /// larger again (a button at 180 %, its symbol up to 360 %), so a large button can be filled.
    var iconScaleRange: ClosedRange<Double> {
        Self.iconScales.lowerBound...(Self.iconScales.upperBound * (material.hasShape ? max(1, size) : 1))
    }
    static let sizes = 0.5...3.0
    /// The symbol stays this far inside the button's edges at most (a share of its size).
    static let iconOffsets = -0.5...0.5

    /// What the button is made of.
    nonisolated enum Material: String, Sendable, Codable, CaseIterable, Identifiable {
        /// The symbol alone, as the widget draws it.
        case regular
        /// An opaque shape behind the symbol.
        case solid
        /// Liquid Glass behind the symbol, tinted by the fill.
        case glass

        var id: String { rawValue }

        var title: String {
            switch self {
            case .regular: "Regular"
            case .solid: "Solid"
            case .glass: "Glass"
            }
        }

        /// It has a shape of its own to set.
        var hasShape: Bool { self != .regular }
    }

    nonisolated enum Shape: String, Sendable, Codable, CaseIterable, Identifiable {
        /// As tall as it is wide: a circle, or with corners a square.
        case circle
        /// Wider than tall: a capsule, or with corners a rectangle.
        case capsule

        var id: String { rawValue }

        var title: String {
            switch self {
            case .circle: "Circle"
            case .capsule: "Capsule"
            }
        }
    }

    nonisolated enum Corners: String, Sendable, Codable, CaseIterable, Identifiable {
        case sharp, rounded, round

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sharp: "Sharp"
            case .rounded: "Rounded"
            case .round: "Round"
            }
        }

        /// The corner radius of a button `height` tall.
        func radius(height: CGFloat) -> CGFloat {
            switch self {
            case .sharp: 0
            case .rounded: height * 0.24
            case .round: height / 2
            }
        }
    }

    nonisolated enum Fill: String, Sendable, Codable, CaseIterable, Identifiable {
        /// The widget's own plate: light, see-through.
        case plate
        case colour
        /// Nothing but a faint grey edge.
        case none
        /// The cover's colour while something plays.
        case artwork

        var id: String { rawValue }

        var title: String {
            switch self {
            case .plate: "Plate"
            case .colour: "Colour"
            case .none: "None"
            // Short: four in the inspector's width.
            case .artwork: "Cover"
            }
        }
    }

    nonisolated enum IconEdges: String, Sendable, Codable, CaseIterable, Identifiable {
        case rounded, sharp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rounded: "Rounded"
            case .sharp: "Sharp"
            }
        }
    }

    nonisolated enum IconFill: String, Sendable, Codable, CaseIterable, Identifiable {
        /// The widget's own: white.
        case automatic
        case colour
        /// Its outline alone, a faint grey line.
        case none
        case artwork

        var id: String { rawValue }

        var title: String {
            switch self {
            // Short: four in the inspector's width.
            case .automatic: "Auto"
            case .colour: "Colour"
            case .none: "None"
            case .artwork: "Cover"
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case material, shape, corners, fill, fillColor, size, iconScale, iconOffset, iconEdges, iconFill, iconColor
    }

    // Every field may be missing or unknown (stored before it existed, or by a later version): its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        material = (try? container.decodeIfPresent(Material.self, forKey: .material)) ?? .regular
        shape = (try? container.decodeIfPresent(Shape.self, forKey: .shape)) ?? .circle
        corners = (try? container.decodeIfPresent(Corners.self, forKey: .corners)) ?? .round
        fill = (try? container.decodeIfPresent(Fill.self, forKey: .fill)) ?? .plate
        fillColor = (try? container.decodeIfPresent(IslandTheme.RGB.self, forKey: .fillColor)).flatMap { $0 }
        size = (try? container.decodeIfPresent(Double.self, forKey: .size)).flatMap { $0 } ?? 1
        iconScale = (try? container.decodeIfPresent(Double.self, forKey: .iconScale)).flatMap { $0 } ?? 1
        iconOffset = (try? container.decodeIfPresent(ElementOffset.self, forKey: .iconOffset)).flatMap { $0 } ?? .zero
        iconEdges = (try? container.decodeIfPresent(IconEdges.self, forKey: .iconEdges)) ?? .rounded
        iconFill = (try? container.decodeIfPresent(IconFill.self, forKey: .iconFill)) ?? .automatic
        iconColor = (try? container.decodeIfPresent(IslandTheme.RGB.self, forKey: .iconColor)).flatMap { $0 }
    }

    /// Kept within what Customize offers.
    mutating func sanitize() {
        size = size.isFinite ? min(max(size, Self.sizes.lowerBound), Self.sizes.upperBound) : 1
        let scales = iconScaleRange
        iconScale = iconScale.isFinite ? min(max(iconScale, scales.lowerBound), scales.upperBound) : 1
        let range = Self.iconOffsets
        iconOffset = iconOffset.isFinite
            ? ElementOffset(x: min(max(iconOffset.x, range.lowerBound), range.upperBound),
                            y: min(max(iconOffset.y, range.lowerBound), range.upperBound))
            : .zero
    }
}
