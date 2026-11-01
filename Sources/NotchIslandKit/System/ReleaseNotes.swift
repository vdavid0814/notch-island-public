import SwiftUI

/// What a version brought, for the page shown in the notch after an update (`WhatsNewPage`): first its
/// highlights in pictures, then its features, performance (with the largest numbers), fixes and what is good
/// to know. Written with each release,
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

    /// A tile of the first page (`WhatsNewHighlights`): a picture drawn from what it says, and its title.
    struct Highlight: Identifiable, Sendable {
        /// What the tile draws. Only from what is true of the version: its numbers measured, its symbols
        /// those of its cards.
        enum Visual: Sendable {
            /// Glossy symbols side by side, the middle one largest.
            case bubbles([Bubble])
            /// A large number in a ring filled to `fraction`, a short line under it.
            case gauge(value: String, unit: String, fraction: Double, tint: Color, note: String = "")
            /// Bars side by side, before and after: each with its value over it and its version under it.
            case bars([Bar])
            /// Small symbols going into one: several things kept as one.
            case flow([Bubble], into: Bubble)
            /// One symbol in the three icon styles of macOS: Clear, Dark and Tinted.
            case iconStyles(String, tint: Color)
            /// One large symbol, smaller ones around it.
            case orbit(Bubble, around: [Bubble])
        }

        struct Bubble: Sendable {
            var symbol: String
            var tint: Color
        }

        struct Bar: Sendable {
            var label: String
            var value: String
            var amount: Double
            var tint: Color
        }

        var title: String
        var visual: Visual

        var id: String { title }
    }

    typealias Item = InfoCard

    var version: String
    /// One line under the title of the first page.
    var summary = ""
    /// The first page's tiles: none, or exactly `highlightSlots`; with none it opens on the cards.
    var highlights: [Highlight] = []
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

    /// A row of the page: a large number's card fits, and three lines of text. Four rows (16 cards) are
    /// lower, so the window doesn't take the whole screen: their cards have three lines at most.
    static func rowHeight(rows: Int) -> CGFloat { rows >= 4 ? 132 : 160 }

    /// The cards a topic may have, the only ones that fill their rows: 2×2, 3×2, 4×2, 3×3, 4×3, 4×4. Asked
    /// for: at least 4, at most 15 and `manyMore`, always even and square with the window (`InfoCardGrid`).
    static let allowedCounts: Set<Int> = [4, 6, 8, 9, 12, 16]

    /// The last of 16 cards: a topic says at most 15 things itself.
    static let manyMore = Item(symbol: "ellipsis.circle.fill", tint: .white, title: String(localized: "And many more…"),
                               detail: String(localized: "Smaller changes all over. Look around Settings to find them."))

    /// The first page's tiles, in the order they are laid out: the left column's two, the wide one over
    /// the title, the two under it, the right column's two (`WhatsNewHighlights`).
    static let highlightSlots = 7

    /// The first page is as high as three rows of cards.
    static let highlightRows = 3

    /// Its cards, Performance's large numbers among them.
    func cardCount(_ section: Section) -> Int {
        items(section).count + (section == .performance ? stats.count : 0)
    }

    /// Cards in each of its rows. Performance's numbers are three in a row, the rest under them too.
    func columns(_ section: Section) -> Int {
        if section == .performance, !stats.isEmpty { return 3 }
        return switch cardCount(section) {
        case 4: 2
        case 8, 12, 16: 4
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
        return rows * rowHeight(rows: Int(rows)) + max(0, rows - 1) * 12
    }

    /// The sections with anything in them.
    var sections: [Section] { Section.allCases.filter { !items($0).isEmpty } }

    static let current = ReleaseNotes(
        version: "0.8.9.1",
        summary: String(localized: "See what fills your disk, System Data's hidden places too, and clear what's safe to the Trash."),
        highlights: [
            Highlight(title: String(localized: "Storage"), visual: .orbit(.init(symbol: "internaldrive.fill", tint: .blue), around: [
                .init(symbol: "checkmark.circle.fill", tint: .green),
                .init(symbol: "exclamationmark.triangle.fill", tint: .orange),
                .init(symbol: "hand.raised.fill", tint: .gray),
                .init(symbol: "person.crop.circle.fill", tint: .blue),
            ])),
            Highlight(title: String(localized: "Hidden System Data"), visual: .bubbles([
                .init(symbol: "clock.arrow.circlepath", tint: .teal),
                .init(symbol: "square.and.arrow.down.on.square.fill", tint: .gray),
                .init(symbol: "shippingbox.fill", tint: .indigo),
            ])),
            Highlight(title: String(localized: "What fills System Data"), visual: .bubbles([
                .init(symbol: "archivebox.fill", tint: .orange),
                .init(symbol: "shippingbox.fill", tint: .purple),
                .init(symbol: "message.fill", tint: .green),
                .init(symbol: "hammer.fill", tint: .blue),
                .init(symbol: "doc.text.fill", tint: .gray),
                .init(symbol: "trash.fill", tint: .red),
            ])),
            Highlight(title: String(localized: "Clear to the Trash"), visual: .flow([
                .init(symbol: "archivebox.fill", tint: .orange),
                .init(symbol: "doc.text.fill", tint: .gray),
                .init(symbol: "message.fill", tint: .green),
            ], into: .init(symbol: "trash.fill", tint: .red))),
            Highlight(title: String(localized: "Disk measured"), visual: .gauge(value: "16", unit: "s", fraction: 0.27, tint: .green,
                                                                               note: String(localized: "about 200 GB"))),
            Highlight(title: String(localized: "A new What's New"), visual: .bubbles([
                .init(symbol: "chart.bar.fill", tint: .indigo),
                .init(symbol: "sparkles", tint: .yellow),
                .init(symbol: "square.grid.2x2.fill", tint: .blue),
            ])),
            Highlight(title: String(localized: "Full Disk Access"), visual: .bubbles([
                .init(symbol: "accessibility", tint: .blue),
                .init(symbol: "lock.open.fill", tint: .gray),
                .init(symbol: "keyboard.fill", tint: .gray),
            ])),
        ],
        stats: [
            Stat(title: String(localized: "Disk measured"), symbol: "timer", tint: .green, value: "15–17 s",
                 detail: String(localized: "About 200 GB, on a MacBook Pro M5.")),
            Stat(title: String(localized: "Energy to measure"), symbol: "leaf.fill", tint: .green, value: "9–13 J",
                 detail: String(localized: "For all of it, once.")),
            Stat(title: String(localized: "Shown again at once"), symbol: "bolt.fill", tint: .yellow, value: "10 min",
                 detail: String(localized: "Opened again within it, nothing is measured.")),
        ],
        new: [
            Item(symbol: "internaldrive.fill", tint: .blue, title: String(localized: "What fills your disk"),
                 detail: String(localized: "A new page in About shows what takes your Mac's storage, System Data most of all.")),
            Item(symbol: "checkmark.circle.fill", tint: .green, title: String(localized: "What's safe to delete"),
                 detail: String(localized: "Every place says plainly: safe to delete, you'd notice, or leave alone.")),
            Item(symbol: "square.and.arrow.down.on.square.fill", tint: .gray, title: String(localized: "Hidden System Data"),
                 detail: String(localized: "macOS downloads, Simulator runtimes, temporary files and swap, each explained.")),
            Item(symbol: "clock.arrow.circlepath", tint: .teal, title: String(localized: "Backup snapshots"),
                 detail: String(localized: "Time Machine's copies kept on the Mac are counted. Disk Utility opens to remove them.")),
            Item(symbol: "shippingbox.fill", tint: .indigo, title: String(localized: "Apps' own data"),
                 detail: String(localized: "Large folders apps keep, Docker's and virtual machines' disks too, by the app's name.")),
            Item(symbol: "trash.fill", tint: .red, title: String(localized: "Clear to the Trash"),
                 detail: String(localized: "Move a place to the Trash right on its card. Only Empty Trash deletes for good.")),
            Item(symbol: "lock.open.fill", tint: .gray, title: String(localized: "Your files counted"),
                 detail: String(localized: "With Full Disk Access, now beside the other permissions, your own folders are measured too.")),
            Item(symbol: "circle.dotted", tint: .green, title: String(localized: "Loading in the notch"),
                 detail: String(localized: "While the disk is measured, a green line round the notch shows how far it is.")),
            Item(symbol: "sparkles", tint: .yellow, title: String(localized: "A new What's New"),
                 detail: String(localized: "This page opens on the highlights. More Details leads to every change.")),
        ],
        performance: [
            Item(symbol: "cpu", tint: .green, title: String(localized: "On the energy-saving cores"),
                 detail: String(localized: "Measuring runs in the background, on the Mac's most frugal cores.")),
            Item(symbol: "stop.circle.fill", tint: .orange, title: String(localized: "Stops when you leave"),
                 detail: String(localized: "Close the page and the measuring stops. Nothing runs while it's closed.")),
            Item(symbol: "ellipsis", tint: .mint, title: String(localized: "Calm Loading dots"),
                 detail: String(localized: "The dots come and go in steps, so the screen isn't redrawn all the time.")),
        ],
        fixed: [],
        known: [
            Item(symbol: "lock.fill", tint: .gray, title: String(localized: "Your folders need access"),
                 detail: String(localized: "Without Full Disk Access, your folders and apps' containers aren't measured.")),
            Item(symbol: "clock.arrow.circlepath", tint: .teal, title: String(localized: "Snapshot sizes unknown"),
                 detail: String(localized: "Only Disk Utility shows how much Time Machine's snapshots take.")),
            Item(symbol: "hand.raised.fill", tint: .gray, title: String(localized: "Some stays unexplained"),
                 detail: String(localized: "What only macOS can read stays under Everything else.")),
            Item(symbol: "clock.fill", tint: .orange, title: String(localized: "Measuring takes a moment"),
                 detail: String(localized: "About 15 seconds on a full disk. Opened again within 10 minutes, it shows at once.")),
            Item(symbol: "trash.fill", tint: .red, title: String(localized: "Empty Trash is for good"),
                 detail: String(localized: "Everything else goes to the Trash first. Emptying it can't be undone.")),
            Item(symbol: "chart.bar.fill", tint: .indigo, title: String(localized: "Sizes differ a little"),
                 detail: String(localized: "System Settings counts some places in other rows, so its numbers won't match exactly.")),
            Item(symbol: "clock.arrow.2.circlepath", tint: .orange, title: String(localized: "Pages take a moment"),
                 detail: String(localized: "A page loads again if you left it over a minute ago, so it takes a little longer to appear.")),
            Item(symbol: "memorychip.fill", tint: .blue, title: String(localized: "Some memory stays"),
                 detail: String(localized: "About 30 MB stays after you first open Widgets, until you quit. It doesn't keep growing.")),
            Item(symbol: "fan.fill", tint: .mint, title: String(localized: "Fan Control"),
                 detail: String(localized: "Only tried on an M5 MacBook Pro. With the fans stopped, the chip gets hot under load.")),
        ])
}
