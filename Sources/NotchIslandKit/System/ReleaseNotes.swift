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
        version: "0.8.4.4",
        new: [
            Item(title: "Liquid Glass is clear",
                 detail: "Plain, colourless glass: nothing smoked, no tint, and the white veil even the clearest glass lays over the desktop is taken back out. It follows System Settings ▸ Appearance ▸ Liquid Glass: fully see-through at the clear end of that slider, evenly darker towards its tinted end. Fade and Black are as they were.",
                 isChange: true),
            Item(title: "Settings shows the island as it is",
                 detail: "General's Appearance and Size pictures, the picture of the island opening, and every picture in Live Activities are photographs of the island itself, in the style and at the size in use, over the preview wallpaper."),
            Item(title: "Wider Settings pages",
                 detail: "General, Live Activities, Spotlight and About use the whole room beside the sidebar, as Widgets does.",
                 isChange: true),
            Item(title: "The scroller keeps out of the way",
                 detail: "The bar beside a Settings page shows only while the pointer is on it, where it can be dragged; scrolling no longer brings it up.",
                 isChange: true),
            Item(title: "Preview Wallpaper",
                 detail: "macOS Dark, macOS Light and the test pattern. Your Desktop is gone for now; a stored choice of it becomes macOS Dark.",
                 isChange: true),
            Item(title: "About starts with Updates",
                 detail: "The card with the app's name and description is gone; the version heads the sidebar.",
                 isChange: true),
            Item(title: "Lighter",
                 detail: "Settings is built ahead in low-priority turns after a launch, Size mode in Widgets unfolds in one layout pass, and a swipe along the Timer's ruler costs about half of what it did.",
                 isChange: true),
        ],
        fixed: [],
        known: [
            Item(title: "Light text on clear glass",
                 detail: "Over a light desktop, the island's grey secondary texts are hard to read on Liquid Glass. Fade and Black keep their black under them."),
            Item(title: "Settings' pictures show one island",
                 detail: "The photographs were taken on one Mac: the island in them has that Mac's width, not yours."),
            Item(title: "Fan Control on M1–M4",
                 detail: "Tried on an M5 MacBook Pro only. If the fans do not follow the dial, send a report from About."),
        ])
}
