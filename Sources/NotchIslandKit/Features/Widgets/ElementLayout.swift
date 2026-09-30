import CoreGraphics
import Foundation

// The grid inside a widget (Customize ▸ Custom layout): its elements placed freely, each on a
// rectangle in fractions of the widget, so a layout drawn at one size reflows to every other.
// This file is the model only — what is stored and what a stored layout may contain; placing,
// reflowing and snapping are not here.

/// How a widget's elements are arranged: the kind's own stacks, or the user's layouts.
nonisolated enum ElementArrangement: Codable, Hashable, Sendable {
    case automatic
    case custom(CustomLayouts)

    /// The decorations of every size's layout (`custom.<uuid>`).
    var decorationIDs: Set<ElementID> {
        guard case .custom(let layouts) = self else { return [] }
        return Set(layouts.variants.values.flatMap { variant -> [ElementID] in
            guard case .custom(let layout) = variant else { return [] }
            return Array(layout.decorations.keys)
        })
    }

    mutating func sanitize(for kind: IslandWidgetKind) {
        guard case .custom(var layouts) = self else { return }
        layouts.sanitize(for: kind.spec, standardPadding: WidgetMetrics.standardPadding(for: kind))
        self = .custom(layouts)
    }
}

/// The user's layouts, one per size class the widget has been laid out in.
nonisolated struct CustomLayouts: Codable, Hashable, Sendable {
    /// The size class the user laid it out in first: other classes without a variant reflow it.
    var authored: LayoutClass
    var variants: [LayoutClass: LayoutVariant]

    init(authored: LayoutClass, variants: [LayoutClass: LayoutVariant]) {
        self.authored = authored
        self.variants = variants
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        authored = try c.decode(LayoutClass.self, forKey: .authored)
        // By name, so a size class this build does not know is left out rather than every variant.
        let variants = c.lossy([String: Lossy<LayoutVariant>].self, .variants) ?? [:]
        self.variants = Dictionary(uniqueKeysWithValues: variants.compactMap { name, variant in
            LayoutClass(name: name).flatMap { size in variant.value.map { (size, $0) } }
        })
    }

    mutating func sanitize(for spec: WidgetKindSpec, standardPadding: CGFloat) {
        variants = variants.mapValues { variant in
            guard case .custom(var layout) = variant else { return variant }
            layout.sanitize(for: spec, standardPadding: standardPadding)
            return .custom(layout)
        }
    }
}

/// One size class: the kind's own stacks there, or a layout of its own.
nonisolated enum LayoutVariant: Codable, Hashable, Sendable {
    case automatic
    case custom(CustomLayout)
}

/// A widget shape's band: short, medium or tall, by narrow, balanced or wide.
nonisolated struct LayoutClass: Hashable, Sendable, Codable, CodingKeyRepresentable {
    nonisolated enum Height: String, Sendable, CaseIterable { case short, medium, tall }
    nonisolated enum Aspect: String, Sendable, CaseIterable { case narrow, balanced, wide }

    var height: Height
    var aspect: Aspect

    init(height: Height, aspect: Aspect) {
        self.height = height
        self.aspect = aspect
    }

    /// "short-wide".
    var name: String { height.rawValue + "-" + aspect.rawValue }

    init?(name: String) {
        let parts = name.split(separator: "-").map(String.init)
        guard parts.count == 2, let height = Height(rawValue: parts[0]), let aspect = Aspect(rawValue: parts[1]) else { return nil }
        self.init(height: height, aspect: aspect)
    }

    var codingKey: any CodingKey { Name(stringValue: name) }

    init?<T: CodingKey>(codingKey: T) { self.init(name: codingKey.stringValue) }

    init(from decoder: any Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let value = LayoutClass(name: name) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no size class \(name)"))
        }
        self = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }

    private struct Name: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// Elements placed on a widget of one size class.
