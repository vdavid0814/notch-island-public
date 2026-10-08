import Synchronization
import Foundation

// The island's vocabulary.
//
// A presentation names the *kind* of thing on screen and nothing else. Data —
// a volume level, a track title, a battery percentage — lives in the feature
// stores and is read by the views directly. That split is what keeps a volume
// key press from being a state transition: the level changes, the presentation
// does not, so the window is not re-staged and no spring restarts.

nonisolated enum LevelKind: String, Sendable, Equatable, CaseIterable {
    case volume
    case brightness
}

nonisolated enum PowerEvent: Sendable, Equatable {
    /// The charger was plugged in.
    case connected
    /// The charger was removed.
    case disconnected
    /// Reached full charge while plugged in.
    case charged
    /// Crossed one of the low thresholds downward while on battery.
    case low(threshold: Int)
}

nonisolated enum BannerKind: Sendable, Equatable {
    case level(LevelKind)
    /// The minimal level style (`LevelHUDStyle.pill`): beside the notch only, pill-sized.
    case levelPill(LevelKind)
    /// A volume change made on the headphones (an AirPods stem swipe): macOS then draws its own
    /// volume card under the notch (MenuBarAgent, a 352 × 148 window at the pop-up menu level), which
    /// no key tap can stop. The level banner is drawn at the AirPods card's size above it instead.
    case levelCovering(LevelKind)
    case power(PowerEvent)
    case timerFinished
    /// A file drag is in progress somewhere on screen.
    case dropTarget
    /// A window is being dragged to the notch: letting go there anchors it.
    case anchorTarget
    /// Headphones connected: their picture, name and batteries.
    case airPods(AirPodsInfo)
}

nonisolated extension BannerKind {
    /// A level banner over macOS's own volume card.
    var isCovering: Bool {
        if case .levelCovering = self { true } else { false }
    }

    /// The level a volume or brightness banner shows, in either style.
    var levelKind: LevelKind? {
        switch self {
        case .level(let kind), .levelPill(let kind), .levelCovering(let kind): kind
        default: nil
        }
    }
}

nonisolated enum CompactActivity: Sendable, Equatable {
    case timer
    case stopwatch
    case nowPlaying
    /// The screen is being recorded (`ScreenRecorder`): a red line round the notch, the time in one
    /// ear and a red dot in the other.
    case recording
}

/// A page of the panel: one of the island's own (home, the shelf, the timer, the battery) or one
/// the user added (`CustomPage`, a board of widgets). Named by a string, stored as it: an own page by
/// its name, an added one as `page.<UUID>`.
nonisolated struct ExpandedPage: RawRepresentable, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    let rawValue: String

    init?(rawValue: String) {
        guard Self.allCases.contains(where: { $0.rawValue == rawValue }) || Self.isCustom(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    private init(own name: String) { rawValue = name }

    static let home = ExpandedPage(own: "home")
    static let shelf = ExpandedPage(own: "shelf")
    static let timer = ExpandedPage(own: "timer")
    /// The battery's charge over the day, its health and the adapter (only on a Mac with a battery).
    static let battery = ExpandedPage(own: "battery")
    /// While the screen is recorded, what the pointer over the notch opens instead of the panel: the
    /// time and Stop (`RecordingCard`). Never in the picker, never stored.
    static let recording = ExpandedPage(own: "recording")

    /// The island's own pages, in the panel's order; the user's follow them (`HeaderLayout.customPages`).
    static let allCases: [ExpandedPage] = [.home, .shelf, .timer, .battery]

    /// A new page of the user's.
    static func newCustom() -> ExpandedPage { ExpandedPage(own: customPrefix + UUID().uuidString) }

    private static let customPrefix = "page."
    private static func isCustom(_ name: String) -> Bool {
        name.hasPrefix(customPrefix) && UUID(uuidString: String(name.dropFirst(customPrefix.count))) != nil
    }

    /// One the user added.
    var isCustom: Bool { Self.isCustom(rawValue) }

    /// Drawn as a board of widgets the user arranges: home, the timer's and the battery's, and the
    /// user's own (the shelf is its own).
    var isBoard: Bool { self != .shelf && self != .recording }

    var id: String { rawValue }

    init(from decoder: any Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let page = ExpandedPage(rawValue: name) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown page \(name)"))
        }
        self = page
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .timer: "Timer"
        case .battery: "Battery"
        case .recording: "Recording"
        default: CustomPage.catalog.withLock { $0[self]?.title } ?? "Page"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .shelf: "tray"
        case .timer: "timer"
        case .battery: "battery.100percent"
        case .recording: "record.circle"
        default: CustomPage.catalog.withLock { $0[self]?.symbol } ?? CustomPage.defaultSymbol
        }
    }
}

