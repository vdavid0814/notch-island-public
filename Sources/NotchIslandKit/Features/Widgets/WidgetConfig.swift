import Foundation

/// What one widget shows, where its kind asks for it (`WidgetKindSpec.settings`): a world clock's
/// city, a list's length. Every field optional (nil: the kind's own), decoded field by field, under
/// the names boards saved them with before, so an old widget's settings come back with it.
nonisolated struct WidgetConfig: Codable, Hashable, Sendable {
    /// An IANA identifier ("Europe/Budapest").
    var timeZone: String?
    /// The user's caption (a world clock's city).
    var label: String?
    /// How many things it lists (clipboard entries).
    var count: Int?
    /// The rows that have a symbol, from 1, in order (clipboard's; nil: the first alone).
    var symbolRows: [Int]?

    static let countRange = 1...8
    static let labelLimit = 40

    init() {}

    private enum CodingKeys: String, CodingKey { case timeZone, label, count, symbolRows }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timeZone = (try? c.decodeIfPresent(String.self, forKey: .timeZone)).flatMap { $0 }
        label = (try? c.decodeIfPresent(String.self, forKey: .label)).flatMap { $0 }
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)).flatMap { $0 }
        symbolRows = (try? c.decodeIfPresent([Int].self, forKey: .symbolRows)).flatMap { $0 }
    }

    /// An unknown time zone, an empty caption and an out-of-range count are left out.
    mutating func sanitize() {
        if let timeZone, TimeZone(identifier: timeZone) == nil { self.timeZone = nil }
        label = label.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.labelLimit)) }
            .flatMap { $0.isEmpty ? nil : $0 }
        count = count.map { min(max($0, Self.countRange.lowerBound), Self.countRange.upperBound) }
        symbolRows = symbolRows.map { Array(Set($0.filter(Self.countRange.contains))).sorted() }.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// A setting a kind offers in Customize (its panel's Settings), stored in `WidgetConfig`.
nonisolated enum WidgetSetting: Sendable, Hashable {
    /// The city, by its time zone.
    case timeZone
    /// A caption of the user's own, in place of the kind's.
    case label
    /// How many rows it lists.
    case count
    /// Which of its rows have a symbol (how many, from the top, in Customize's Settings).
    case symbols
    /// How many files share the shelf's row (`count`, `ShelfWidget.fileCounts`).
    case files
}
