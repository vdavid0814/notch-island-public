import Foundation

/// How the battery page draws its chart (Settings ▸ Activities ▸ Battery Page, and the chart's
/// context menu). Stored as one JSON value (`ni2.battery`); a field missing from an older value, or
/// one this build cannot read, keeps its default, so adding one never resets the others.
nonisolated struct BatteryDisplaySettings: Sendable, Equatable, Codable {
    var style: BatteryChartStyle = .bars
    var range: BatteryChartRange = .today
    /// The level on battery; automatic is white.
    var normalColor: StyleColor = .automatic
    /// While charging; automatic is green.
    var chargingColor: StyleColor = .automatic
    /// Below 20 % on battery; automatic is red.
    var lowColor: StyleColor = .automatic
    /// Hatching where nothing is known (the Mac asleep, or the app not running).
    var showsGaps = true
    /// A faint band where the displays were off.
    var shadesDisplayOff = true
    /// "Last charged to …" over the chart and the percentages beside it.
    var showsCaptions = true

    init() {}

    // Tolerant decoding: every field optional, colours clamped.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BatteryDisplaySettings()
        style = c.lossy(BatteryChartStyle.self, .style) ?? d.style
        range = c.lossy(BatteryChartRange.self, .range) ?? d.range
        normalColor = c.lossy(StyleColor.self, .normalColor)?.sanitized ?? d.normalColor
        chargingColor = c.lossy(StyleColor.self, .chargingColor)?.sanitized ?? d.chargingColor
        lowColor = c.lossy(StyleColor.self, .lowColor)?.sanitized ?? d.lowColor
        showsGaps = c.lossy(Bool.self, .showsGaps) ?? d.showsGaps
        shadesDisplayOff = c.lossy(Bool.self, .shadesDisplayOff) ?? d.shadesDisplayOff
        showsCaptions = c.lossy(Bool.self, .showsCaptions) ?? d.showsCaptions
    }
}

nonisolated extension BatteryChartStyle {
    var title: String {
        switch self {
        case .bars: "Bars"
        case .area: "Area"
        case .line: "Line"
        }
    }
}

nonisolated extension BatteryChartRange {
    var title: String {
        switch self {
        case .today: "Today"
        case .last24Hours: "24 Hours"
        case .last48Hours: "48 Hours"
        }
    }
}
