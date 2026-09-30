import CoreGraphics
import Foundation

/// Everything about Siri in the notch the user can tune (Settings ▸ Siri): how it opens, how
/// eagerly it searches and matches, what it lists, where it looks for files, how it answers, and
/// how large its window is. Stored as one JSON value (`ni2.siri`); fields missing from an older
/// value keep their defaults, so adding one never resets the others.
nonisolated struct SiriSettings: Sendable, Equatable, Codable {
    // MARK: Opening

    var shortcut: SiriShortcut = .commandSpace
    /// The shortcut again closes Siri (like the system's Search); off, it only opens.
    var shortcutCloses = true
    /// Two fingers swiped down on the notch (or the wheel turned down over it) open Siri.
    var swipeOpens = true
    /// The suggestions come down under the field while the pointer is over Siri.
    var hoverRevealsSuggestions = true

    // MARK: Search

    /// Seconds after a keystroke before searching; 0 searches on every key.
    var searchDelay = 0.12
    var matching: SiriMatching = .wordStart
    /// Apps and files each shown for a query.
    var resultsPerKind = 3
    var showsApplications = true
    var showsFiles = true
    var showsActions = true
    /// Clipboard (⌘4): the history of copied text. Off, nothing is watched or kept.
    var showsClipboard = true
    /// System (⌘5): the island's commands, Control Center's switches, the Mac's commands and
    /// System Settings' panes.
    var showsSystem = true
    /// Windows (⌘6): the running apps and their windows.
    var showsWindows = true
    var showsEmoji = true

    // MARK: App gallery

    var galleryColumns = 9
    var gallerySort: SiriGallerySort = .recent

    // MARK: Files

    var folders: Set<SiriFolder> = Set(SiriFolder.allCases)
    /// How far back "recent" files go.
    var recentDays = 30

    // MARK: Actions

    var includesIslandActions = true
    var includesShortcuts = true

    // MARK: Answers

    var usesIntelligence = true
    var answerLength: SiriAnswerLength = .brief
    var searchEngine: SiriSearchEngine = .google
    var offersChatGPT = true

    // MARK: Window

    /// Siri's width (the field, the list and the answer).
    var panelSize: SiriPanelSize = .standard
    /// Rows of hits the list shows before it scrolls (also the answer's height).
    var listRows = 7
    /// Rows of apps the gallery shows before it scrolls (its columns set its width).
    var galleryRows = 4

    static let searchDelayRange: ClosedRange<Double> = 0...0.4
    static let resultsRange: ClosedRange<Int> = 1...6
    static let galleryColumnsRange: ClosedRange<Int> = 6...12
    static let recentDayChoices = [7, 30, 90]
    static let listRowsRange: ClosedRange<Int> = 4...10
    static let galleryRowsRange: ClosedRange<Int> = 2...6

    init() {}

    /// The downward scroll, in points, that opens Siri: the lightest flick (the user asked for the
    /// most sensitive setting, with no slider).
    var swipeDistance: CGFloat { 12 }

    // Tolerant decoding: every field optional, clamped.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback }
        let d = SiriSettings()
        shortcut = value(.shortcut, d.shortcut)
        shortcutCloses = value(.shortcutCloses, d.shortcutCloses)
        swipeOpens = value(.swipeOpens, d.swipeOpens)
        hoverRevealsSuggestions = value(.hoverRevealsSuggestions, d.hoverRevealsSuggestions)
        searchDelay = min(max(value(.searchDelay, d.searchDelay), Self.searchDelayRange.lowerBound), Self.searchDelayRange.upperBound)
        matching = value(.matching, d.matching)
        resultsPerKind = min(max(value(.resultsPerKind, d.resultsPerKind), Self.resultsRange.lowerBound), Self.resultsRange.upperBound)
        showsApplications = value(.showsApplications, d.showsApplications)
        showsFiles = value(.showsFiles, d.showsFiles)
        showsActions = value(.showsActions, d.showsActions)
        showsClipboard = value(.showsClipboard, d.showsClipboard)
        showsSystem = value(.showsSystem, d.showsSystem)
        showsWindows = value(.showsWindows, d.showsWindows)
        showsEmoji = value(.showsEmoji, d.showsEmoji)
        galleryColumns = min(max(value(.galleryColumns, d.galleryColumns), Self.galleryColumnsRange.lowerBound), Self.galleryColumnsRange.upperBound)
        gallerySort = value(.gallerySort, d.gallerySort)
        folders = value(.folders, d.folders)
        recentDays = max(1, value(.recentDays, d.recentDays))
        includesIslandActions = value(.includesIslandActions, d.includesIslandActions)
        includesShortcuts = value(.includesShortcuts, d.includesShortcuts)
        usesIntelligence = value(.usesIntelligence, d.usesIntelligence)
        answerLength = value(.answerLength, d.answerLength)
        searchEngine = value(.searchEngine, d.searchEngine)
        offersChatGPT = value(.offersChatGPT, d.offersChatGPT)
        panelSize = value(.panelSize, d.panelSize)
        listRows = min(max(value(.listRows, d.listRows), Self.listRowsRange.lowerBound), Self.listRowsRange.upperBound)
        galleryRows = min(max(value(.galleryRows, d.galleryRows), Self.galleryRowsRange.lowerBound), Self.galleryRowsRange.upperBound)
    }

    /// The part of the settings that sizes Siri's window, for `IslandLayout`.
    var layout: SiriLayout {
        SiriLayout(widthFactor: panelSize.factor, listRows: listRows, galleryRows: galleryRows, galleryColumns: galleryColumns)
    }

    /// The suggestions (⌘1–⌘7) that are switched on, in order.
    var categories: [AssistantCategory] {
        AssistantCategory.allCases.filter {
            switch $0 {
            case .applications: showsApplications
            case .files: showsFiles
            case .actions: showsActions
            case .clipboard: showsClipboard
            case .system: showsSystem
            case .windows: showsWindows
            case .emoji: showsEmoji
            }
        }
    }
}

