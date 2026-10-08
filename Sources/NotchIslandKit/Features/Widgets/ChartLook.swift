import Foundation

/// How a chart is drawn (`WidgetKindSpec.charts`), from Customize's inspector: its bars' corners,
/// the colour of a bar by how far the battery has run down, and how often a percentage is written
/// beside it (its dashed lines with them). Every field at its default is the chart as the widget
/// draws it on its own.
nonisolated struct ChartLook: Sendable, Codable, Hashable {
    var corners: Corners = .rounded
    /// Run down a lot: below `PowerState.lowLevel` (automatic: red).
    var lowColor: TextStyle.TextColor = .automatic
    /// Run down some: from there to `mediumLevel` (automatic: the bars' grey).
    var mediumColor: TextStyle.TextColor = .automatic
    /// Run down little: from `mediumLevel` up (automatic: the bars' grey).
    var highColor: TextStyle.TextColor = .automatic
    /// A percentage (and its dashed line) every this many percent; 0: none beside the chart.
    var percentStep = 50

    static let plain = ChartLook()

    /// Where "run down some" ends and "run down little" begins.
    static let mediumLevel = 50
    /// The steps offered: none, 0 and 100 only, then every half, quarter, fifth and tenth.
    static let percentSteps = [0, 100, 50, 25, 20, 10]

    nonisolated enum Corners: String, Sendable, Codable, CaseIterable, Identifiable {
        case slight, rounded, square

        var id: String { rawValue }

        var title: String {
            switch self {
            case .slight: "Slight"
            case .rounded: "Rounded"
            case .square: "Square"
            }
        }

        /// A bar's top corners' radius, for a bar `width` wide.
        func radius(width: CGFloat) -> CGFloat {
            switch self {
            case .slight: min(width * 0.12, 1.25)
            case .rounded: min(width * 0.3, 3)
            case .square: 0
            }
        }
    }

    init() {}

    private enum CodingKeys: String, CodingKey { case corners, lowColor, mediumColor, highColor, percentStep }

    // Field by field: one this build cannot read keeps its default.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        corners = (try? c.decodeIfPresent(Corners.self, forKey: .corners)).flatMap { $0 } ?? .rounded
        lowColor = (try? c.decodeIfPresent(TextStyle.TextColor.self, forKey: .lowColor)).flatMap { $0 } ?? .automatic
        mediumColor = (try? c.decodeIfPresent(TextStyle.TextColor.self, forKey: .mediumColor)).flatMap { $0 } ?? .automatic
        highColor = (try? c.decodeIfPresent(TextStyle.TextColor.self, forKey: .highColor)).flatMap { $0 } ?? .automatic
        percentStep = (try? c.decodeIfPresent(Int.self, forKey: .percentStep)).flatMap { $0 } ?? 50
    }

    /// A step not offered is the chart's own.
    mutating func sanitize() {
        if !Self.percentSteps.contains(percentStep) { percentStep = 50 }
    }

    /// What a step is called in Customize.
    static func title(ofStep step: Int) -> String {
        switch step {
        case 0: String(localized: "None")
        case 100: String(localized: "0 and 100 %")
        default: String(localized: "Every \(step) %")
        }
    }

    /// The levels written beside the chart, low to high.
    var percentages: [Int] {
        percentStep > 0 ? Array(stride(from: 0, through: 100, by: percentStep)) : []
    }
}
