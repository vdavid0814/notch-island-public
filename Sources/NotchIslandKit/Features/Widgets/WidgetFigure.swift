import CoreGraphics
import Foundation

/// A shape added to a widget in Customize (a line, a ring, an arrow…): drawn over its parts, from
/// the middle of its inside, then moved and sized in the editor like any part (`offsets`, `scales`).
nonisolated struct WidgetFigure: Sendable, Codable, Hashable, Identifiable {
    /// Its own element, "figure." and a few letters: one of its kind is told from another by it.
    var id: ElementID
    var kind: Kind
    var color: TextStyle.TextColor = .automatic
    /// A line's ends, a square's corners (`hasCorners`); nil: the kind's own (`Kind.corners`).
    var corners: Corners?
    /// A square drawn solid, not as its outline (`canFill`).
    var isFilled = false
    /// Turned about its middle, in degrees, clockwise: -180…180.
    var rotation: Double = 0

    var effectiveCorners: Corners { corners ?? kind.corners }

    init(id: ElementID, kind: Kind, color: TextStyle.TextColor = .automatic, corners: Corners? = nil, isFilled: Bool = false,
         rotation: Double = 0) {
        self.id = id
        self.kind = kind
        self.color = color
        self.corners = corners
        self.isFilled = isFilled
        self.rotation = Self.normalized(rotation)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, color, corners, isFilled, rotation
    }

    /// `degrees` within -180…180 (a whole turn more or less is the same), on tenths.
    static func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        var turned = degrees.truncatingRemainder(dividingBy: 360)
        if turned > 180 { turned -= 360 }
        if turned <= -180 { turned += 360 }
        return (turned * 10).rounded() / 10
    }

    // Saved before a field existed, or with one not understood: its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ElementID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        color = (try? container.decodeIfPresent(TextStyle.TextColor.self, forKey: .color)).flatMap { $0 } ?? .automatic
        corners = (try? container.decodeIfPresent(Corners.self, forKey: .corners)).flatMap { $0 }
        isFilled = (try? container.decodeIfPresent(Bool.self, forKey: .isFilled)).flatMap { $0 } ?? false
        rotation = Self.normalized((try? container.decodeIfPresent(Double.self, forKey: .rotation)).flatMap { $0 } ?? 0)
    }

    /// Round, a little rounded, or sharp: a line's ends, a square's corners.
    nonisolated enum Corners: String, Sendable, Codable, CaseIterable, Identifiable {
        case round, rounded, sharp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .round: String(localized: "Round")
            case .rounded: String(localized: "Rounded")
            case .sharp: String(localized: "Sharp")
            }
        }

        /// The radius for a shape `size` large: a line's from its thickness, a square's from its
        /// shorter side.
        func radius(_ size: CGSize, line: Bool) -> CGFloat {
            let short = min(size.width, size.height)
            return switch self {
            case .round: line ? short / 2 : short * 0.3
            case .rounded: line ? short * 0.22 : short * 0.18
            case .sharp: 0
            }
        }
    }

    static let prefix = "figure."
    /// At most this many on a widget.
    static let limit = 16

    /// A new one of `kind`, with an id of its own.
    static func new(_ kind: Kind) -> WidgetFigure {
        WidgetFigure(id: ElementID(rawValue: prefix + UUID().uuidString.prefix(8).lowercased()), kind: kind)
    }

    nonisolated enum Kind: String, Sendable, Codable, CaseIterable, Identifiable {
        case line, ring, disc, square, arrow, turnArrow, circleArrow, twoWayArrow

        var id: String { rawValue }

        var title: String {
            switch self {
            case .line: String(localized: "Line")
            case .ring: String(localized: "Ring")
            case .disc: String(localized: "Dot")
            case .square: String(localized: "Square")
            case .arrow: String(localized: "Arrow")
            case .turnArrow: String(localized: "Turning Arrow")
            case .circleArrow: String(localized: "Circling Arrow")
            case .twoWayArrow: String(localized: "Two-Way Arrow")
            }
        }

        /// Its picture in Customize, and for the arrows the symbol it is drawn as.
        var symbol: String {
            switch self {
            case .line: "minus"
            case .ring: "circle"
            case .disc: "circle.fill"
            case .square: "square"
            case .arrow: "arrow.right"
            case .turnArrow: "arrow.turn.up.right"
            case .circleArrow: "arrow.clockwise"
            case .twoWayArrow: "arrow.left.arrow.right"
            }
        }

        /// Whether its ends or corners can be set: a line's, a square's.
        var hasCorners: Bool { self == .line || self == .square }

        /// Whether it can be drawn solid: a square.
        var canFill: Bool { self == .square }

        /// Its ends or corners as added: a line's round, a square's a little rounded.
        var corners: Corners { self == .line ? .round : .rounded }

        /// How large it is added, in points (its layout box: resizing scales it from there).
        var size: CGSize {
            switch self {
            case .line: CGSize(width: 48, height: 3)
            case .ring, .square: CGSize(width: 28, height: 28)
            case .disc: CGSize(width: 16, height: 16)
            case .arrow: CGSize(width: 30, height: 22)
            case .turnArrow, .circleArrow: CGSize(width: 26, height: 26)
            case .twoWayArrow: CGSize(width: 32, height: 24)
            }
        }
    }
}
