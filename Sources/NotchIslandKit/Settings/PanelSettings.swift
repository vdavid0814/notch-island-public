import CoreGraphics
import Foundation

/// The open panel's size beyond the island's own scale (Settings ▸ Widgets ▸ Size): how much wider
/// it is, and how much taller its board. Stored as one JSON value (`ni2.panel`); a missing or
/// out-of-range field takes its default or its nearest bound, so an older value never resets the
/// others. At the defaults the panel is exactly the size it had before this could be set.
nonisolated struct PanelSettings: Sendable, Equatable, Codable {
    var widthFactor: Double = 1
    var boardHeightFactor: Double = 1

    static let widthRange: ClosedRange<Double> = 0.85...1.6
    static let boardHeightRange: ClosedRange<Double> = 0.8...2.2

    init() {}

    init(widthFactor: Double, boardHeightFactor: Double) {
        self.widthFactor = Self.widthRange.clamp(widthFactor)
        self.boardHeightFactor = Self.boardHeightRange.clamp(boardHeightFactor)
    }

    // Tolerant decoding: every field optional, clamped.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PanelSettings()
        self.init(widthFactor: c.lossy(Double.self, .widthFactor) ?? d.widthFactor,
                  boardHeightFactor: c.lossy(Double.self, .boardHeightFactor) ?? d.boardHeightFactor)
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
