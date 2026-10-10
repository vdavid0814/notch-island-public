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
        version: "0.8.4.3",
        new: [
            Item(title: "The Top Bar page, made anew",
                 detail: "Each side's bar as round chips in their order, the picker's pages in a capsule of their own, and everything the bar can hold in one list under them. Drag anything anywhere: into a bar, across to the other, or out onto the list; the chips make room as it comes."),
            Item(title: "A colour for each button",
                 detail: "Click a button or a page's symbol in Top Bar mode, ⌘-click to pick more, and Button Colour sets their colour; with none picked it colours them all. The pages' colours show in the picker under the stage too."),
            Item(title: "⌘Z and ⌘⇧Z in every mode",
                 detail: "Widgets, Top Bar and Size each step back and forward through what was changed there."),
            Item(title: "AirDrop in the top bar",
                 detail: "A button that opens AirDrop, beside Wi-Fi, Bluetooth, Dark Mode and Focus."),
            Item(title: "The shelf under the stage",
                 detail: "The stage's page bar shows the island's pages in the top bar's own order, the shelf among them. A page taken out of the picker comes back from the + beside them."),
            Item(title: "Felt on the trackpad",
                 detail: "A chip dragged in Top Bar mode ticks as a place opens for it and as it settles there."),
            Item(title: "Settings in two boxes",
                 detail: "The page beside the sidebar keeps the same gap to the sidebar, to the island's side and to its foot, and is cut round its lower corners as the sidebar is.",
                 isChange: true),
            Item(title: "Widgets' scroller stands beside the page",
                 detail: "In the gap at the island's side, not over the cards.", isChange: true),
            Item(title: "The stage's bar",
                 detail: "The ⋯ button is gone: the wallpaper and Reset to Default Widgets are on a right click of the stage's desktop. Top Bar mode's hint sits on glass and closes with its cross.",
                 isChange: true),
            Item(title: "Smoother Widgets page",
                 detail: "Another page on the stage fades in at once, and the gallery no longer slows the rest of the page while it is out of sight.",
                 isChange: true),
        ],
        fixed: [
            Item(title: "Nothing stands out of the island's corner",
                 detail: "Widgets' cards and its scroller reached past the island's rounded lower right corner."),
            Item(title: "Reset Bars is level with the sidebar's foot",
                 detail: "Top Bar mode's page fills the room under the stage; nothing in it scrolls."),
        ],
        known: [
            Item(title: "Fan Control on M1–M4",
                 detail: "Tried on an M5 MacBook Pro only. If the fans do not follow the dial, send a report from About."),
            Item(title: "The page picker's chosen page keeps the system's colour",
                 detail: "A colour set for a page shows on its symbol; the picker's own highlight stays as the system draws it."),
            Item(title: "The editor follows a drag in the panel at its end",
                 detail: "While a text is dragged in the panel under Customize's editor, the widget over it shows where it was; it catches up when the drag ends."),
        ])
}
