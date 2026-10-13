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
        version: "0.8.5.1.1",
        new: [
            Item(title: "No more spikes on the charger",
                 detail: "Settings now stays ready while you use the Mac on the charger too, so opening it no longer makes a burst of work. It frees its memory when the Mac is locked or asleep, or when macOS needs memory, and gets ready again quietly once you are back.",
                 isChange: true),
            Item(title: "Settings ▸ Widgets opens lighter",
                 detail: "Opening Settings on the Widgets page takes about a third less energy.",
                 isChange: true),
            Item(title: "Spotlight's quick picks",
                 detail: "The pointer over Spotlight shows Applications, Files, Actions and Clipboard as large icons in a row. System, Windows, Emoji and People & Calendar are still a shortcut (⌘5–⌘8) or ↓ away.",
                 isChange: true),
            Item(title: "Clearer in Light Mode",
                 detail: "With Liquid Glass and the Mac in Light Mode, the island is a little darker, and widgets on no background or a plate get a black Colour background at 40 % — set in their own settings, so you can change it. Back in Dark Mode they get theirs back."),
            Item(title: "Settings ▸ Widgets moves smoothly",
                 detail: "Switching pages, categories or Widgets / Top Bar / Size no longer hitches the bar's glass: the work waits until it has slid. Pages crossfade, quick clicks included; Size mode unfolds and the inspector comes up without redrawing the page at every frame.",
                 isChange: true),
            Item(title: "A new page is named first",
                 detail: "The + beside the pages opens the same editor as the pencil: a name, a symbol, then Create Page. Home, Battery or Shelf taken out of the picker come back from there too.",
                 isChange: true),
            Item(title: "NotchIsland's own Spotlight mark",
                 detail: "In Spotlight's field, in Settings' sidebar and beside Replace macOS Spotlight. Settings' preview wallpaper follows Light and Dark Mode.",
                 isChange: true),
        ],
        fixed: [
            Item(title: "Memory after Settings",
                 detail: "Closed Settings kept about 250 MB on the charger. It is freed now (about 80 MB)."),
            Item(title: "Empty widget previews",
                 detail: "Opened right after the app started, Settings ▸ Widgets could show its gallery's pictures empty."),
            Item(title: "Widgets flying in after Size",
                 detail: "Back from Size to Widgets, the gallery flew in from the top of the page."),
            Item(title: "Spotlight's old list",
                 detail: "Folding back, Spotlight showed the old list of suggestions for a moment. Only the quick picks show now; ↑/↓ and Return go through them."),
            Item(title: "Spotlight icon twice",
                 detail: "The mark stood both over the field and in it."),
            Item(title: "A page of your own froze the app",
                 detail: "Switching to it from Home or Battery could hang Settings at full CPU, and its editor did not open."),
            Item(title: "The widget search field",
                 detail: "Its blue focus ring stood out past the gallery's edge."),
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