/// Siri's window proportions (see `IslandLayout.size(for: .assistant)`); the defaults are the sizes
/// Siri had before they could be set.
nonisolated struct SiriLayout: Sendable, Equatable {
    var widthFactor: CGFloat = 1
    var listRows = 7
    var galleryRows = 4
    var galleryColumns = 9
}

nonisolated enum SiriShortcut: String, Sendable, Codable, CaseIterable, Identifiable {
    case commandSpace, optionSpace, controlSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commandSpace: "⌘ Space"
        case .optionSpace: "⌥ Space"
        case .controlSpace: "⌃ Space"
        }
    }

    /// The modifier held with Space (and nothing else).
    var modifiers: CGEventFlags {
        switch self {
        case .commandSpace: .maskCommand
        case .optionSpace: .maskAlternate
        case .controlSpace: .maskControl
        }
    }
}

nonisolated enum SiriMatching: String, Sendable, Codable, CaseIterable, Identifiable {
    /// A word of the name starts with what was typed ("saf" → Safari).
    case wordStart
    /// Anywhere in the name ("far" → Safari).
    case anywhere
    /// Its letters in order, gaps allowed ("sfr" → Safari): forgiving of typos and shorthand.
    case fuzzy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wordStart: "Word Starts"
        case .anywhere: "Anywhere"
        case .fuzzy: "Fuzzy"
        }
    }
}

nonisolated enum SiriGallerySort: String, Sendable, Codable, CaseIterable, Identifiable {
    case recent, name

    var id: String { rawValue }
    var title: String { self == .recent ? "Recently Used" : "Name" }
}

nonisolated enum SiriFolder: String, Sendable, Codable, CaseIterable, Identifiable {
    case desktop, documents, downloads, iCloudDrive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .iCloudDrive: "iCloud Drive"
        }
    }

    var systemImage: String {
        switch self {
        case .desktop: "menubar.dock.rectangle"
        case .documents: "doc.fill"
        case .downloads: "arrow.down.circle.fill"
        case .iCloudDrive: "icloud.fill"
        }
    }

    var path: String {
        switch self {
        case .desktop: NSHomeDirectory() + "/Desktop"
        case .documents: NSHomeDirectory() + "/Documents"
        case .downloads: NSHomeDirectory() + "/Downloads"
        case .iCloudDrive: AssistantSearch.iCloudDrive
        }
    }
}

nonisolated enum SiriAnswerLength: String, Sendable, Codable, CaseIterable, Identifiable {
    case brief, detailed

    var id: String { rawValue }
    var title: String { self == .brief ? "Brief" : "Detailed" }

    var instructions: String {
        switch self {
        case .brief:
            """
            You are Siri, in the notch of the user's Mac. Answer the question directly and briefly, in a \
            few sentences at most, in the same language as the question. No preamble.
            """
        case .detailed:
            """
            You are Siri, in the notch of the user's Mac. Answer the question thoroughly but clearly, with \
            short paragraphs or a list where it helps, in the same language as the question. No preamble.
            """
        }
    }

    var maximumTokens: Int { self == .brief ? 400 : 1200 }
}

nonisolated enum SiriSearchEngine: String, Sendable, Codable, CaseIterable, Identifiable {
    case google, duckDuckGo, bing, ecosia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .ecosia: "Ecosia"
        }
    }

    /// Takes the query as `q`.
    var base: String {
        switch self {
        case .google: "https://www.google.com/search"
        case .duckDuckGo: "https://duckduckgo.com/"
        case .bing: "https://www.bing.com/search"
        case .ecosia: "https://www.ecosia.org/search"
        }
    }
}

nonisolated enum SiriPanelSize: String, Sendable, Codable, CaseIterable, Identifiable {
    case small, standard, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Standard"
        case .large: "Large"
        }
    }

    /// Scales Siri's width on top of the island's own size.
    var factor: CGFloat {
        switch self {
        case .small: 0.85
        case .standard: 1
        case .large: 1.2
        }
    }
}
