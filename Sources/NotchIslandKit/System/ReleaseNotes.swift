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
        version: "0.8.4.2",
        new: [
            Item(title: "What's New, in the notch",
                 detail: "After an update the notch opens on what the new version brought: one list to scroll, or one part of it picked in the bar. Settings ▸ About ▸ What's New… shows it again."),
            Item(title: "Fan Control in About ▸ Permissions",
                 detail: "Whether the fan helper is switched on and answers, a button to Login Items, and Reset when it does not work."),
            Item(title: "Rings and dials are set like lines",
                 detail: "The fan's and the chip's dials, Volume's and Brightness' ring, System's rings and the battery's ring: colours, ends, a knob, thickness and size in Customize."),
            Item(title: "Graphs with a range of their own",
                 detail: "Fan Control's graphs: the lowest and the highest value drawn (the temperature's 25 to 100° by itself), and a value written every so many degrees or rpm."),
            Item(title: "Take one of the island's own pages out of the picker",
                 detail: "Battery, Shelf or Home: the bin beside the pages under the stage. Top Bar ▸ Pages brings it back."),
            Item(title: "The fan's dial is made as the chip's",
                 detail: "The speed with rpm and the dial's name are the dial's own texts, placed and styled in its panel. The name says Manual while the fans are held.",
                 isChange: true),
            Item(title: "Customize keeps up with the pointer",
                 detail: "A text dragged in the panel under the editor moves about four times as often as before; the side panels are left alone while it does.",
                 isChange: true),
            Item(title: "Smoother Settings",
                 detail: "Pages fade and rise into place; Widgets, Top Bar and Size, and the gallery's categories, switch without building everything again.",
                 isChange: true),
            Item(title: "The page editor",
                 detail: "Round symbols, a capsule for the name and a red glass Delete.", isChange: true),
        ],
        fixed: [
            Item(title: "A text in a ring no longer grows out of it",
                 detail: "Its size stops at 25 pt, where its slider and its handles do, and letters wider than the ring shrink to fit."),
            Item(title: "Parts with no room read as off",
                 detail: "A widget made too small for a part shows its tile off, with \"No room at this size\"."),
            Item(title: "A page's new symbol shows at once",
                 detail: "The stage's page bar kept the old one until Settings was opened again."),
            Item(title: "The graphs' text size",
                 detail: "Its slider started from another size than the one drawn, and jumped at the first touch. At most 15 pt now."),
        ],
        known: [
            Item(title: "Fan Control on M1–M4",
                 detail: "Tried on an M5 MacBook Pro only. If the fans do not follow the dial, send a report from About."),
            Item(title: "The editor follows a drag in the panel at its end",
                 detail: "While a text is dragged in the panel under Customize's editor, the widget over it shows where it was; it catches up when the drag ends."),
            Item(title: "The fan helper is asked for once more after Reset",
                 detail: "macOS shows its Login Items notice again when the helper is registered anew."),
        ])
}
