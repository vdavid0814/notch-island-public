import CoreGraphics
import Foundation

/// The open panel's size beyond the island's own scale (Settings ▸ Widgets ▸ Size): how much wider
/// it is, and how much taller its board, and whether it keeps that size as cells are added (they
/// get smaller) or grows with them (they keep theirs, `BoardSizing`). Stored as one JSON value (`ni2.panel`); a missing or
/// out-of-range field takes its default or its nearest bound, so an older value never resets the
/// others. At the defaults the panel is exactly the size it had before this could be set.
nonisolated struct PanelSettings: Sendable, Equatable, Codable {
    var widthFactor: Double = 1
    var boardHeightFactor: Double = 1
    /// Cells added or taken away leave the panel as it is: the cells and the gap between them get
    /// smaller or larger instead.
    var keepsSize = false

    /// As far as the cells may take it; the screen stops it sooner (`IslandLayout.maximumExpandedSize`).
    static let widthRange: ClosedRange<Double> = 0.85...3
    static let boardHeightRange: ClosedRange<Double> = 0.8...4
    /// What an edge dragged on the stage steps by.
    static let step = 0.05

    init() {}

    init(widthFactor: Double, boardHeightFactor: Double, keepsSize: Bool = false) {
        self.widthFactor = Self.widthRange.clamp(widthFactor)
        self.boardHeightFactor = Self.boardHeightRange.clamp(boardHeightFactor)
        self.keepsSize = keepsSize
    }

    // Tolerant decoding: every field optional, clamped.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PanelSettings()
        self.init(widthFactor: c.lossy(Double.self, .widthFactor) ?? d.widthFactor,
                  boardHeightFactor: c.lossy(Double.self, .boardHeightFactor) ?? d.boardHeightFactor,
                  keepsSize: c.lossy(Bool.self, .keepsSize) ?? d.keepsSize)
    }

    /// The part `IslandLayout` sizes the panel with.
    var layout: PanelLayout {
        PanelLayout(widthFactor: CGFloat(widthFactor), boardHeightFactor: CGFloat(boardHeightFactor))
    }
}

/// The panel's proportions (see `IslandLayout.size(for: .expanded)`); the defaults are the size the
/// panel had before they could be set.
nonisolated struct PanelLayout: Sendable, Equatable {
    var widthFactor: CGFloat = 1
    var boardHeightFactor: CGFloat = 1
}

nonisolated extension ClosedRange {
    func clamp(_ value: Bound) -> Bound { Swift.min(Swift.max(value, lowerBound), upperBound) }
}

nonisolated extension KeyedDecodingContainer {
    /// The value at `key`, or nil when it is missing or cannot be read.
    func lossy<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)).flatMap { $0 }
    }
}
