import Foundation

/// What is behind a part, as Customize sets it the way a button's shape is (`ButtonLook`): nothing
/// (Regular), an opaque shape (Solid) or Liquid Glass, with its corners and its fill.
nonisolated struct SurfaceLook: Sendable, Codable, Hashable {
    var material: ButtonLook.Material = .regular
    var corners: ButtonLook.Corners = .rounded
    var fill: ButtonLook.Fill = .plate
    /// The Colour fill's colour; nil: the theme's.
    var fillColor: IslandTheme.RGB?

    static let none = SurfaceLook()

    /// Something is drawn behind the part.
    var isShown: Bool { material.hasShape }

    /// Drawn on Liquid Glass (`SharpZoom` draws it under the picture of the rest).
    var isGlass: Bool { material == .glass && fill != .none }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case material, corners, fill, fillColor
    }

    // Every field may be missing or unknown (stored before it existed, or by a later version): its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        material = (try? container.decodeIfPresent(ButtonLook.Material.self, forKey: .material)).flatMap { $0 } ?? .regular
        corners = (try? container.decodeIfPresent(ButtonLook.Corners.self, forKey: .corners)).flatMap { $0 } ?? .rounded
        fill = (try? container.decodeIfPresent(ButtonLook.Fill.self, forKey: .fill)).flatMap { $0 } ?? .plate
        fillColor = (try? container.decodeIfPresent(IslandTheme.RGB.self, forKey: .fillColor)).flatMap { $0 }
    }
}

/// How a grid of days (the calendar's) is drawn, from Customize's inspector: a background behind
/// each day, and one behind the whole grid. The days' numbers are a text of their own
/// (`ElementID.monthDays`: their type, size and colour). At its defaults the grid as the widget
/// draws it: the numbers on nothing.
nonisolated struct DayGridLook: Sendable, Codable, Hashable {
    /// Behind each day of the month (today keeps its disc over it).
    var day = SurfaceLook()
    /// Behind the whole grid, its weekdays included.
    var grid = SurfaceLook()

    static let plain = DayGridLook()

    var isGlass: Bool { day.isGlass || grid.isGlass }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case day, grid
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? container.decodeIfPresent(SurfaceLook.self, forKey: .day)).flatMap { $0 } ?? SurfaceLook()
        grid = (try? container.decodeIfPresent(SurfaceLook.self, forKey: .grid)).flatMap { $0 } ?? SurfaceLook()
    }

    /// Nothing to keep within a range: every field is a choice.
    mutating func sanitize() {}
}
