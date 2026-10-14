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
        version: "0.8.6",
        new: [
            Item(title: "Use Siri AI in the island",
                 detail: "Spotlight's Use Siri AI asks the system's Siri AI out of sight and shows its answer in the island, laid out as Siri lays it out: paragraphs and links, sources, file and app cards, photos, its buttons."),
            Item(title: "Two fingers back and forward",
                 detail: "Swipe sideways with two fingers to go back and forward: in Siri between suggestions, in Settings between the pages and Customize you have been to."),
            Item(title: "System grows into a graph and dials",
                 detail: "Given room, the System widget draws its loads as a graph over 10 seconds to 10 minutes, and as dials if you like; the GPU's load is among them."),
            Item(title: "Grey text you can read on clear glass",
                 detail: "On Liquid Glass, grey texts and texts in a light colour of their own (the cover's colour of a title) get a thin sharp edge: black in Light Mode, white in Dark Mode."),
            Item(title: "A touch more frost",
                 detail: "Liquid Glass at its clearest is a little more frosted: 40 % white in Light Mode, 35 % black in Dark Mode.",
                 isChange: true),
            Item(title: "Lighter openings",
                 detail: "The closed panel is kept ten minutes and stays at rest; opening it from an empty notch only shows it.",
                 isChange: true),
        ],
        fixed: [
            Item(title: "A page's new symbol in the top bar",
                 detail: "A page given another symbol kept the old one in the top bar until Settings was opened again."),
            Item(title: "Sharp previews in Settings",
                 detail: "Where macOS's wallpaper video is not downloaded, the previews' desktop was a tiny blurred picture; the default wallpaper now comes with the app."),
        ],
        known: [
            Item(title: "Settings' pictures show one island",
                 detail: "The photographs were taken on one Mac: the island in them has that Mac's width, not yours."),
            Item(title: "Fan Control on M1–M4",
                 detail: "Tried on an M5 MacBook Pro only. If the fans do not follow the dial, or do not stay where it was set, send a report from About."),
            Item(title: "A fan held still",
                 detail: "With the fans stopped the chip gets hot under load and macOS slows it down. Click Manual for automatic before heavy work."),
        ])
}
