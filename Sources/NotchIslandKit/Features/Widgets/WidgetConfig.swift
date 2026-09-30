import Foundation

/// What one instance shows, where its kind asks for it: a world clock's time zone, a countdown's
/// date, a shortcut's name, a launcher's apps… Every field optional (nil: the kind's default), and
/// decoded field by field like `WidgetStyle`. Larger per-instance data does not belong here.
nonisolated struct WidgetConfig: Codable, Hashable, Sendable {
    /// An IANA identifier ("Europe/Budapest").
    var timeZone: String?
    /// The user's caption (a world clock's city, a countdown's event).
    var label: String?
    var date: Date?
    var shortcutName: String?
    /// An SF Symbol name.
    var symbol: String?
    /// App bundle paths, in order.
    var apps: [String]?
    var imagePath: String?
    var calendarIDs: [String]?
    /// How many things it lists (clipboard entries, apps).
    var count: Int?

    static let countRange = 1...8
    static let labelLimit = 40

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timeZone = c.lossy(String.self, .timeZone)
        label = c.lossy(String.self, .label)
        date = c.lossy(Date.self, .date)
        shortcutName = c.lossy(String.self, .shortcutName)
        symbol = c.lossy(String.self, .symbol)
        apps = c.lossy([Lossy<String>].self, .apps)?.compactMap(\.value)
        imagePath = c.lossy(String.self, .imagePath)
        calendarIDs = c.lossy([Lossy<String>].self, .calendarIDs)?.compactMap(\.value)
        count = c.lossy(Int.self, .count)
    }

    /// An unknown time zone, empty texts and an out-of-range count are left out; the apps are
    /// capped at the most a launcher shows.
    mutating func sanitize() {
        if let timeZone, TimeZone(identifier: timeZone) == nil { self.timeZone = nil }
        label = label.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.labelLimit)) }
            .flatMap { $0.isEmpty ? nil : $0 }
        for path in [\WidgetConfig.shortcutName, \.symbol, \.imagePath] where self[keyPath: path]?.isEmpty == true {
            self[keyPath: path] = nil
        }
        apps = apps.map { Array($0.filter { !$0.isEmpty }.prefix(Self.countRange.upperBound)) }
        calendarIDs = calendarIDs?.filter { !$0.isEmpty }
        count = count.map(Self.countRange.clamp)
    }
}
