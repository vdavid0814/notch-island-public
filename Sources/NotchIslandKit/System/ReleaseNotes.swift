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
        version: "0.8.5.2",
        new: [
            Item(title: "Liquid Glass follows its slider",
                 detail: "System Settings ▸ Appearance ▸ Liquid Glass sets the island too: clear glass at the Clear end, frosting evenly as you move it, the system's frosted glass at the Tinted end.",
                 isChange: true),
            Item(title: "White glass in Light Mode",
                 detail: "With Liquid Glass and the Mac in Light Mode the island is light glass with black text and symbols, and a thin dark edge so it stands out on a light desktop — the volume and AirPods card too. Sliders, the battery and the grey bars of the charts are drawn darker so they show.",
                 isChange: true),
            Item(title: "A widget background for each Mode",
                 detail: "With Liquid Glass every widget gets a Colour background as the Mode begins: light grey at 50 % in Light Mode, black at 40 % in Dark Mode. Settings ▸ Widgets says so, with Revert Changes to go back to your own; with another style they get theirs back.",
                 isChange: true),
            Item(title: "A black notch",
                 detail: "With Liquid Glass the island at the notch's height (music, timers) is solid black, as with Fade and Black. Closing into it, it turns black as it closes, not when it lands.",
                 isChange: true),
            Item(title: "The volume card",
                 detail: "The card that comes down for the AirPods' volume opens a little quicker and stays a moment longer.",
                 isChange: true),
        ],
        fixed: [
            Item(title: "The menu bar stayed covered",
                 detail: "Leaving a full-screen app, the black strip over the menu bar could stay on the desktop until the next full screen."),
            Item(title: "Stutter right after launch on a busy Mac",
                 detail: "Settings gets itself ready in the background after launch; on a Mac that was busy or short of memory that held the island up for a while. It now waits until the Mac is calmer."),
            Item(title: "Widgets left out of the automatic background",
                 detail: "After Undo or a notch style some widgets were taken for your own changes and no longer got it."),
        ],
        known: [
            Item(title: "Settings' pictures show one island",
                 detail: "The photographs were taken on one Mac: the island in them has that Mac's width, not yours."),
            Item(title: "Fan Control on M1–M4",
                 detail: "Tried on an M5 MacBook Pro only. If the fans do not follow the dial, or do not stay where it was set, send a report from About."),
            Item(title: "A fan held still",
                 detail: "With the fans stopped the chip gets hot under load and macOS slows it down. Click the fan for automatic before heavy work."),
        ])
}
