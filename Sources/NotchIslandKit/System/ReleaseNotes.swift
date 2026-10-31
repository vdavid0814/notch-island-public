import SwiftUI

/// What a version brought, for the page shown in the notch after an update (`WhatsNewPage`): its
/// features, performance (with the largest numbers), fixes and what is good to know. Written with each release,
/// with the `whats-new` skill; the page shows only the notes of the version that runs
/// (`AppUpdater.current`).
nonisolated struct ReleaseNotes: Sendable {
    enum Section: String, CaseIterable, Identifiable, Sendable {
        case new, performance, fixed, known

        var id: String { rawValue }

        var title: String {
            switch self {
            case .new: String(localized: "Features")
            case .performance: String(localized: "Performance")
            case .fixed: String(localized: "Fixes")
            case .known: String(localized: "Good to Know")
            }
        }
    }

    /// A large number at the top of Performance (three, one row).
    struct Stat: Identifiable, Sendable {
        var title: String
        var symbol: String
        var tint: Color
        var value: String
        var detail: String

        var id: String { title }
    }

    typealias Item = InfoCard

    var version: String
    var stats: [Stat] = []
    var new: [Item]
    var performance: [Item] = []
    var fixed: [Item]
    var known: [Item]

    func items(_ section: Section) -> [Item] {
        switch section {
        case .new: new
        case .performance: performance
        case .fixed: fixed
        case .known: known
        }
    }

    /// A row of the page: a large number's card fits, and three lines of text.
    static let rowHeight: CGFloat = 160

    /// The cards a topic may have, the only ones that fill their rows: 2×2, 3×2, 4×2, 3×3, 4×3. Asked
    /// for: at least 4, at most 12, always even and square with the window (`InfoCardGrid`).
    static let allowedCounts: Set<Int> = [4, 6, 8, 9, 12]

    /// Its cards, Performance's large numbers among them.
    func cardCount(_ section: Section) -> Int {
        items(section).count + (section == .performance ? stats.count : 0)
    }

    /// Cards in each of its rows. Performance's numbers are three in a row, the rest under them too.
    func columns(_ section: Section) -> Int {
        if section == .performance, !stats.isEmpty { return 3 }
        return switch cardCount(section) {
        case 4: 2
        case 8, 12: 4
        default: 3
        }
    }

    /// Its rows: the window is as high as they are (`IslandLayout.size(for:)`).
    func rows(_ section: Section) -> Int {
        (cardCount(section) + columns(section) - 1) / columns(section)
    }

    /// `rows` together, with the gaps between them (`InfoRow.spacing`).
    static func cardsHeight(rows: Int) -> CGFloat {
        let rows = CGFloat(rows)
        return rows * rowHeight + max(0, rows - 1) * 12
    }

    /// The sections with anything in them.
    var sections: [Section] { Section.allCases.filter { !items($0).isEmpty } }

    static let current = ReleaseNotes(
        version: "0.8.8",
        stats: [
            Stat(title: String(localized: "Memory at rest"), symbol: "moon.fill", tint: .indigo, value: "≈ 48 MB",
                 detail: String(localized: "In 0.8.6 it was about 190 MB.")),
            Stat(title: String(localized: "Window Anchor"), symbol: "macwindow", tint: .teal, value: "60 fps",
                 detail: String(localized: "In 0.8.6 it was 15–30.")),
            Stat(title: String(localized: "Energy at rest"), symbol: "leaf.fill", tint: .green, value: "−17 %",
                 detail: String(localized: "Against 0.8.6, while you're away.")),
        ],
        new: [
            Item(symbol: "square.and.arrow.down.fill", tint: .blue, title: String(localized: "Save App Settings"),
                 detail: String(localized: "Keep all your settings in one click, and open them again from General.")),
            Item(symbol: "info.circle.fill", tint: .cyan, title: String(localized: "How It Works"),
                 detail: String(localized: "A new page in About: what it uses, why so little, and what it can do.")),
            Item(symbol: "sparkles", tint: .yellow, title: String(localized: "A new What's New"),
                 detail: String(localized: "Cards by topic, on your island's own surface. Opens nicely from Settings.")),
            Item(symbol: "square.grid.2x2.fill", tint: .indigo, title: String(localized: "Gallery sections"),
                 detail: String(localized: "Your recent apps on top, in the middle, then every app by name.")),
            Item(symbol: "paintbrush.fill", tint: .pink, title: String(localized: "Icons that match"),
                 detail: String(localized: "Spotlight's own icons follow your Clear, Dark or Tinted icon style.")),
            Item(symbol: "slider.horizontal.below.rectangle", tint: .purple, title: String(localized: "Spotlight your size"),
                 detail: String(localized: "Width and icon size are sliders now, with a live picture of the result.")),
            Item(symbol: "arrow.up.and.down", tint: .teal, title: String(localized: "Move window up"),
                 detail: String(localized: "Rest on an anchored window's top edge, then drag its tab up or down.")),
            Item(symbol: "macwindow", tint: .mint, title: String(localized: "Anchor controls"),
                 detail: String(localized: "The anchored window's name and Release are always beside the notch.")),
            Item(symbol: "music.note", tint: .red, title: String(localized: "Now Playing width"),
                 detail: String(localized: "The picture in Settings follows the slider as you drag it.")),
            Item(symbol: "textformat", tint: .orange, title: String(localized: "Cleaner text"),
                 detail: String(localized: "Grey text no longer has an outline around it.")),
            Item(symbol: "gearshape.fill", tint: .gray, title: String(localized: "A simpler Settings"),
                 detail: String(localized: "Fewer switches to go through. Your choices stay as you set them.")),
            Item(symbol: "arrow.triangle.2.circlepath", tint: .green, title: String(localized: "Automatic updates"),
                 detail: String(localized: "NotchIsland now looks for a new version twice a day.")),
        ],
        performance: [
            Item(symbol: "pause.rectangle.fill", tint: .teal, title: String(localized: "Still windows save energy"),
                 detail: String(localized: "An anchored window that isn't moving takes about 2 mW, down from about 33.")),
            Item(symbol: "text.bubble.fill", tint: .purple, title: String(localized: "Lighter Siri AI answers"),
                 detail: String(localized: "Reading an answer takes about 25 times less work than before.")),
            Item(symbol: "memorychip.fill", tint: .orange, title: String(localized: "Calmer on low memory"),
                 detail: String(localized: "After a memory warning, Settings waits longer before it prepares itself again.")),
        ],
        fixed: [
            Item(symbol: "sparkles", tint: .indigo, title: String(localized: "Siri AI opened Settings"),
                 detail: String(localized: "Opening Siri AI or starting a chat could bring up NotchIsland's Settings.")),
            Item(symbol: "hourglass", tint: .yellow, title: String(localized: "Freezes while asking Siri AI"),
                 detail: String(localized: "Waiting for Siri AI could hold up the island. It now waits in the background.")),
            Item(symbol: "list.clipboard.fill", tint: .gray, title: String(localized: "Freezes from the clipboard"),
                 detail: String(localized: "Checking what you copied could hold up the island. That's in the background too.")),
            Item(symbol: "cursorarrow.click.2", tint: .teal, title: String(localized: "Buttons in saved lists"),
                 detail: String(localized: "Open and Delete did nothing in Open Notch Styles.")),
            Item(symbol: "arrow.triangle.2.circlepath", tint: .orange, title: String(localized: "Settings rebuilt over and over"),
                 detail: String(localized: "On low memory it could prepare itself and be dropped again and again.")),
            Item(symbol: "stethoscope", tint: .mint, title: String(localized: "False alarms in reports"),
                 detail: String(localized: "Using the island normally no longer shows up as unusual behaviour.")),
        ],
        known: [
            Item(symbol: "clock.fill", tint: .orange, title: String(localized: "Pages take a moment"),
                 detail: String(localized: "A page loads again if you left it over a minute ago, so it takes a little longer to appear.")),
            Item(symbol: "memorychip.fill", tint: .blue, title: String(localized: "Some memory stays"),
                 detail: String(localized: "About 30 MB stays after you first open Widgets, until you quit. It doesn't keep growing.")),
            Item(symbol: "magnifyingglass", tint: .purple, title: String(localized: "Spotlight off opens slower"),
                 detail: String(localized: "With nothing kept ready, it reads your apps and icons as it opens.")),
            Item(symbol: "arrow.clockwise", tint: .green, title: String(localized: "Opening settings restarts"),
                 detail: String(localized: "Opening saved App Settings restarts NotchIsland for a moment.")),
            Item(symbol: "photo.fill", tint: .gray, title: String(localized: "Pictures show one Mac"),
                 detail: String(localized: "The island in Settings' photos may be wider or narrower than yours.")),
            Item(symbol: "fan.fill", tint: .mint, title: String(localized: "Fan Control"),
                 detail: String(localized: "Only tried on an M5 MacBook Pro. With the fans stopped, the chip gets hot under load.")),
        ])
}
