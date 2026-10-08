import Foundation

/// Boards saved by earlier versions, read into today's (`WidgetBoard.version`).
///
/// - Version 1 (no version field): widgets with elements only. The elements added in version 2 are
///   switched on, so an old widget keeps looking the way it did (`elementsAddedInVersion2`).
/// - Version 2 (each widget carries its version): one widget per kind, on the fixed 12 × 3 grid.
///   Each widget takes its kind's legacy id (`WidgetID.legacy`), so migrating is deterministic.
/// - Before the first version 3 write, the stored data is copied once to `backupKey`.
nonisolated enum WidgetMigration {
    static let backupKey = WidgetStore.key + ".v2backup"

    /// The version stored data was written by: version 3 states it at the top; before that only its
    /// widgets did (none at all in version 1). 0 when it is not a board.
    static func version(of data: Data) -> Int {
        struct Stored: Decodable {
            struct Widget: Decodable { var version: Int? }
            var version: Int?
            var widgets: [Lossy<Widget>]?
        }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return 0 }
        return stored.version ?? stored.widgets?.compactMap(\.value?.version).max() ?? 1
    }

    /// Keeps the board as it was before version 3, once: a later write never replaces it.
    static func backUp(_ data: Data, in defaults: UserDefaults) {
        guard defaults.data(forKey: backupKey) == nil else { return }
        defaults.set(data, forKey: backupKey)
    }

    /// `id`, or — when a board already has it (a hand-edited or merged board) — the first id derived
    /// from it that is free, the same one every time.
    static func uniqueID(_ id: WidgetID, used: inout Set<WidgetID>) -> WidgetID {
        var unique = id, attempt = 0
        while used.contains(unique) {
            attempt += 1
            unique = WidgetID(name: "notchisland.widget.\(id).\(attempt)")
        }
        used.insert(unique)
        return unique
    }

    /// Elements that did not exist in boards saved before elements (version 1): they are switched
    /// on there, so an old widget keeps looking the way it did.
    /// Parts always drawn before version 4, a switch of their own since: switched on in a widget saved
    /// before, so it keeps them (the calendar's days and weekdays).
    static func elementsSwitchableInVersion4(_ kind: IslandWidgetKind) -> Set<ElementID> {
        switch kind {
        case .monthCalendar: [.monthGrid, .monthWeekdays]
        default: []
        }
    }

    static func elementsAddedInVersion2(_ kind: IslandWidgetKind) -> Set<ElementID> {
        switch kind {
        case .nowPlaying: [.artist, .playbackButtons]
        case .stopwatch: [.readout]
        default: []
        }
    }
}

/// Any JSON, kept as it was read: a widget of a kind this build does not know is written back
/// unchanged (`WidgetBoard.foreign`).
nonisolated enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