nonisolated struct CustomLayout: Codable, Hashable, Sendable {
    /// The widget's size it was laid out at, in reference points (at the standard island size).
    var authoredSize: CGSize
    /// An editing aid only: the frames are fractions, so changing it never moves anything.
    var grid: InnerGrid
    /// Back to front.
    var items: [ElementFrame]
    /// Elements not placed — hidden, or they did not fit: the "Didn't fit" tray.
    var parked: [ElementID]
    /// What the user added: labels, symbols, dividers and shapes (`ElementID.custom`).
    var decorations: [ElementID: Decoration]
    /// The widget's padding it was laid out with, in reference points: the band the reflow maps
    /// onto the padding it is drawn with. Nil only for a layout saved before it was recorded, until
    /// `sanitize` gives it the kind's standard padding.
    var authoredPadding: CGFloat?

    init(authoredSize: CGSize, grid: InnerGrid, items: [ElementFrame], parked: [ElementID] = [],
         decorations: [ElementID: Decoration] = [:], authoredPadding: CGFloat? = nil) {
        self.authoredSize = authoredSize
        self.grid = grid
        self.items = items
        self.parked = parked
        self.decorations = decorations
        self.authoredPadding = authoredPadding
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        authoredSize = try c.decode(CGSize.self, forKey: .authoredSize)
        grid = c.lossy(InnerGrid.self, .grid) ?? InnerGrid(columns: 8, rows: 4)
        items = (c.lossy([Lossy<ElementFrame>].self, .items) ?? []).compactMap(\.value)
        parked = (c.lossy([Lossy<ElementID>].self, .parked) ?? []).compactMap(\.value)
        decorations = (c.lossy([ElementID: Lossy<Decoration>].self, .decorations) ?? [:]).compactMapValues(\.value)
        authoredPadding = c.lossy(CGFloat.self, .authoredPadding)
    }

    /// Keeps what the kind can show: each id once (the first, the one drawn furthest back), only
    /// the kind's elements and their parts or a decoration of this layout; rectangles inside the
    /// widget and no smaller than the minimum; every element of the kind either placed or parked;
    /// the padding it was laid out with, else the kind's standard padding.
    mutating func sanitize(for spec: WidgetKindSpec, standardPadding: CGFloat) {
        authoredSize = CGSize(width: max(authoredSize.width, 1), height: max(authoredSize.height, 1))
        authoredPadding = authoredPadding ?? standardPadding
        decorations = decorations.filter { $0.key.isCustom }
        let allowed = spec.elementIDs
        var seen = Set<ElementID>()
        func keeps(_ id: ElementID) -> Bool {
            (allowed.contains(id) || decorations[id] != nil) && seen.insert(id).inserted
        }
        items = items.filter { keeps($0.id) }.map { frame in
            var frame = frame
            frame.rect = frame.rect.clamped
            return frame
        }
        parked = parked.filter(keeps)
        for element in spec.elements where !seen.contains(element.id) && element.parts.allSatisfy({ !seen.contains($0) }) {
            parked.append(element.id)
            seen.insert(element.id)
        }
        decorations = decorations.filter { seen.contains($0.key) }
    }
}

/// The editing grid over a widget: 2–24 columns by 1–12 rows.
nonisolated struct InnerGrid: Codable, Hashable, Sendable {
    static let columnRange = 2...24
    static let rowRange = 1...12

    private(set) var columns: Int
    private(set) var rows: Int

    init(columns: Int, rows: Int) {
        self.columns = Self.columnRange.clamp(columns)
        self.rows = Self.rowRange.clamp(rows)
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(columns: try c.decode(Int.self, forKey: .columns), rows: try c.decode(Int.self, forKey: .rows))
    }
}

/// One element's place: a rectangle in fractions of the widget, and how it follows a resize.
nonisolated struct ElementFrame: Codable, Hashable, Sendable {
    var id: ElementID
    var rect: UnitRect
    var pinX: Pin
    var pinY: Pin
    /// Not moved by a drag or a nudge.
    var locked: Bool
    var keepsAspect: Bool

    init(id: ElementID, rect: UnitRect, pinX: Pin = .scale, pinY: Pin = .scale, locked: Bool = false, keepsAspect: Bool = false) {
        self.id = id
        self.rect = rect
        self.pinX = pinX
        self.pinY = pinY
        self.locked = locked
        self.keepsAspect = keepsAspect
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ElementID.self, forKey: .id)
        rect = try c.decode(UnitRect.self, forKey: .rect)
        pinX = c.lossy(Pin.self, .pinX) ?? .scale
        pinY = c.lossy(Pin.self, .pinY) ?? .scale
        locked = c.lossy(Bool.self, .locked) ?? false
        keepsAspect = c.lossy(Bool.self, .keepsAspect) ?? false
    }
}

/// Where the room a resize adds or takes goes, on one axis.
nonisolated enum Pin: String, Codable, Hashable, Sendable, CaseIterable {
    /// Held at the leading (top) edge, the trailing (bottom) edge, or the centre.
    case leading, trailing, center
    /// Grows and shrinks with the widget.
    case stretch
    /// Moves and grows in proportion.
    case scale
}

/// A rectangle in fractions of the widget (0…1 on each axis).
nonisolated struct UnitRect: Codable, Hashable, Sendable {
    /// The smallest side, as a fraction.
    static let minimumSide = 0.02

    var x: Double
    var y: Double
    var width: Double
    var height: Double

    /// Inside the widget, and no smaller than the minimum.
    var clamped: UnitRect {
        let range = Self.minimumSide...1
        let width = range.clamp(width), height = range.clamp(height)
        return UnitRect(x: (0...(1 - width)).clamp(x), y: (0...(1 - height)).clamp(y), width: width, height: height)
    }
}

/// Something the user adds to a custom layout, styled like any element.
nonisolated enum Decoration: Codable, Hashable, Sendable {
    case label(String)
    case symbol(String)
    case divider(LayoutAxis)
    case shape(DecorationShape)
}

nonisolated enum DecorationShape: String, Codable, Hashable, Sendable, CaseIterable {
    case rectangle, roundedRectangle, circle, capsule
}
