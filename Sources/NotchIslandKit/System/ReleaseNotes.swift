import Foundation

/// What a version brought, for the page shown in the notch after an update (`WhatsNewPage`): what
/// is new, what was fixed and what is still known not to work. Written with each release; the page
/// shows only the notes of the version that runs (`AppUpdater.current`).
nonisolated struct ReleaseNotes: Sendable, Equatable {
    nonisolated enum Section: String, Sendable, CaseIterable, Identifiable {
        case new, fixed, known

        var id: String { rawValue }

        var title: String {
            switch self {
            case .new: String(localized: "What's New")
            case .fixed: String(localized: "Fixed")
            case .known: String(localized: "Known Issues")
            }
        }

        var symbol: String {
            switch self {
            case .new: "sparkles"
            case .fixed: "checkmark.seal.fill"
            case .known: "exclamationmark.triangle.fill"
            }
        }
    }

    nonisolated struct Item: Sendable, Equatable, Identifiable {
        var title: String
        var detail: String
        /// Changed rather than new: marked so among What's New.
        var isChange = false

        var id: String { title }
    }

    var version: String
    var new: [Item]
    var fixed: [Item]
    var known: [Item]

    func items(_ section: Section) -> [Item] {
        switch section {
        case .new: new
        case .fixed: fixed
        case .known: known
        }
    }

    /// The sections with anything in them.
    var sections: [Section] { Section.allCases.filter { !items($0).isEmpty } }

    static let current = ReleaseNotes(
        version: "0.8.4.5",
        new: [
            Item(title: "A fan speed set by hand stays",
                 detail: "Turn Fan Control's dial and the fans are held there until you click the fan in it for automatic: fans macOS takes back meanwhile are taken again, and the dial says Manual all along. Only a chip at its limit (105 °C) gives them back by itself, until it has cooled.",
                 isChange: true),
            Item(title: "Fans down to 0 rpm",
                 detail: "The dial starts at nothing instead of the slowest macOS turns the fans: all the way down holds them still. A Mac that will not stop a fan holds it at its slowest.",
                 isChange: true),
            Item(title: "Auto or Manual, between the fan and the speed",
                 detail: "The mode has a line of its own in the dial, under the fan and over the rpm. The dial's name, Fan, stays in its opening.",
                 isChange: true),
            Item(title: "Graphs of the last 30 seconds",
                 detail: "Fan Control's temperature and speed graphs show the last half minute, a reading a second, so what just happened is seen as it moved, on a small graph too. The speed graph starts at 0 rpm.",
                 isChange: true),
            Item(title: "The dial turns smoothly",
                 detail: "A turn of the dial asked macOS about the fan helper at every step, 15 ms each time; it stuttered. Asked once now, and a turn redraws the dial alone.",
                 isChange: true),
            Item(title: "Lighter",
                 detail: "The Timer's ruler is drawn as layers: a swipe along it costs about a fifth of what it did. On the charger Settings is built when opened, so the app rests at about 27 MB instead of 220.",
                 isChange: true),
        ],
        fixed: [
            Item(title: "The menu bar at the notch in full screen",
                 detail: "The strip that keeps the menu bar from coming down when the pointer is on the notch could be left on another Space, and covered nothing. It is brought to the Space in use."),
            Item(title: "Automatic at once",
                 detail: "After a click on the fan the dial said Manual for another second."),
        ],
        known: [
            Item(title: "Light text on clear glass",
                 detail: "Over a light desktop, the island's grey secondary texts are hard to read on Liquid Glass. Fade and Black keep their black under them."),
            Item(title: "Settings' pictures show one island",
                 detail: "The photographs were taken on one Mac: the island in them has that Mac's width, not yours."),
            Item(title: "Fan Control on M1–M4",
                 detail: "Tried on an M5 MacBook Pro only. If the fans do not follow the dial, or do not stay where it was set, send a report from About."),
            Item(title: "A fan held still",
                 detail: "With the fans stopped the chip gets hot under load and macOS slows it down. Click the fan for automatic before heavy work."),
        ])
}
