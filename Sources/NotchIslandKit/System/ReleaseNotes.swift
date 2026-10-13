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
        version: "0.8.5.3",
        new: [
            Item(title: "Fan Control: one graph",
                 detail: "The heat as a line and, under it, the fans as a row of strokes — far apart while they turn slowly, close together while they turn fast — so you see the fans answer the heat. A dotted line marks the lowest temperature in view.",
                 isChange: true),
            Item(title: "Colours by reading",
                 detail: "Fan Control's dials, the heat line and every stroke are green while low, yellow halfway and red near the top.",
                 isChange: true),
            Item(title: "How far back the graph goes",
                 detail: "Ten seconds to ten minutes: click the time under the graph (a glass button) and set it on the timer's ruler, minutes or seconds, Done at the left — or in Customize ▸ Settings ▸ History."),
            Item(title: "Words on the dials",
                 detail: "Over the speed: Auto, Manual, Resting, At max or Off; over the degrees: Cool, Warm or Hot. Held by hand, click Manual to give the fans back to macOS.",
                 isChange: true),
            Item(title: "Smoother and lighter",
                 detail: "The graph glides at each reading instead of jumping, and the dials' glides run on the window server: the app itself spends about a quarter of the energy on Fan Control it did.",
                 isChange: true),
            Item(title: "A size for each page",
                 detail: "Settings ▸ Widgets ▸ Size sets the page it shows, not all of them; Apply to All Pages gives that size to every page.",
                 isChange: true),
            Item(title: "Usage by App",
                 detail: "A new battery widget: which apps used the most battery today, or on the day picked in Daily Usage. Its rows add up to the day's own figure; measured while on battery."),
            Item(title: "Battery Chart",
                 detail: "Its percentages and the hours (00, 06, 12, 18, 24) are written at every size.",
                 isChange: true),
        ],
        fixed: [
            Item(title: "Battery Chart's 0 and 100 %",
                 detail: "They sat half a line inside the chart; they are on their lines now."),
            Item(title: "Links to your own pages",
                 detail: "notchisland://open?page= opened nothing for a page you added."),
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
