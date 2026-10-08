import Foundation

/// How a ruler (the timer's) is drawn, from Customize's inspector: the colour of its ticks, its
/// marker and its numbers; the ticks' ends; and what is behind it — nothing (Regular), an opaque
/// shape (Solid) or Liquid Glass — with that shape's corners and fill, as a button's
/// (`ButtonLook`). Every field at its default is the ruler as the widget draws it: orange ticks
/// with round ends, on nothing.
nonisolated struct RulerLook: Sendable, Codable, Hashable {
    /// Automatic: the timer's orange.
    var color: TextStyle.TextColor = .automatic
    /// The ticks' ends: sharp, a little rounded, or round.
    var ends: ButtonLook.Corners = .round
    /// What is behind the ruler.
    var material: ButtonLook.Material = .regular
    /// The background's corners: sharp, rounded, or round (a capsule).
    var corners: ButtonLook.Corners = .rounded
    var fill: ButtonLook.Fill = .plate
    /// The Colour fill's colour; nil: the theme's.
    var fillColor: IslandTheme.RGB?
    /// How far the unit's name (`ElementID.rulerUnit`, beside the marker) is moved from where the
    /// ruler puts it, in points (in the panel under Customize's editor). Its type, colour and box
    /// are its text style.
    var unitOffset: ElementOffset = .zero

    static let plain = RulerLook()
    /// The farthest the unit's name is moved, either way.
    static let unitReach = 200.0

    /// Drawn on Liquid Glass (`SharpZoom` draws it under the picture of the rest).
    static func isGlass(_ look: RulerLook) -> Bool { look.material == .glass && look.fill != .none }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case color, ends, material, corners, fill, fillColor, unitOffset
    }

    // Every field may be missing or unknown (stored before it existed, or by a later version): its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = (try? container.decodeIfPresent(TextStyle.TextColor.self, forKey: .color)).flatMap { $0 } ?? .automatic
        ends = (try? container.decodeIfPresent(ButtonLook.Corners.self, forKey: .ends)).flatMap { $0 } ?? .round
        material = (try? container.decodeIfPresent(ButtonLook.Material.self, forKey: .material)).flatMap { $0 } ?? .regular
        corners = (try? container.decodeIfPresent(ButtonLook.Corners.self, forKey: .corners)).flatMap { $0 } ?? .rounded
        fill = (try? container.decodeIfPresent(ButtonLook.Fill.self, forKey: .fill)).flatMap { $0 } ?? .plate
        fillColor = (try? container.decodeIfPresent(IslandTheme.RGB.self, forKey: .fillColor)).flatMap { $0 }
        unitOffset = (try? container.decodeIfPresent(ElementOffset.self, forKey: .unitOffset)).flatMap { $0 } ?? .zero
    }

    /// The unit's name moved no farther than `unitReach`, and not at all where it is no number.
    mutating func sanitize() {
        let reach = Self.unitReach
        unitOffset = unitOffset.isFinite
            ? ElementOffset(x: min(max(unitOffset.x, -reach), reach).rounded(), y: min(max(unitOffset.y, -reach), reach).rounded())
            : .zero
    }
}
