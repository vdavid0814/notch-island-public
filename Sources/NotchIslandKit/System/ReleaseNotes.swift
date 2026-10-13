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
        version: "0.8.5.4",
        new: [
            Item(title: "It answers at once after a launch",
                 detail: "Settings is made ready in the background a few seconds after NotchIsland starts. A hover, a volume or brightness key or ⌘Space in that moment waited for it, up to two and a half seconds; now they come first.",
                 isChange: true),
            Item(title: "Page switches are lighter",
                 detail: "The slide from one page of the panel to the next runs on the window server: the app does a third of the work for it, and a switch takes about 60 % less energy.",
                 isChange: true),
            Item(title: "On battery, the content fades without the app",
                 detail: "A pill giving way to the panel or to a banner is faded by the window server too, so it stays smooth while the app is busy.",
                 isChange: true),
            Item(title: "Kinder to a Mac short of memory",
                 detail: "Settings is no longer made ready ahead while macOS asks for memory; it is built when you open it.",
                 isChange: true),
        ],
        fixed: [
            Item(title: "Freezes on a busy Mac",
                 detail: "With every core or the memory taken — builds, simulators, many apps — the island could stand still for seconds: right after an update, while opening or closing Settings, while switching pages. It keeps its own priority now whenever the Mac is busy."),
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
