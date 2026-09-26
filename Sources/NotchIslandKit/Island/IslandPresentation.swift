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
    case power(PowerEvent)
    case timerFinished
    /// A file drag is in progress somewhere on screen.
    case dropTarget
    /// Headphones connected: their picture, name and batteries.
    case airPods(AirPodsInfo)
}

nonisolated extension BannerKind {
    /// The level a volume or brightness banner shows, in either style.
    var levelKind: LevelKind? {
        switch self {
        case .level(let kind), .levelPill(let kind): kind
        default: nil
        }
    }
}

nonisolated enum CompactActivity: Sendable, Equatable {
    case timer
    case stopwatch
    case nowPlaying
}

nonisolated enum ExpandedPage: String, Sendable, Equatable, CaseIterable, Identifiable {
    case home
    case shelf
    case timer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .timer: "Timer"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .shelf: "tray"
        case .timer: "timer"
        }
    }
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

    /// The field and every suggestion (Applications, Files, Actions, Clipboard).
    static let suggestions = AssistantRoom.rows(AssistantCategory.allCases.count)

    static let allCases: [AssistantRoom] = [.field, .suggestions, .list, .gallery]

    private var rank: Double {
        switch self {
        case .field: 0
        case .rows(let count): 1 + Double(min(max(count, 0), 999)) / 1000
        case .list: 2
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

    var isCompact: Bool {
        if case .compact = self { return true }
        return false
    }

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
        case .banner(.power):
            "banner.power"
        case .banner(.timerFinished):
            "banner.timerFinished"
        case .banner(.dropTarget):
            "banner.dropTarget"
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
