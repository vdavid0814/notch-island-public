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
    case power(PowerEvent)
    case timerFinished
    /// A file drag is in progress somewhere on screen.
    case dropTarget
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
/// pointer comes over it (or ↓), then the suggestions below it; a full list once there is a query,
/// an open suggestion or an answer.
nonisolated enum AssistantRoom: Int, Sendable, Equatable, Comparable, CaseIterable {
    case field, suggestions, list

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
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

    var isIdle: Bool { self == .idle }

    var isCompact: Bool {
        if case .compact = self { return true }
        return false
    }

    var isBanner: Bool {
        if case .banner = self { return true }
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

    /// Open by the user and large: the expanded panel or the assistant. Both keep the band guard's
    /// strip up and end with the close spring.
    var isOpen: Bool { isExpanded || isAssistant }

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
        case .banner(.power):
            "banner.power"
        case .banner(.timerFinished):
            "banner.timerFinished"
        case .banner(.dropTarget):
            "banner.dropTarget"
        case .expanded(let page):
            "expanded.\(page.rawValue)"
        case .assistant:
            "assistant"
        }
    }
}
