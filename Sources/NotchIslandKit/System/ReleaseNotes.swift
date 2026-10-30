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
        version: "0.8.7",
        new: [
            Item(title: "About a quarter of the memory",
                 detail: "At rest NotchIsland now takes about 47 MB, down from about 190 MB in 0.8.6.",
                 isChange: true),
            Item(title: "Settings loads page by page",
                 detail: "Only General is in memory. Any other page loads when you go to it and is emptied one minute after you leave it, even while Settings stays open on another page.",
                 isChange: true),
            Item(title: "Replace macOS Spotlight decides what stays",
                 detail: "On: the app gallery, icons and lists stay in memory, so Spotlight opens full every time. Off: all of it is freed at once. On again: it is read ahead again without a restart.",
                 isChange: true),
            Item(title: "Window Anchor at 60 frames a second",
                 detail: "The live copy runs at your screen's rate and stays on every space, over full-screen apps too. A still window costs 2 mW instead of about 33 mW."),
            Item(title: "Settings opens on General",
                 detail: "From the gear or the menu it starts on General, not on the page you last visited. Page titles line up with the sidebar and pages scroll on under them.",
                 isChange: true),
            Item(title: "Lower energy at rest",
                 detail: "Once nobody is at the Mac, the clipboard is checked every 30 seconds: 17 % less energy at rest than 0.8.6.",
                 isChange: true),
        ],
        fixed: [
            Item(title: "Siri AI opening NotchIsland",
                 detail: "Opening Siri AI or starting a chat in it could bring up NotchIsland's Settings."),
            Item(title: "Freezes while asking Siri AI",
                 detail: "Talking to Siri AI and checking the clipboard no longer wait on the main thread, and reading an answer takes 35 system calls per look instead of 919."),
            Item(title: "False alarms in diagnostics",
                 detail: "Normal use and planned work are no longer reported as unusual behaviour, and a false \"Settings cannot be seen\" report is gone."),
        ],
        known: [
            Item(title: "Pages load when you go to them",
                 detail: "The first visit to Widgets, or a visit more than a minute after leaving it, builds the page again, so it takes a moment longer."),
            Item(title: "Settings' pictures show one island",
                 detail: "The photographs were taken on one Mac: the island in them has that Mac's width, not yours."),
            Item(title: "Fan Control on M1–M4",
                 detail: "Tried on an M5 MacBook Pro only. If the fans do not follow the dial, or do not stay where it was set, send a report from About."),
            Item(title: "A fan held still",
                 detail: "With the fans stopped the chip gets hot under load and macOS slows it down. Click Manual for automatic before heavy work."),
        ])
}