/// A page the user added to the panel: its name and symbol in the picker; its widgets are its own
/// board (`WidgetPages`).
nonisolated struct CustomPage: Sendable, Hashable, Codable, Identifiable {
    var page: ExpandedPage
    var title: String
    var symbol: String

    var id: ExpandedPage { page }

    static let defaultSymbol = "square.grid.2x2"
    /// At most this many: the picker stays beside the notch.
    static let limit = 3
    /// Symbols offered for one.
    static let symbols = ["square.grid.2x2", "star", "heart", "bolt", "house", "briefcase", "book", "gamecontroller",
                          "music.note", "film", "camera", "paintpalette", "leaf", "flame", "cloud.sun", "moon",
                          "globe", "cart", "chart.bar", "cpu", "keyboard", "headphones", "airplane", "sparkles"]

    /// Every page's name and symbol, for `ExpandedPage.title` wherever it is read: kept by
    /// `HeaderLayout`'s owner (`Preferences`) as the pages change.
    static let catalog = Mutex<[ExpandedPage: CustomPage]>([:])
}

/// How much of the assistant shows, as in the system's Search window: only the field until the
/// pointer comes over it (or ↓), then the suggestions below it; for a query exactly as many rows
/// as it has (up to the full list, which then scrolls); the full list for an open suggestion or an
/// answer; and a larger window for the app gallery.
nonisolated enum AssistantRoom: Sendable, Hashable, Comparable {
    case field
    /// The field and this many rows under it.
    case rows(Int)
    case list
    case gallery
    /// The gallery with only this many rows of apps (a search in it that found a few): not a
    /// full gallery of black space under two apps (seen on video, v0.4.5).
    case galleryRows(Int)

    /// The Applications gallery, full or cut to its rows.
    var isGallery: Bool {
        switch self {
        case .gallery, .galleryRows: true
        default: false
        }
    }

    /// The field and every suggestion (Applications, Files, Actions, Clipboard, System, Windows, Emoji).
    static let suggestions = AssistantRoom.rows(AssistantCategory.allCases.count)

    static let allCases: [AssistantRoom] = [.field, .suggestions, .list, .gallery]

    private var rank: Double {
        switch self {
        case .field: 0
        case .rows(let count): 1 + Double(min(max(count, 0), 999)) / 1000
        case .list: 2
        case .galleryRows(let count): 2.5 + Double(min(max(count, 0), 99)) / 1000
        case .gallery: 3
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

nonisolated enum IslandPresentation: Sendable, Equatable {
    /// Nothing to show: the notch is just the notch.
    case idle
    /// An ongoing activity hugging the notch, never taller than it.
    case compact(CompactActivity)
    /// A transient notice that drops just below the notch.
    case banner(BannerKind)
    /// The full panel the user asked for.
    case expanded(ExpandedPage)
    /// Siri in the notch: search and ask, with the keyboard (`AssistantView`), as tall as what it
    /// shows needs.
    case assistant(AssistantRoom)
    /// Settings, grown out of the notch as a larger window (`IslandSettingsView`).
    case settings

    var isIdle: Bool { self == .idle }

    var isBanner: Bool {
        if case .banner = self { return true }
        return false
    }

    /// Hugs the notch at its height: the compact pill, and the minimal level pill.
    var isPillShaped: Bool {
        if case .compact = self { return true }
        if case .banner(.levelPill) = self { return true }
        return false
    }

    var isExpanded: Bool {
        if case .expanded = self { return true }
        return false
    }

    var isAssistant: Bool {
        if case .assistant = self { return true }
        return false
    }

    var isSettings: Bool { self == .settings }

    /// Takes the keyboard while on screen (typing, arrows, Esc): the assistant and Settings.
    var takesKeyboard: Bool { isAssistant || isSettings }

    /// Open by the user and large: the expanded panel or the assistant. Both keep the band guard's
    /// strip up and end with the close spring.
    var isOpen: Bool { isExpanded || isAssistant || isSettings }

    /// Identity for content transitions. Changes with the kind of content on
    /// screen, never with the data inside it.
    var contentKey: String {
        switch self {
        case .idle:
            "idle"
        case .compact(let activity):
            "compact.\(activity)"
        case .banner(.level(let kind)):
            "banner.level.\(kind.rawValue)"
        case .banner(.levelPill(let kind)):
            "banner.levelPill.\(kind.rawValue)"
        case .banner(.levelCovering(let kind)):
            "banner.levelCovering.\(kind.rawValue)"
        case .banner(.power):
            "banner.power"
        case .banner(.timerFinished):
            "banner.timerFinished"
        case .banner(.dropTarget):
            "banner.dropTarget"
        case .banner(.anchorTarget):
            "banner.anchorTarget"
        case .banner(.airPods):
            "banner.airPods"
        case .expanded(let page):
            "expanded.\(page.rawValue)"
        case .assistant:
            "assistant"
        case .settings:
            "settings"
        }
    }
}
