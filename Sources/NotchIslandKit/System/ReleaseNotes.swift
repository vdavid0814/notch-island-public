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
        version: "0.9.1",
        summary: String(localized: "Usage and Energy for each app, a new song's title in the notch, Listen Again, and the island on a monitor."),
        highlights: [
            Highlight(title: String(localized: "A new song's title"), visual: .bubbles([
                .init(symbol: "music.note.list", tint: .pink),
                .init(symbol: "play.rectangle.fill", tint: .red),
                .init(symbol: "text.line.first.and.arrowtriangle.forward", tint: .orange),
            ])),
            Highlight(title: String(localized: "Listen Again"), visual: .orbit(.init(symbol: "arrow.counterclockwise.circle.fill", tint: .pink), around: [
                .init(symbol: "music.note", tint: .pink),
                .init(symbol: "person.fill", tint: .gray),
                .init(symbol: "opticaldisc.fill", tint: .orange),
            ])),
            Highlight(title: String(localized: "The island on a monitor"), visual: .bubbles([
                .init(symbol: "laptopcomputer", tint: .gray),
                .init(symbol: "display", tint: .blue),
                .init(symbol: "display.2", tint: .indigo),
                .init(symbol: "minus", tint: .gray),
            ])),
            Highlight(title: String(localized: "Opening and closing"), visual: .bars([
                .init(label: "0.8.9.1", value: "733 mJ", amount: 733, tint: .gray),
                .init(label: "0.9", value: "693 mJ", amount: 693, tint: .green)])),
            Highlight(title: String(localized: "Usage adds up"), visual: .flow([
                .init(symbol: "app.fill", tint: .blue),
                .init(symbol: "gearshape.2.fill", tint: .gray),
            ], into: .init(symbol: "battery.75percent", tint: .green))),
            Highlight(title: String(localized: "Energy per app"), visual: .orbit(.init(symbol: "bolt.fill", tint: .yellow), around: [
                .init(symbol: "app.fill", tint: .blue),
                .init(symbol: "powerplug.fill", tint: .green),
                .init(symbol: "gearshape.2.fill", tint: .gray),
            ])),
            Highlight(title: String(localized: "Asked when plugged in"), visual: .flow([
                .init(symbol: "laptopcomputer", tint: .gray),
                .init(symbol: "display", tint: .blue),
            ], into: .init(symbol: "display.2", tint: .indigo))),
        ],
        stats: [
            Stat(title: String(localized: "Opening and closing"), symbol: "leaf.fill", tint: .green, value: "693 mJ",
                 detail: String(localized: "Six times, measured. It was 733 mJ.")),
            Stat(title: String(localized: "At rest"), symbol: "moon.fill", tint: .indigo, value: "0.28–0.35",
                 detail: String(localized: "Energy Impact with nothing to show, as before.")),
            Stat(title: String(localized: "Passing the notch"), symbol: "cursorarrow.motionlines", tint: .teal, value: "13–16 mJ",
                 detail: String(localized: "Six passes, about as before.")),
        ],
        new: [
            Item(symbol: "bolt.fill", tint: .yellow, title: String(localized: "Energy per app"),
                 detail: String(localized: "The energy each app used today, on battery or plugged in, in watt-hours.")),
            Item(symbol: "list.bullet.rectangle.fill", tint: .green, title: String(localized: "Usage or Energy"),
                 detail: String(localized: "Click the title of Usage by App to switch between the two. It stays as you leave it.")),
            Item(symbol: "music.note.list", tint: .pink, title: String(localized: "A new song's title"),
                 detail: String(localized: "When the next song or video starts, its title drops under the notch in its cover's colour.")),
            Item(symbol: "text.line.first.and.arrowtriangle.forward", tint: .orange, title: String(localized: "Long titles glide"),
                 detail: String(localized: "A title too long for it stands still for half a second, then glides through once.")),
            Item(symbol: "slider.horizontal.3", tint: .gray, title: String(localized: "Its size and time"),
                 detail: String(localized: "Live Activities ▸ New Track sets how large it is and how long it stays, with a moving picture.")),
            Item(symbol: "arrow.counterclockwise.circle.fill", tint: .pink, title: String(localized: "Listen Again"),
                 detail: String(localized: "With nothing playing, Now Playing shows the last song from Music: cover, title and artist.")),
            Item(symbol: "music.note", tint: .red, title: String(localized: "Straight to the song"),
                 detail: String(localized: "Listen Again opens Music right at that song, without playing it. It can be turned off in General.")),
            Item(symbol: "display", tint: .blue, title: String(localized: "Pick its screen"),
                 detail: String(localized: "Automatic, the MacBook or a monitor, in Live Activities ▸ Displays.")),
            Item(symbol: "display.2", tint: .indigo, title: String(localized: "Plug-in notice"),
                 detail: String(localized: "Plug a monitor in and the notch asks where the island should live.")),
            Item(symbol: "speaker.wave.2.fill", tint: .cyan, title: String(localized: "Volume in Settings"),
                 detail: String(localized: "With Settings open, volume and brightness now show beside the notch.")),
            Item(symbol: "minus", tint: .gray, title: String(localized: "No notch? A line"),
                 detail: String(localized: "On a monitor or a MacBook Air M1, a faint line shows where the island comes out.")),
            Item(symbol: "switch.2", tint: .green, title: String(localized: "Tidier Settings"),
                 detail: String(localized: "Settings' sections start with the switch and its picture. Options fold away while it's off.")),
        ],
        performance: [
            Item(symbol: "wand.and.rays", tint: .orange, title: String(localized: "Titles glide for free"),
                 detail: String(localized: "macOS draws the title's glide, so the app does no work while it moves.")),
            Item(symbol: "photo.fill", tint: .pink, title: String(localized: "Covers when shown"),
                 detail: String(localized: "Listen Again's cover is only read when Now Playing shows it.")),
            Item(symbol: "eye.slash.fill", tint: .indigo, title: String(localized: "A quieter panel at rest"),
                 detail: String(localized: "The panel kept ready draws nothing while closed, so openings cost a little less.")),
        ],
        fixed: [
            Item(symbol: "battery.75percent", tint: .green, title: String(localized: "Usage adds up"),
                 detail: String(localized: "An app could show more of the battery than the whole day used. Now the apps add up to it.")),
            Item(symbol: "powerplug.fill", tint: .green, title: String(localized: "Days on the charger"),
                 detail: String(localized: "A day spent plugged in could list apps with percents. Now it says Nothing counted.")),
            Item(symbol: "rectangle.fill", tint: .gray, title: String(localized: "A black notch on a monitor"),
                 detail: String(localized: "On a screen without a notch, a black shape could stay at the top while the island was closed.")),
            Item(symbol: "scroll.fill", tint: .blue, title: String(localized: "Two scroll bars"),
                 detail: String(localized: "With a mouse connected, Settings' pages could show two scroll bars.")),
        ],
        known: [
            Item(symbol: "bolt.fill", tint: .yellow, title: String(localized: "Energy from today"),
                 detail: String(localized: "Energy per app is counted from this version on. Earlier days show Nothing counted.")),
            Item(symbol: "gearshape.2.fill", tint: .gray, title: String(localized: "macOS reads low"),
                 detail: String(localized: "The window server and other system parts can't be measured, so macOS reads low.")),
            Item(symbol: "chart.bar.fill", tint: .green, title: String(localized: "Earlier days scaled"),
                 detail: String(localized: "Days counted wrong before keep each app's share, scaled to what the day used.")),
            Item(symbol: "music.note", tint: .pink, title: String(localized: "Music only"),
                 detail: String(localized: "Listen Again offers songs played in Music, not Spotify or videos.")),
            Item(symbol: "magnifyingglass", tint: .gray, title: String(localized: "Not in your library?"),
                 detail: String(localized: "A song you only streamed opens as a search in Music.")),
            Item(symbol: "play.rectangle.fill", tint: .red, title: String(localized: "No full screen"),
                 detail: String(localized: "A new title doesn't appear while a video plays in full screen.")),
            Item(symbol: "clock.fill", tint: .orange, title: String(localized: "A longer page"),
                 detail: String(localized: "Live Activities has more on it, so its first opening each visit takes a little longer.")),
            Item(symbol: "display.2", tint: .indigo, title: String(localized: "After waking"),
                 detail: String(localized: "No monitor notice for 15 seconds after the Mac wakes.")),
            Item(symbol: "arrow.right.square.fill", tint: .blue, title: String(localized: "After Settings"),
                 detail: String(localized: "A screen picked in Settings is moved to once Settings closes.")),
            Item(symbol: "lock.fill", tint: .gray, title: String(localized: "Folder access"),
                 detail: String(localized: "Without Full Disk Access, your folders and apps' containers aren't measured.")),
            Item(symbol: "trash.fill", tint: .red, title: String(localized: "Empty Trash"),
                 detail: String(localized: "Everything else goes to the Trash first. Emptying it can't be undone.")),
            Item(symbol: "fan.fill", tint: .mint, title: String(localized: "Fan Control"),
                 detail: String(localized: "Only tried on an M5 MacBook Pro. With the fans stopped, the chip gets hot under load.")),
        ])
}
