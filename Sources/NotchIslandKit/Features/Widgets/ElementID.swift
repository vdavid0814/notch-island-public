import Foundation

/// One element of a widget (its title, a button, a slider…), by name. The names are the ones boards
/// have been saved with since version 1, so an old board decodes one to one.
nonisolated struct ElementID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
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

    // Wi-Fi.
    static let controlButton = ElementID(rawValue: "controlButton")
    static let controlName = ElementID(rawValue: "controlName")
    static let controlStatus = ElementID(rawValue: "controlStatus")
    // Volume.
    static let levelIcon = ElementID(rawValue: "levelIcon")
    static let levelValue = ElementID(rawValue: "levelValue")
    static let levelSlider = ElementID(rawValue: "levelSlider")
    // Date & Time and the stopwatch.
    static let readout = ElementID(rawValue: "readout")
    static let dateLine = ElementID(rawValue: "dateLine")
    static let resetButton = ElementID(rawValue: "resetButton")
    static let stopwatchButton = ElementID(rawValue: "stopwatchButton")
    // Now Playing.
    static let artwork = ElementID(rawValue: "artwork")
    static let trackInfo = ElementID(rawValue: "trackInfo")
    static let artist = ElementID(rawValue: "artist")
    static let progress = ElementID(rawValue: "progress")
    /// The times under the progress line, each styled on its own (`ProgressLook`).
    static let elapsedTime = ElementID(rawValue: "elapsedTime")
    static let remainingTime = ElementID(rawValue: "remainingTime")
    static let playbackButtons = ElementID(rawValue: "playbackButtons")
    static let skipButtons = ElementID(rawValue: "skipButtons")
    /// Previous and next, each moved on its own (`skipButtons` switches both).
    static let previousButton = ElementID(rawValue: "previousButton")
    static let nextButton = ElementID(rawValue: "nextButton")
    /// Back and forward by some seconds (`IslandWidget.seekSeconds`): the switch, and its two buttons.
    static let seekButtons = ElementID(rawValue: "seekButtons")
    static let seekBackButton = ElementID(rawValue: "seekBackButton")
    static let seekForwardButton = ElementID(rawValue: "seekForwardButton")
    // System.
    static let cpuLoad = ElementID(rawValue: "cpuLoad")
    static let memoryLoad = ElementID(rawValue: "memoryLoad")
    /// The texts of the system's lines: each one's name and value (`ProgressLook.Part`).
    static let cpuTitle = ElementID(rawValue: "cpuTitle")
    static let cpuValue = ElementID(rawValue: "cpuValue")
    static let memoryTitle = ElementID(rawValue: "memoryTitle")
    static let memoryValue = ElementID(rawValue: "memoryValue")
    // A readout (World Clock and its kin): the value, its caption and its symbol.
    static let value = ElementID(rawValue: "value")
    static let label = ElementID(rawValue: "label")
    static let symbol = ElementID(rawValue: "symbol")
    // Battery: the battery (or its ring), the percentage and the time left.
    static let batteryGlyph = ElementID(rawValue: "batteryGlyph")
    /// The battery as a ring (about square): a button in Customize, its charge round its edge.
    static let batteryRing = ElementID(rawValue: "batteryRing")
    static let percentage = ElementID(rawValue: "percentage")
    static let timeRemaining = ElementID(rawValue: "timeRemaining")
    /// A chart (Battery Chart).
    static let chart = ElementID(rawValue: "chart")
    // Clipboard: each copy's text and its symbol, a part of its own; the symbols' switch.
    static let clipSymbols = ElementID(rawValue: "clipSymbols")
    // Timer: the ruler (a scale to set by scrolling), the time (`readout`), its action (Start,
    // Pause, Resume, Done), Cancel while it counts, and +1.
    static let ruler = ElementID(rawValue: "ruler")
    static let timerActions = ElementID(rawValue: "timerActions")
    static let timerCancel = ElementID(rawValue: "timerActions.cancel")
    static let addMinute = ElementID(rawValue: "addMinute")
    /// The unit's name beside the ruler's marker ("min", "sec", "hr"): its switch, and its text
    /// (styled from the panel under Customize's editor, never moved in the editor itself).
    static let rulerUnit = ElementID(rawValue: "ruler.unit")
    /// The switches that let the time be set in hours, and in seconds (a part of the time picked,
    /// the ruler sets it).
    static let timerHours = ElementID(rawValue: "timerHours")
    static let timerSeconds = ElementID(rawValue: "timerSeconds")
    // Shelf: the files to drag out; the tray and the count (one switch); AirDrop and Clear (one switch).
    static let previews = ElementID(rawValue: "previews")
    static let shelfTray = ElementID(rawValue: "shelfCount.tray")
    static let shelfCount = ElementID(rawValue: "shelfCount")
    static let shelfActions = ElementID(rawValue: "shelfActions")
    static let shelfAirDrop = ElementID(rawValue: "shelfActions.airDrop")
    static let shelfClear = ElementID(rawValue: "shelfActions.clear")
    // Clock Face: the dial, its seconds hand's switch; the caption is `label`.
    static let face = ElementID(rawValue: "face")
    static let secondsHand = ElementID(rawValue: "secondsHand")
    // Calendar: the month's days (its name is `label`).
    static let monthGrid = ElementID(rawValue: "monthGrid")
    /// The days' numbers in it: a text of the grid's own (its type, size and colour).
    static let monthDays = ElementID(rawValue: "monthGrid.days")
    /// The weekdays' letters over the days: a switch of the grid's.
    static let monthWeekdays = ElementID(rawValue: "monthGrid.weekdays")
    // Daily Usage: the day picked under the percentage (the title is `label`, the bars `chart`).
    static let usageDay = ElementID(rawValue: "usageDay")
    // Fan Control: the dial round the fan (its speed is `value`, automatic or manual `label`), the
    // chip's temperature as a dial of its own, and the graphs of the temperature and the speed.
    static let fanDial = ElementID(rawValue: "fanDial")
    static let tempDial = ElementID(rawValue: "tempDial")
    static let tempGraph = ElementID(rawValue: "tempGraph")
    static let rpmGraph = ElementID(rawValue: "rpmGraph")
    /// The texts in the dials, each set from its dial's panel (`ProgressLook.Part`): the fan's name
    /// and its unit ("rpm"), the chip's name and its degrees.
    static let fanName = ElementID(rawValue: "fanDial.name")
    static let fanUnit = ElementID(rawValue: "fanDial.unit")
    static let tempName = ElementID(rawValue: "tempDial.name")
    static let tempValue = ElementID(rawValue: "tempDial.value")
    /// A graph's texts (its name, the value now, the values beside it): one style for them all.
    static let tempGraphText = ElementID(rawValue: "tempGraph.text")
    static let rpmGraphText = ElementID(rawValue: "rpmGraph.text")

    /// The `row`th copy's text (from 1).
    static func clipText(_ row: Int) -> ElementID { ElementID(rawValue: "clipText\(row)") }

    /// The `row`th copy's symbol, a button (from 1).
    static func clipSymbol(_ row: Int) -> ElementID { ElementID(rawValue: "clipSymbol\(row)") }

    /// The copy a Clipboard part is of (from 1); nil for any other part.
    var clipRow: Int? {
        for prefix in ["clipText", "clipSymbol"] where rawValue.hasPrefix(prefix) {
            return Int(rawValue.dropFirst(prefix.count))
        }
        return nil
    }
}
