import Foundation

/// One element of a widget (its title, a button, a ring…), by name. The names are the ones boards
/// have been saved with since version 1, so an old board decodes one to one. What an element is in a
/// given kind — its title, role, samples — is that kind's `ElementSpec`.
///
/// Parts of an element are `<element>.<part>` (`skipButtons.previous`); decorations the user adds
/// in a custom layout are `custom.<uuid>`.
nonisolated struct ElementID: RawRepresentable, Hashable, Codable, CodingKeyRepresentable, Sendable, Identifiable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }

    var id: String { rawValue }

    // As its name alone, the way boards have stored elements since version 1.
    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let customPrefix = "custom."

    /// A decoration of a custom layout.
    static func custom(_ uuid: UUID = UUID()) -> ElementID { ElementID(rawValue: customPrefix + uuid.uuidString) }

    var isCustom: Bool { rawValue.hasPrefix(Self.customPrefix) }

    /// A part of this element (`skipButtons.previous`).
    func part(_ name: String) -> ElementID { ElementID(rawValue: rawValue + "." + name) }

    // Now Playing.
    static let artwork = ElementID(rawValue: "artwork")
    static let trackInfo = ElementID(rawValue: "trackInfo")
    static let artist = ElementID(rawValue: "artist")
    static let progress = ElementID(rawValue: "progress")
    static let playbackButtons = ElementID(rawValue: "playbackButtons")
    static let skipButtons = ElementID(rawValue: "skipButtons")
    // Timer, stopwatch and the time.
    static let ruler = ElementID(rawValue: "ruler")
    static let readout = ElementID(rawValue: "readout")
    static let addMinute = ElementID(rawValue: "addMinute")
    /// The timer is set in seconds too, and in hours (`TimerDraftUnits`).
    static let timerSeconds = ElementID(rawValue: "timerSeconds")
    static let timerHours = ElementID(rawValue: "timerHours")
    static let resetButton = ElementID(rawValue: "resetButton")
    // Shelf.
    static let previews = ElementID(rawValue: "previews")
    static let shelfCount = ElementID(rawValue: "shelfCount")
    static let shelfActions = ElementID(rawValue: "shelfActions")
    // Battery.
    static let batteryGlyph = ElementID(rawValue: "batteryGlyph")
    static let percentage = ElementID(rawValue: "percentage")
    static let timeRemaining = ElementID(rawValue: "timeRemaining")
    // Volume and brightness.
    static let levelIcon = ElementID(rawValue: "levelIcon")
    static let levelValue = ElementID(rawValue: "levelValue")
    /// A control widget's name and its On / Off (shown when it is wider than its button).
    static let controlName = ElementID(rawValue: "controlName")
    static let controlStatus = ElementID(rawValue: "controlStatus")
    // Siri.
    static let assistantLabel = ElementID(rawValue: "assistantLabel")
    // Date & Time, System.
    static let dateLine = ElementID(rawValue: "dateLine")
    static let cpuLoad = ElementID(rawValue: "cpuLoad")
    static let memoryLoad = ElementID(rawValue: "memoryLoad")
    // A reading, its caption, its symbol and its chart: the elements of a kind that shows one value. A family
    // adds its own elements in an `ElementID` extension in its spec file.
    static let value = ElementID(rawValue: "value")
    static let label = ElementID(rawValue: "label")
    static let symbol = ElementID(rawValue: "symbol")
    /// A chart of the reading over time.
    static let chart = ElementID(rawValue: "chart")
    /// An analog clock's face, a month's grid of days, a list of events.
    static let face = ElementID(rawValue: "face")
    static let monthGrid = ElementID(rawValue: "monthGrid")
    static let eventList = ElementID(rawValue: "eventList")
    // Tools.
    static let appIcons = ElementID(rawValue: "appIcons")
    static let clipList = ElementID(rawValue: "clipList")
    static let photo = ElementID(rawValue: "photo")
}
