import AppKit
import FoundationModels
import NaturalLanguage
import Synchronization
import UniformTypeIdentifiers

/// The suggestions shown before anything is typed, as in the system's Search window: each one
/// lists everything of its kind (⌘1–⌘7) and the field then filters that list.
nonisolated enum AssistantCategory: Int, CaseIterable, Hashable, Sendable {
    case applications = 1, files, actions, clipboard, system, windows, emoji, people

    /// What the user may type to find the suggestion itself: its title, and its English names in
    /// any language (the title is localized).
    var searchNames: [String] {
        let english: [String] = switch self {
        case .applications: ["Applications", "Apps"]
        case .files: ["Files", "Documents"]
        case .actions: ["Actions", "Shortcuts"]
        case .clipboard: ["Clipboard", "Pasteboard", "Copied"]
        case .system: ["System", "Commands", "Control Center"]
        case .windows: ["Windows", "Running Apps", "Switch Apps"]
        case .emoji: ["Emoji", "Emojis", "Smileys"]
        case .people: ["People & Calendar", "People", "Contacts", "Calendar", "Events"]
        }
        let title = switch self {
        case .applications: String(localized: "Applications")
        case .files: String(localized: "Files")
        case .actions: String(localized: "Actions")
        case .clipboard: String(localized: "Clipboard")
        case .system: String(localized: "System")
        case .windows: String(localized: "Windows")
        case .emoji: String(localized: "Emoji")
        case .people: String(localized: "People & Calendar")
        }
        return [title] + english.filter { $0 != title }
    }
}

/// What the assistant can do with the query, in the order its list shows them.
nonisolated enum AssistantRow: Hashable, Identifiable, Sendable {
    case category(AssistantCategory)
    case hit(AssistantHit)
    case action(AssistantAction)
    /// Something the user copied (Clipboard, ⌘4).
    case clip(ClipboardItem)
    /// An island command, a Control Center switch or one of the Mac's (System, ⌘5).
    case command(AssistantCommand)
    /// A System Settings pane (System, ⌘5).
    case settingsPane(SystemSettingsPane)
    /// A running app or one of its windows (Windows, ⌘6).
    case window(AssistantWindow)
    /// Return pastes it, ⌘C copies it (Emoji, ⌘7).
    case emoji(AssistantEmoji)
    /// A sum or a unit conversion worked out from the query (Return copies the result).
    case calculation(AssistantCalculation)
    /// The query's word in the dictionary (Return shows the whole entry).
    case definition(AssistantDefinition)
    /// One of the user's contacts (People & Calendar, ⌘8): Return lists the ways to reach them.
    case contact(AssistantContact)
    case contactAction(ContactAction)
    /// A coming event (⌘8): Return opens Calendar on its day.
    case event(CalendarEvent)
    case bookmark(AssistantBookmark)
    /// Asks macOS for the contacts or the calendar: only ever from this row.
    case permission(AssistantPermission)
    /// The query is a web address: Return opens it.
    case openURL(URL)
    case askIntelligence
    case searchWeb
    case askChatGPT
    /// "se lunch at 1", "sm on my way", "maps cafe": a new email or message with the text, or Maps
    /// looking for it (Spotlight's quick actions).
    case compose(AssistantCompose)
    /// A command in the menu bar of the app the user is in (Return chooses it there).
    case menuItem(AssistantMenuItem)

    var id: String {
        switch self {
        case .category(let category): "category:\(category.rawValue)"
        case .hit(let hit): "hit:\(hit.url.path)"
        case .action(let action): "action:\(action.id)"
        case .clip(let item): "clip:\(item.id)"
        case .command(let command): "command:\(command.id)"
        case .settingsPane(let pane): "pane:\(pane.id)"
        case .window(let window): "window:\(window.id)"
        case .emoji(let emoji): "emoji:\(emoji.id)"
        case .calculation: "calculation"
        case .definition(let definition): "define:\(definition.word)"
        case .contact(let contact): "contact:\(contact.id)"
        case .contactAction(let action): "contactAction:\(action.id)"
        case .event(let event): "event:\(event.id):\(event.start.timeIntervalSinceReferenceDate)"
        case .bookmark(let bookmark): "bookmark:\(bookmark.id)"
        case .permission(let permission): "permission:\(permission.rawValue)"
        case .openURL: "url"
        case .askIntelligence: "ask"
        case .searchWeb: "web"
        case .askChatGPT: "chatgpt"
        case .compose(let compose): "compose:\(compose.kind.rawValue)"
        case .menuItem(let item): "menu:\(item.id)"
        }
    }
}

/// Something the island can do, or one of the user's shortcuts.
nonisolated enum AssistantAction: Hashable, Identifiable, Sendable {
    case island(IslandAction)
    case shortcut(String)

    var id: String {
        switch self {
        case .island(let action): "island:\(action.rawValue)"
        case .shortcut(let name): "shortcut:\(name)"
        }
    }

    var title: String {
        switch self {
        case .island(let action): action.title
        case .shortcut(let name): name
        }
    }
}

nonisolated enum IslandAction: String, CaseIterable, Sendable {
    case play, pause, next, previous, timer, stopwatch, shelf, customize, settings

    var title: String {
        switch self {
        case .play: String(localized: "Play")
        case .pause: String(localized: "Pause")
        case .next: String(localized: "Next Track")
        case .previous: String(localized: "Previous Track")
        case .timer: String(localized: "Timer")
        case .stopwatch: String(localized: "Stopwatch")
        case .shelf: String(localized: "Shelf")
        case .customize: String(localized: "Customize Island")
        case .settings: String(localized: "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .next: "forward.fill"
        case .previous: "backward.fill"
        case .timer: "timer"
        case .stopwatch: "stopwatch"
        case .shelf: "tray.full.fill"
        case .customize: "square.grid.2x2.fill"
        case .settings: "gearshape.fill"
        }
    }

    var command: AppCommand {
        switch self {
        case .play: .media(.play)
        case .pause: .media(.pause)
        case .next: .media(.next)
        case .previous: .media(.previous)
        case .timer: .open(.timer)
        case .stopwatch: .startStopwatch
        case .shelf: .open(.shelf)
        case .customize: .customize
        case .settings: .showSettings
        }
    }
}

/// An answer from Apple Intelligence, as it streams in.
nonisolated struct AssistantAnswer: Sendable, Equatable {
    var question: String
    var text = ""
    var isResponding = true
    var failure: String?
    /// A dictionary's entry rather than Apple Intelligence's answer: the word it defines.
    var definedWord: String?
}

/// Where the assistant's lists come from. Tests use fixed lists: the live ones read Spotlight, which
/// for files means the user's privacy-protected folders.
nonisolated struct AssistantSources: Sendable {
    var apps: @Sendable (_ query: String, _ limit: Int) async -> [AssistantHit]
    var files: @Sendable (_ query: String, _ limit: Int, _ scope: FileScope) async -> [AssistantHit]
    var recentFiles: @Sendable (_ scope: FileScope) async -> [AssistantHit]
    var allApps: @Sendable () async -> [AssistantHit]
    var shortcuts: @Sendable () async -> [String]
    var isUnsupportedLanguage: @Sendable (String) -> Bool
    var settingsPanes: @Sendable () async -> [SystemSettingsPane]
    /// The running apps; with `titles`, as their windows (Accessibility, off the main thread).
    var windows: @Sendable (_ titles: Bool) async -> [AssistantWindow]
    var emoji: @Sendable () async -> [AssistantEmoji]
    var define: @Sendable (String) async -> AssistantDefinition? = { _ in nil }
    var contacts: @Sendable (_ query: String, _ limit: Int) async -> [AssistantContact] = { _, _ in [] }
    var contactsAccess: @Sendable () -> AccessState = { .denied }
    var requestContacts: @Sendable () async -> AccessState = { .denied }
    var bookmarks: @Sendable () async -> [AssistantBookmark] = { [] }
    /// The currencies' rates per euro (fetched at most once a day); nil when they cannot be had.
    var rates: @Sendable () async -> [String: Double]? = { nil }
    /// The menu bar commands of the app with this process id.
    var menuItems: @Sendable (pid_t) async -> [AssistantMenuItem] = { _ in [] }

    static let live = AssistantSources(
        apps: { await AssistantSearch.apps(matching: $0, limit: $1) },
        files: { await AssistantSearch.files(matching: $0, limit: $1, scope: $2) },
        recentFiles: { await AssistantSearch.recentFiles(scope: $0) },
        allApps: { await AssistantSearch.allApps() },
        shortcuts: { await AssistantSearch.shortcuts() },
        isUnsupportedLanguage: { AssistantModel.isUnsupportedLanguage($0) },
        settingsPanes: { await SystemSettingsPane.table() },
        windows: { await RunningWindows.list(titles: $0) },
        emoji: { await EmojiTable.build() },
        define: { await DictionaryLookup.define($0) },
        contacts: { await ContactsLookup.search($0, limit: $1) },
        contactsAccess: { ContactsLookup.access() },
        requestContacts: { await ContactsLookup.request() },
        bookmarks: { await BrowserBookmarks.all() },
        rates: { await CurrencyRates.shared.rates() },
        menuItems: { pid in
            guard let app = NSRunningApplication(processIdentifier: pid) else { return [] }
            return await AppMenus.items(of: app)
        }
    )
}

/// Where files are looked for (Settings ▸ Siri ▸ Files) and how a name must match.
nonisolated struct FileScope: Sendable, Equatable {
    var paths: [String]
    /// The query may sit anywhere in the name (else at a word's start).
    var anywhere: Bool
    /// How far back the recent files go.
    var days: Int
    /// What the files say is searched too, not only their names.
    var contents = false

    init(paths: [String] = SiriFolder.allCases.filter { $0 != .home }.map(\.path), anywhere: Bool = false, days: Int = 30, contents: Bool = false) {
        self.paths = paths
        self.anywhere = anywhere
        self.days = days
        self.contents = contents
    }

    init(_ settings: SiriSettings) {
        self.init(paths: SiriFolder.allCases.filter { settings.folders.contains($0) }.map(\.path),
                  anywhere: settings.matching != .wordStart, days: settings.recentDays, contents: settings.searchesFileContents)
    }
}

/// Siri in the notch: the query, the live search, the list's selection, and answers from the
/// on-device model. Everything is torn down when the assistant closes (`end()`; the lists it read
/// go `keepDuration` later), so nothing runs while it is not on screen.
@Observable final class AssistantModel {
    /// Typed by the user; every change re-runs the search after a short pause.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            queryChanged()
        }
    }
    /// The suggestion the user opened (⌘1–⌘7); nil is the root.
    private(set) var category: AssistantCategory?
    /// Root search hits.
    private(set) var apps: [AssistantHit] = [] { didSet { if apps != oldValue { listsVersion &+= 1 } } }
    /// Root search hits, or the Files list (recent files, or the ones matching the query).
    private(set) var files: [AssistantHit] = [] { didSet { if files != oldValue { listsVersion &+= 1 } } }
    /// The menu bar commands of the app the user was in when Siri opened (`menuApp`), read once
    /// per opening, when a query of three letters or more first asks for them.
    private(set) var menuItems: [AssistantMenuItem]? { didSet { if menuItems != oldValue { listsVersion &+= 1 } } }
    @ObservationIgnored private var menuApp: pid_t?
    @ObservationIgnored private var menuTask: Task<Void, Never>?
    /// Every app, most recently used first: the Applications gallery, filtered in memory.
    private(set) var allApps: [AssistantHit] = [] { didSet { if allApps != oldValue { listsVersion &+= 1 } } }
    /// When `allApps` was read from Spotlight: it is kept across openings (asking Spotlight and
    /// drawing the icons again on every opening of the gallery was most of its energy, measured)
    /// and read again in the background once it is older than `appsLifetime`.
    @ObservationIgnored private var allAppsRead: Date?
    static let appsLifetime: TimeInterval = 30 * 60
    /// The user's shortcuts, read once per opening (and kept for `keepDuration` after it).
    private(set) var shortcuts: [String]? { didSet { if shortcuts != oldValue { listsVersion &+= 1 } } }
    /// The System Settings panes (⌘5), read once per opening (and kept for `keepDuration` after it).
    private(set) var settingsPanes: [SystemSettingsPane]? {
        didSet {
            guard settingsPanes != oldValue else { return }
            listsVersion &+= 1
            matchedPanes = nil
        }
    }
    /// The running apps (root), or their windows (⌘6), read once per opening.
    private(set) var windows: [AssistantWindow]? { didSet { if windows != oldValue { listsVersion &+= 1 } } }
    /// `windows` has the windows' titles: read through Accessibility only once ⌘6 opened.
    @ObservationIgnored private var windowsHaveTitles = false
    /// Every emoji (⌘7), built once per opening: a few thousand names are not kept at rest, only
    /// for `keepDuration` after a close.
    private(set) var emoji: EmojiIndex? {
        didSet {
            listsVersion &+= 1
            matchedEmoji = nil
        }
    }
    /// How long the lists read for an opening (shortcuts, panes, emoji) and Apple Intelligence's
    /// availability outlive it, as a closed panel is kept: a quick re-open reads and builds none of
    /// them again (a `shortcuts list` process, the emoji table and its index).
    static let keepDuration: Duration = .seconds(10)
    /// How long the read lists (shortcuts, panes, emoji, bookmarks) outlive a close: read again at
    /// every opening after ten seconds, they were most of what typing a first word cost (a
    /// `shortcuts list` process, the panes' table, the emoji index; Energy Impact ~350, measured).
    /// They are a few megabytes; read ahead after launch (`prewarm`) and kept half an hour.
    static let listsKeepDuration: Duration = .seconds(30 * 60)
    /// Times `keepDuration` (a test moves its own).
    @ObservationIgnored var clock: any Clock<Duration> = ContinuousClock()
    /// Frees the kept lists `keepDuration` after a close; nil while Siri is open or once they are gone.
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    /// The query's word as the dictionary has it (root, a single word).
    private(set) var definition: AssistantDefinition? { didSet { if definition != oldValue { listsVersion &+= 1 } } }
    /// The contacts the query found (root and ⌘8), read only once the user allowed them.
    private(set) var contacts: [AssistantContact] = [] { didSet { if contacts != oldValue { listsVersion &+= 1 } } }
    /// The contact whose ways to reach them ⌘8 lists (Return on a contact); Esc goes back.
    private(set) var openedContact: AssistantContact? { didSet { if openedContact != oldValue { listsVersion &+= 1 } } }
    private(set) var contactsAccess = AccessState.denied { didSet { if contactsAccess != oldValue { listsVersion &+= 1 } } }
    /// The browsers' bookmarks, read once per opening where they are switched on.
    private(set) var bookmarks: [AssistantBookmark]? { didSet { if bookmarks != oldValue { listsVersion &+= 1 } } }
    /// The currencies' rates, once a currency was typed and they arrived.
    private(set) var currencyRates: [String: Double]? {
        didSet {
            guard currencyRates != oldValue else { return }
            calculated = nil
            listsVersion &+= 1
        }
    }
    @ObservationIgnored private var ratesTask: Task<Void, Never>?
    /// The coming events matching a query (all of them for an empty one): the app's calendar, read
    /// only while ⌘8 is open or once the user allowed it.
    @ObservationIgnored var calendarEvents: (_ query: String) -> [CalendarEvent] = { _ in [] }
    @ObservationIgnored var calendarAccess: () -> AccessState = { .denied }
    @ObservationIgnored var requestCalendar: () -> Void = {}
    /// Spotlight starts (true) or stops reading the calendar.
    @ObservationIgnored var onCalendarLease: (Bool) -> Void = { _ in }
    @ObservationIgnored private var holdsCalendar = false
    /// A file is shown in Quick Look: the assistant stays while its panel has the keyboard.
    @ObservationIgnored private(set) var isPreviewing = false
    /// The switches' states as read this opening (their rows show "On" or "Off").
    private(set) var commandStates: [AssistantCommand: Bool] = [:]
    /// The row waiting for a second Return (Empty Trash); another selection or `confirmWindow` cancels it.
    private(set) var confirming: AssistantRow.ID?
    static let confirmWindow: Duration = .seconds(4)
    /// The second Return counts only this long after the first press: a double click or a
    /// double press of Return is not a confirmation (and a click never confirms).
    static let confirmDelay: Duration = .milliseconds(400)
    @ObservationIgnored private var confirmArmed = ContinuousClock.now
    private(set) var selection = 0
    /// Shown instead of the list while present.
    private(set) var answer: AssistantAnswer?
    /// Apple Intelligence can answer on this Mac.
    private(set) var intelligenceAvailable = false { didSet { if intelligenceAvailable != oldValue { listsVersion &+= 1 } } }
    /// The query's language is one the on-device model does not support (it then answers poorly
    /// or refuses, measured with Hungarian), so the "Ask" row moves down.
    private(set) var languageUnsupported = false { didSet { if languageUnsupported != oldValue { listsVersion &+= 1 } } }
    /// Moves with every list the rows are made of, so `rows` is composed once per change and not
    /// at every move of the pointer (observed: a view reading `rows` redraws when a list lands).
    /// Only a list that really changed moves it: the same hits landing again, or a close that
    /// empties lists already empty, redrew the list for nothing (~5 ms per close, measured).
    private var listsVersion = 0
    /// ↑/↓ brought the suggestions down under the field (the pointer does it by hovering).
    private(set) var revealsSuggestions = false

    /// The pointer is over the island (kept by the island controller).
    @ObservationIgnored var isPointerOver = false
    /// Closes the assistant (the island controller owns that).
    @ObservationIgnored var onClose: (() -> Void)?
    /// Runs an island action; the app also closes the assistant (or lets the panel take its place).
    @ObservationIgnored var onCommand: ((AppCommand) -> Void)?
    /// The user's Siri settings, read as they are needed (so a change applies at once).
    @ObservationIgnored var settings: () -> SiriSettings = { SiriSettings() }
    /// What the user copied, newest first (Clipboard, ⌘4).
    @ObservationIgnored var clipboard: () -> [ClipboardItem] = { [] }
    /// Pastes a copied item where the user was typing before Siri (the app closes Siri first).
    @ObservationIgnored var onPaste: ((ClipboardItem) -> Void)?
    /// Whether something is playing: the Now Playing actions are listed only with a track.
    @ObservationIgnored var mediaState: () -> MediaState = { .none }
    nonisolated enum MediaState: Sendable { case none, paused, playing }
    /// A files read that may ask for folder access has finished (the app takes the keyboard back
    /// from the system's prompt).
    @ObservationIgnored var onFileAccessSettled: (() -> Void)?
    /// Carries out the Mac's commands and switches: the app gives the live one, a test a recorder.
    @ObservationIgnored var system = AssistantSystem()
    /// A countdown is running or paused: "Cancel Timer" is listed.
    @ObservationIgnored var timerIsActive: () -> Bool = { false }
    /// The kinds of widget on the board ("Edit Timer Widget").
    @ObservationIgnored var widgetKinds: () -> [IslandWidgetKind] = { [] }
    /// Window Anchor as Spotlight lists it: nil while it cannot run, else whether a window is held.
    @ObservationIgnored var anchorIsHolding: () -> Bool? = { nil }
    /// ⌘↩ on a window: it comes to the front and goes under the notch.
    @ObservationIgnored var onAnchorWindow: ((AssistantWindow) -> Void)?
    /// The panel's pages this Mac has ("Open Battery" only with a battery).
    @ObservationIgnored var pages: () -> [ExpandedPage] = { ExpandedPage.allCases }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sources: AssistantSources
    /// The user once listed or searched files and got hits (so access was granted): file hits then
    /// come with every query. Until then files are read only from the Files suggestion, because the
    /// first read asks for folder access.
    @ObservationIgnored private var filesEnabled: Bool {
        get { defaults.bool(forKey: Self.filesKey) }
        set { defaults.set(newValue, forKey: Self.filesKey) }
    }
    nonisolated static let filesKey = "ni2.assistantFiles"

    init(defaults: UserDefaults = .standard, sources: AssistantSources = .live) {
        self.defaults = defaults
        self.sources = sources
    }

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// The running apps, read apart from the other lists so their rows never wait on Accessibility.
    @ObservationIgnored private var windowsTask: Task<Void, Never>?
    /// The current query's search has not landed: the rows are still an earlier query's.
    @ObservationIgnored private var searchPending = false
    /// A Return pressed while `searchPending`: it runs once the results land, or after `returnWait`.
    @ObservationIgnored private var deferredReturn: Task<Void, Never>?
    @ObservationIgnored var returnWait: Duration = .milliseconds(400)
    @ObservationIgnored private var askTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// The user moved the selection (keys or pointer): results landing keep that row selected.
    @ObservationIgnored private var selectionIsUsers = false
    /// The pointer put the selection where it is (hovering a row). The lists scroll only a
    /// selection the keys moved: scrolling slides a new row under a still pointer, and scrolling
    /// that one into view would slide the next one under it, down to the end.
    @ObservationIgnored private(set) var selectionFollowsPointer = false
    /// The keys moved the selection: its row is marked (a plate in the theme's colour) until the
    /// user types or points. Only then: a plate always under the first row read as a stuck hover
    /// (v0.4.5); without one, ↑/↓ showed nothing of where they were (a tester, v0.4.10).
    private(set) var marksSelection = false
    /// Files reads running that may be waiting on the system's folder-access prompt.
    @ObservationIgnored private var fileAccessReads = 0

    /// Pause after a keystroke before searching (the default of `SiriSettings.searchDelay`).
    static let searchDelay: Duration = .milliseconds(120)
    /// Root search: hits of each kind (the default of `SiriSettings.resultsPerKind`).
    static let rootHitLimit = 3
    static let rootActionLimit = 2
    /// Columns of the Applications gallery (↑/↓ move by a row of them).
    var galleryColumns: Int { settings().galleryColumns }
    /// The gallery's icon side (Settings ▸ Spotlight ▸ App Gallery).
    var galleryIconSize: CGFloat { settings().galleryIconSize.points }

    /// Apple Intelligence answers here: it is available and the user has not turned it off.
    private var answersWithIntelligence: Bool { intelligenceAvailable && settings().usesIntelligence }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Something to list: a query, an open suggestion or an answer (the island then shows the list).
    var needsList: Bool { !query.isEmpty || category != nil || answer != nil }

    /// How much of the island the assistant needs: the field alone until the pointer is over it or
    /// ↓ is pressed, the suggestions' height for up to three rows, the full list beyond that (and
    /// for the gallery and answers, which scroll).
    var room: AssistantRoom {
        if answer != nil { return .list }
        if category == .applications {
            // A search in the gallery: as many rows as its apps fill, up to the gallery's own.
            guard !trimmedQuery.isEmpty else { return .gallery }
            let columns = max(1, settings().galleryColumns)
            let needed = max(1, (rows.count + columns - 1) / columns)
            return needed < settings().galleryRows ? .galleryRows(needed) : .gallery
        }
        if needsList {
            // Exactly the rows there are (a query's hits, an open suggestion's items), not a list's
            // worth of empty space, up to the list's height (Settings ▸ Siri), which then scrolls.
            let count = rows.count
            return count < settings().listRows ? .rows(max(count, 1)) : .list
        }
        // Exactly the suggestions the user has switched on.
        return revealsSuggestions || hoverReveals ? .rows(max(settings().categories.count, 1)) : .field
    }

    /// The pointer over Siri brings the suggestions down (unless the user turned that off).
    private var hoverReveals: Bool { isPointerOver && settings().hoverRevealsSuggestions }

    /// A folder-access prompt may have the keyboard: the assistant must not close when it loses it.
    var isAwaitingFileAccess: Bool { fileAccessReads > 0 || isPreviewing || permissionRequests > 0 }
    @ObservationIgnored private var permissionRequests = 0

    /// The rows can be seen and chosen (the field alone shows none).
    private var rowsAreShowing: Bool { needsList || revealsSuggestions || hoverReveals }

    /// What the rows are made of besides the lists (`listsVersion`): read at every access, so the
    /// views reading `rows` keep observing them, and compared, so a hover reuses the rows.
    private struct RowsKey: Equatable {
        var query: String
        var category: AssistantCategory?
        var lists: Int
        var settings: SiriSettings
        var media: MediaState
        var timerIsActive: Bool
        var widgetKinds: [IslandWidgetKind]
        var clips: [ClipboardItem]
        /// The calendar as People & Calendar (and a root query) lists it.
        var calendar: AccessState
        var events: [CalendarEvent]
        /// Window Anchor's Anchor / Release row (nil: it cannot run).
        var anchor: Bool?
    }

    @ObservationIgnored private var composed: (key: RowsKey, rows: [AssistantRow])?

    var rows: [AssistantRow] {
        let text = trimmedQuery
        let listsEvents = category == .people || (category == nil && text.count >= 3 && settings().showsPeople)
        let key = RowsKey(query: text, category: category, lists: listsVersion, settings: settings(),
                          media: mediaState(), timerIsActive: timerIsActive(), widgetKinds: widgetKinds(),
                          clips: category == .clipboard ? clipboard() : [],
                          calendar: listsEvents ? calendarAccess() : .denied, events: listsEvents ? calendarEvents(text) : [],
                          anchor: anchorIsHolding())
        if let composed, composed.key == key { return composed.rows }
        let rows = compose(key.query, key.settings, clips: key.clips, calendar: key.calendar, events: key.events)
        composed = (key, rows)
        return rows
    }

    private func compose(_ text: String, _ settings: SiriSettings, clips: [ClipboardItem], calendar: AccessState,
                         events: [CalendarEvent]) -> [AssistantRow] {
        switch category {
        case .applications:
            let gallery = settings.gallerySort == .name
                ? allApps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                : allApps
            guard !text.isEmpty else { return gallery.map(AssistantRow.hit) }
            return AssistantSearch.rank(gallery.filter { AssistantMatch.matches($0.name, text, settings.matching) }, for: text)
                .map(AssistantRow.hit)
        case .files:
            return files.map(AssistantRow.hit)
        case .actions:
            return actions(matching: text).map(AssistantRow.action)
        case .clipboard:
            guard !text.isEmpty else { return clips.map(AssistantRow.clip) }
            return clips.filter { AssistantMatch.matches($0.text, text, .anywhere) }.map(AssistantRow.clip)
        case .system:
            return typedTimer(text) + commands(matching: text).map(AssistantRow.command)
                + panes(matching: text).map(AssistantRow.settingsPane)
        case .windows:
            return windows(matching: text).map(AssistantRow.window)
        case .emoji:
            return emoji(matching: text).map(AssistantRow.emoji)
        case .people:
            if let openedContact { return openedContact.actions.map(AssistantRow.contactAction) }
            // What is not allowed yet is one row that asks; then the people found, then the events.
            var rows: [AssistantRow] = []
            if contactsAccess != .granted { rows.append(.permission(.contacts)) }
            if calendar != .granted { rows.append(.permission(.calendar)) }
            rows += contacts.map(AssistantRow.contact)
            if calendar == .granted { rows += events.map(AssistantRow.event) }
            return rows
        case nil:
            guard !text.isEmpty else { return settings.categories.map(AssistantRow.category) }
            // A sum or a conversion is worked out at once and comes first, above everything, as in
            // Spotlight: "12 + 30 * 2" had five words and went to Apple Intelligence (seen, v0.4.5).
            // A typed web address first of all, as in Spotlight ("github.com", Return); a typed
            // timer ("10 min timer") with them.
            let calculation = (AssistantURL.url(from: text).map { [AssistantRow.openURL($0)] } ?? [])
                + (calculation(for: text).map { [AssistantRow.calculation($0)] } ?? [])
                + (settings.showsSystem ? typedTimer(text) : [])
                + (settings.showsDefinitions && definition?.word.caseInsensitiveCompare(text) == .orderedSame
                   ? [AssistantRow.definition(definition!)] : [])
            // The other kinds' best few: commands and panes by name after the apps, emoji last
            // (and only from two letters: one matches hundreds).
            let few = min(settings.resultsPerKind, Self.rootActionLimit)
            let system = settings.showsSystem
                ? commands(matching: text).prefix(few).map(AssistantRow.command) + panes(matching: text).prefix(few).map(AssistantRow.settingsPane)
                : []
            let hits = (settings.showsApplications ? apps.map(AssistantRow.hit) : [])
                + system
                + (settings.showsFiles ? files.map(AssistantRow.hit) : [])
                + (settings.showsWindows ? windows(matching: text).prefix(few).map(AssistantRow.window) : [])
                + (settings.showsActions ? actions(matching: text).prefix(Self.rootActionLimit).map(AssistantRow.action)
                   + menuItems(matching: text).prefix(few).map(AssistantRow.menuItem) : [])
                + (settings.showsPeople ? contacts.prefix(few).map(AssistantRow.contact)
                   + (calendar == .granted ? events.prefix(few).map(AssistantRow.event) : []) : [])
                + (settings.showsBookmarks ? bookmarks(matching: text).prefix(few).map(AssistantRow.bookmark) : [])
                + (settings.showsEmoji && text.count >= 2 ? emoji(matching: text).prefix(few).map(AssistantRow.emoji) : [])
            let intelligence = answersWithIntelligence
            // A question is answered on Return: the answer comes first, above any hits (Apple
            // Intelligence here, ChatGPT without it).
            if Self.looksLikeQuestion(text), intelligence || settings.offersChatGPT {
                let answer: AssistantRow = intelligence ? .askIntelligence : .askChatGPT
                return calculation + [answer] + hits + [.searchWeb, .askChatGPT, .askIntelligence].filter {
                    $0 != answer && ($0 != .askIntelligence || intelligence) && ($0 != .askChatGPT || settings.offersChatGPT)
                }
            }
            // A suggestion typed by name ("application", "files") comes first, so Return opens it,
            // unless a hit's name starts with the query too ("app" is more likely App Store).
            let named = Self.categories(named: text, in: settings.categories).map(AssistantRow.category)
            let hitStarts = (apps + files).contains { AssistantMatch.startsName($0.name, text) }
            // A quick action typed by its key ("se", "sm") or with its text comes first; its name
            // alone ("mail") after the hits (Mail the app is more likely).
            let compose = settings.showsActions ? AssistantCompose.parse(text) : nil
            let composeFirst = compose.map { $0.isQuickKey || !$0.text.isEmpty } ?? false
            var rows = calculation + (composeFirst ? [AssistantRow.compose(compose!)] : [])
                + (hitStarts ? hits + named : named + hits)
                + (compose != nil && !composeFirst ? [AssistantRow.compose(compose!)] : [])
            let ask: [AssistantRow] = intelligence ? [.askIntelligence] : []
            if !languageUnsupported { rows += ask }
            rows += [.searchWeb]
            if settings.offersChatGPT { rows += [.askChatGPT] }
            if languageUnsupported { rows += ask }
            return rows
        }
    }

    /// The query's sum or conversion, worked out once per query: `rows` is read again at every
    /// move of the pointer over the list.
    @ObservationIgnored private var calculated: (query: String, result: AssistantCalculation?)?

    private func calculation(for text: String) -> AssistantCalculation? {
        if let calculated, calculated.query == text { return calculated.result }
        let result = AssistantCalculator.calculate(text, context: .init(rates: settings().convertsCurrency ? currencyRates : nil))
        calculated = (text, result)
        return result
    }

    /// The bookmarks whose title or address has the query, titles that start with it first.
    private func bookmarks(matching text: String) -> [AssistantBookmark] {
        guard let bookmarks, text.count >= 2 else { return [] }
        let matching = settings().matching
        let found = bookmarks.filter { AssistantMatch.matches($0.title, text, matching) || ($0.url.host() ?? "").localizedCaseInsensitiveContains(text) }
        return found.filter { AssistantMatch.startsName($0.title, text) } + found.filter { !AssistantMatch.startsName($0.title, text) }
    }

    /// The suggestions whose name the query spells out (three letters or more, so "a" does not
    /// list them all): "appl", "application", "files", "shortcuts".
    nonisolated static func categories(named text: String, in categories: [AssistantCategory]) -> [AssistantCategory] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return [] }
        return categories.filter { category in
            category.searchNames.contains { AssistantMatch.startsName($0, text) }
        }
    }

    /// The island's actions (Now Playing ones only with a track), then the user's shortcuts.
    func actions(matching text: String) -> [AssistantAction] {
        let settings = settings()
        var island: [IslandAction] = switch mediaState() {
        case .playing: [.pause, .next, .previous]
        case .paused: [.play, .next, .previous]
        case .none: []
        }
        island += [.timer, .stopwatch, .shelf, .customize, .settings]
        if !settings.includesIslandActions { island = [] }
        let all = island.map(AssistantAction.island)
            + (settings.includesShortcuts ? (shortcuts ?? []) : []).map(AssistantAction.shortcut)
        guard !text.isEmpty else { return all }
        return all.filter { AssistantMatch.matches($0.title, text, settings.matching) }
    }

    /// "timer 10": a row that starts it.
    private func typedTimer(_ text: String) -> [AssistantRow] {
        AssistantCommand.timerMinutes(in: text).map { [.command(.timer(minutes: $0))] } ?? []
    }

    /// What the commands matched for a query, and the panes and emoji: worked out once per query,
    /// as the rows are composed again for the same query when its search lands.
    private struct CommandsKey: Equatable {
        var text: String
        var matching: SiriMatching
        var timerIsActive: Bool
        var widgetKinds: [IslandWidgetKind]
        var pages: [ExpandedPage]
        var anchor: Bool?
    }

    @ObservationIgnored private var matchedCommands: (key: CommandsKey, commands: [AssistantCommand])?
    @ObservationIgnored private var matchedPanes: (text: String, matching: SiriMatching, panes: [SystemSettingsPane])?
    @ObservationIgnored private var matchedEmoji: (text: String, emoji: [AssistantEmoji])?

    /// The island's commands (pages the actions do not open, Settings tabs, keep open, the
    /// board's widgets' editors), Control Center's switches, then the Mac's own.
    func commands(matching text: String) -> [AssistantCommand] {
        let key = CommandsKey(text: text, matching: settings().matching, timerIsActive: timerIsActive(), widgetKinds: widgetKinds(), pages: pages(),
                              anchor: anchorIsHolding())
        if let matchedCommands, matchedCommands.key == key { return matchedCommands.commands }
        let actionPages = IslandAction.allCases.map(\.command)
        var all = key.pages.filter { !actionPages.contains(.open($0)) }.map(AssistantCommand.page)
        all += IslandSettingsPane.allCases.map(AssistantCommand.settings)
        all.append(.keepOpen)
        if key.timerIsActive { all.append(.cancelTimer) }
        if let holding = key.anchor { all.append(holding ? .releaseWindow : .anchorWindow) }
        var seen = Set<IslandWidgetKind>()
        all += key.widgetKinds.filter { seen.insert($0).inserted }.map(AssistantCommand.editWidget)
        all += AssistantCommand.controls.map(AssistantCommand.control)
        all += MacCommand.allCases.map(AssistantCommand.mac)
        let commands = text.isEmpty ? all
            : all.filter { command in command.searchNames.contains { AssistantMatch.matches($0, text, key.matching) } }
        matchedCommands = (key, commands)
        return commands
    }

    private func panes(matching text: String) -> [SystemSettingsPane] {
        let panes = settingsPanes ?? []
        guard !text.isEmpty else { return panes }
        let matching = settings().matching
        if let matchedPanes, matchedPanes.text == text, matchedPanes.matching == matching { return matchedPanes.panes }
        // Found by its own name first ("sound" is Sound before Headphones' "Sound" synonyms).
        let named = panes.filter { AssistantMatch.matches($0.title, text, matching) }
        let found = named + panes.filter { pane in !named.contains(pane) && pane.synonyms.contains { AssistantMatch.matches($0, text, matching) } }
        matchedPanes = (text, matching, found)
        return found
    }

    private func windows(matching text: String) -> [AssistantWindow] {
        let windows = windows ?? []
        guard !text.isEmpty else { return windows }
        let matching = settings().matching
        return windows.filter { AssistantMatch.matches($0.name, text, matching) || AssistantMatch.matches($0.appName, text, matching) }
    }

    /// An alias typed exactly first ("ok" is 👌), then names that start with it, then the rest.
    private func emoji(matching text: String) -> [AssistantEmoji] {
        guard let emoji else { return [] }
        if let matchedEmoji, matchedEmoji.text == text { return matchedEmoji.emoji }
        let found = emoji.matching(text)
        matchedEmoji = (text, found)
        return found
    }

    /// The row the selection is on, while the list shows.
    private var selectedRow: AssistantRow? {
        guard answer == nil else { return nil }
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// The copied item the selection is on, in Clipboard (the field shows it, as Spotlight does).
    var selectedClip: ClipboardItem? {
        guard category == .clipboard, case .clip(let item) = selectedRow else { return nil }
        return item
    }

    /// ⌘C on a copy (Clipboard) or an emoji: it goes on the pasteboard, without a click on it.
    /// False when the selection is on neither (the key goes on to the field).
    func copySelection() -> Bool {
        let text: String
        switch selectedRow {
        case .clip(let item) where category == .clipboard: text = item.text
        case .emoji(let emoji): text = emoji.character
        case .contactAction(let action) where action.kind != .openCard: text = action.value
        case .contact(let contact) where contact.detail != nil: text = contact.detail ?? ""
        case .bookmark(let bookmark): text = bookmark.url.absoluteString
        default: return false
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return true
    }

    /// ⌘H on a running app or its window the user moved to or picked: hides the app, Spotlight
    /// stays. False on any other row, and on a row the list merely starts at.
    func hideSelectedApp() -> Bool {
        guard selectionIsUsers || marksSelection, case .window(let window) = selectedRow else { return false }
        system.hide(window)
        return true
    }

    /// ⌘↩ on a running app or its window: it comes to the front and is anchored under the notch.
    /// False on any other row, and while Window Anchor cannot run.
    func anchorSelectedWindow() -> Bool {
        guard anchorIsHolding() != nil, selectionIsUsers || marksSelection, case .window(let window) = selectedRow,
              let onAnchorWindow else { return false }
        onAnchorWindow(window)
        return true
    }

    /// ⌘Q on a running app or its window: quits the app (macOS asks about unsaved documents) and
    /// its rows go. False on any other row, and on a row the user did not move to or pick.
    func quitSelectedApp() -> Bool {
        guard selectionIsUsers || marksSelection, case .window(let window) = selectedRow else { return false }
        system.quit(window)
        replaceLists { windows?.removeAll { $0.pid == window.pid } }
        // The row the selection falls to was not chosen: another ⌘Q waits for a move.
        selectionIsUsers = false
        marksSelection = false
        return true
    }

    // MARK: Lifecycle

    /// The assistant opened.
    func begin() {
        // Closed less than `keepDuration` ago: what that opening read is still here.
        let reopensQuickly = releaseTask != nil
        end()
        releaseTask?.cancel()
        releaseTask = nil
        // Read ahead in the background (`prewarm`): the first query loads the framework's model
        // catalogue on the calling thread (~0.1 s on the main thread at the first opening, measured).
        if let known = knownIntelligence {
            intelligenceAvailable = known
            if !reopensQuickly {
                Task { [weak self] in
                    let now = await Self.readIntelligence()
                    self?.knownIntelligence = now
                    if self?.intelligenceAvailable != now { self?.intelligenceAvailable = now }
                }
            }
        } else {
            intelligenceAvailable = Self.readIntelligenceNow()
            knownIntelligence = intelligenceAvailable
        }
        // The app the user is in (the island never takes the front): its menus are searched.
        let front = NSWorkspace.shared.frontmostApplication
        menuApp = front.flatMap { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : $0.processIdentifier }
        // The app list is read ahead (one Spotlight query, off the main thread), so the gallery
        // opens full.
        loadLists(for: .applications, query: "")
    }

    @ObservationIgnored private var knownIntelligence: Bool?
    @ObservationIgnored private var hasOpenedGallery = false

    nonisolated static func readIntelligenceNow() -> Bool {
        if case .available = SystemLanguageModel.default.availability { true } else { false }
    }

    @concurrent nonisolated static func readIntelligence() async -> Bool { readIntelligenceNow() }

    /// What the first opening of Siri would otherwise do at once — Apple Intelligence's
    /// availability, the app list and the gallery's first icons (from disk after the first launch,
    /// `IconDiskCache`) — done a while after launch on the background queue (efficiency cores), a
    /// little at a time. The first opening then only builds its views (it cost Energy Impact 130,
    /// the app gallery 300, measured cold).
    func prewarm(icons: Int = 42) async {
        knownIntelligence = await Self.readIntelligence()
        if allApps.isEmpty {
            let found = await sources.allApps()
            // Siri may have opened (and read the list itself) meanwhile.
            if allApps.isEmpty {
                replaceLists {
                    allApps = found
                    allAppsRead = Date()
                }
            }
        }
        let gallery = settings().gallerySort == .name
            ? allApps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            : allApps
        for hit in gallery.prefix(icons) {
            _ = await AssistantIcons.thumbnail(for: hit, points: settings().galleryIconSize.points, prewarming: true)
        }
        await readListsAhead()
        // The kept icons of apps and icon styles that are gone go, and the least recently used
        // beyond the cache's bound.
        await AssistantIcons.tidyDisk()?.value
    }

    /// Contacts' authorization as read at most `accessLifetime` ago: each read is a question to the
    /// privacy daemon (tccd, billed to the app), and typing asked it at every keystroke.
    private func recentContactsAccess(now: Date = Date()) -> AccessState {
        if let cached = cachedContactsAccess, now.timeIntervalSince(cached.read) < Self.accessLifetime { return cached.state }
        let state = sources.contactsAccess()
        cachedContactsAccess = (state, now)
        return state
    }

    @ObservationIgnored private var cachedContactsAccess: (state: AccessState, read: Date)?
    static let accessLifetime: TimeInterval = 30

    /// What a first typed word reads — the lists a root query searches, and the system's search
    /// services (Spotlight, the dictionary, Contacts), whose first query of a launch cost several
    /// times a later one, billed to the app — read once ahead, unseen, at background priority.
    private func readListsAhead() async {
        let settings = settings()
        let sources = sources
        let needsShortcuts = shortcuts == nil && settings.includesShortcuts
        let needsPanes = settingsPanes == nil && settings.showsSystem
        let needsEmoji = emoji == nil && settings.showsEmoji
        let needsBookmarks = bookmarks == nil && settings.showsBookmarks
        async let foundShortcuts = needsShortcuts ? sources.shortcuts() : nil
        async let foundPanes = needsPanes ? sources.settingsPanes() : nil
        async let foundEmoji = needsEmoji ? EmojiIndex.build(sources.emoji) : nil
        async let foundBookmarks = needsBookmarks ? sources.bookmarks() : nil
        let lists = await (foundShortcuts, foundPanes, foundEmoji, foundBookmarks)
        var icons = Set<AssistantIcons.Source>()
        if lists.0?.isEmpty == false { icons.insert(AssistantIcons.shortcutsSource) }
        if lists.1?.isEmpty == false { icons.insert(AssistantIcons.systemSettingsSource) }
        if !icons.isEmpty { await AssistantIcons.prepare(Array(icons)) }
        // Siri may have opened and read them itself meanwhile.
        if needsShortcuts, shortcuts == nil { shortcuts = lists.0 ?? [] }
        if needsPanes, settingsPanes == nil { settingsPanes = lists.1 ?? [] }
        if needsEmoji, emoji == nil { emoji = lists.2 ?? EmojiIndex([]) }
        if needsBookmarks, bookmarks == nil { bookmarks = lists.3 ?? [] }
        _ = await sources.apps("a", 1)
        if settings.showsDefinitions { _ = await sources.define("notch") }
        if settings.showsPeople, sources.contactsAccess() == .granted { _ = await sources.contacts("a", 1) }
    }

    /// The assistant closed: cancel everything and forget the query; the lists go `keepDuration`
    /// later unless it opens again meanwhile.
    func end() {
        generation &+= 1
        searchTask?.cancel()
        searchTask = nil
        loadTask?.cancel()
        loadTask = nil
        windowsTask?.cancel()
        windowsTask = nil
        askTask?.cancel()
        askTask = nil
        menuTask?.cancel()
        menuTask = nil
        menuItems = nil
        searchPending = false
        cancelDeferredReturn()
        category = nil
        query = ""
        apps = []
        files = []
        definition = nil
        contacts = []
        openedContact = nil
        ratesTask?.cancel()
        ratesTask = nil
        isPreviewing = false
        if holdsCalendar {
            holdsCalendar = false
            onCalendarLease(false)
        }
        // Read live at every opening.
        windows = nil
        windowsHaveTitles = false
        commandStates = [:]
        cancelConfirmation()
        selection = 0
        selectionIsUsers = false
        selectionFollowsPointer = false
        marksSelection = false
        answer = nil
        languageUnsupported = false
        revealsSuggestions = false
        // The app list and the gallery's icons stay for the next opening; the icons go after a
        // while without Siri (`AssistantIcons.purgeLater`).
        AssistantIcons.purgeLater()
        // The icons kept on disk are tidied here too: the prewarm, which tidies them, is skipped
        // when Siri opens first.
        AssistantIcons.tidyDisk()
        releaseTask?.cancel()
        releaseTask = Task { [weak self, clock] in
            try? await clock.sleep(for: Self.listsKeepDuration, tolerance: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.releaseTask = nil
            self.shortcuts = nil
            self.settingsPanes = nil
            self.emoji = nil
            self.bookmarks = nil
            AssistantMatch.forget()
        }
    }

    // MARK: Keys

    /// ↑/↓ (and ←/→ in the gallery). The first press on the bare field brings the suggestions down
    /// with the first one selected.
    func moveSelection(by delta: Int) {
        guard answer == nil else { return }
        if !rowsAreShowing {
            revealsSuggestions = true
            selection = 0
            marksSelection = true
            return
        }
        revealsSuggestions = true
        let count = rows.count
        guard count > 0 else { return }
        let next = min(max(selection + delta, 0), count - 1)
        if next != selection { cancelConfirmation() }
        selection = next
        selectionIsUsers = true
        selectionFollowsPointer = false
        marksSelection = true
    }

    func select(_ row: AssistantRow) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        if index != selection { cancelConfirmation() }
        selection = index
        selectionIsUsers = true
        selectionFollowsPointer = true
        marksSelection = false
    }

    /// Return: runs the selected row. On an answer it asks again if the question was edited; on the
    /// bare field it does nothing (nothing is shown to run). Pressed before the query's results
    /// land, it waits for them (up to `returnWait`), so it runs the row the user then sees: "blu"
    /// and Return at once turned Bluetooth off, the row above the apps until they landed.
    func activateSelection() {
        if let answer {
            if !trimmedQuery.isEmpty, trimmedQuery != answer.question { ask() }
            return
        }
        guard rowsAreShowing else { return }
        guard searchPending else { return runSelection() }
        guard deferredReturn == nil else { return }
        // The services wait for a pause in the typing (`servicesPause`): a Return is that pause.
        search(now: true)
        let wait = returnWait
        deferredReturn = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self else { return }
            self.deferredReturn = nil
            self.runSelection()
        }
    }

    private func runSelection() {
        let rows = rows
        guard rowsAreShowing, answer == nil, rows.indices.contains(selection) else { return }
        let row = rows[selection]
        // From the root a switch or a Mac command runs only once the query's own results are in:
        // the apps landing may put another row where it was. (Only those have no island command.)
        if category == nil, searchPending, case .command(let command) = row, command.appCommand == nil {
            DiagnosticsFlow.record("siri: Return on \(row.id) before \"\(trimmedQuery)\" landed, not run")
            return
        }
        perform(row, byKey: true)
    }

    private func cancelDeferredReturn() {
        deferredReturn?.cancel()
        deferredReturn = nil
    }

    /// Esc: from an answer back to the list, then clear the query, then leave the suggestion, then
    /// fold the suggestions away, then close.
    func escape() {
        if answer != nil {
            askTask?.cancel()
            answer = nil
        } else if openedContact != nil {
            openedContact = nil
            selection = 0
        } else if !query.isEmpty {
            query = ""
        } else if category != nil {
            open(nil)
        } else if revealsSuggestions, !isPointerOver {
            revealsSuggestions = false
            selection = 0
        } else {
            onClose?()
        }
    }

    /// Delete with an empty field leaves the suggestion. False when there was nothing to leave, so
    /// the key goes on to the field.
    func deleteBackwardInEmptyField() -> Bool {
        guard query.isEmpty, answer == nil, category != nil else { return false }
        if openedContact != nil {
            openedContact = nil
            selection = 0
        } else {
            open(nil)
        }
        return true
    }

    /// ⌘1, ⌘2, ⌘3, or a suggestion row; nil goes back to the root. The query stays, so a search
    /// can be narrowed to one kind.
    func open(_ category: AssistantCategory?) {
        // The app gallery's first build (its grid and every cell's types): on the efficiency
        // cores, once (Energy Impact ~95 at full clock, measured).
        if category == .applications, !hasOpenedGallery {
            hasOpenedGallery = true
            MainThrift.lowPower(for: 0.9)
        }
        // A suggestion the user switched off does not open by its shortcut either.
        if let category, !settings().categories.contains(category) { return }
        if answer != nil {
            askTask?.cancel()
            answer = nil
        }
        guard category != self.category else { return }
        self.category = category
        openedContact = nil
        // ⌘8 reads the calendar while it is open (nothing is, until the user allowed it).
        let wantsCalendar = category == .people
        if wantsCalendar != holdsCalendar {
            holdsCalendar = wantsCalendar
            onCalendarLease(wantsCalendar)
        }
        if category == .people { contactsAccess = sources.contactsAccess() }
        cancelConfirmation()
        cancelDeferredReturn()
        // Back at the root the suggestions stay down: the user was just in one.
        revealsSuggestions = true
        selection = 0
        selectionIsUsers = false
        selectionFollowsPointer = false
        marksSelection = false
        files = []
        apps = []
        search(now: true)
    }

    // MARK: Actions

    /// A row clicked, or (`byKey`) chosen with Return.
    func perform(_ row: AssistantRow, byKey: Bool = false) {
        DiagnosticsFlow.record("siri: picked \(row.id) for \"\(trimmedQuery)\"")
        // From the answer pane the hand-offs take the question that was answered.
        let text = answer?.question ?? trimmedQuery
        switch row {
        case .category(let category):
            // Opened by typing its name: the name is not a filter for the list it opens.
            if self.category == nil, Self.categories(named: trimmedQuery, in: [category]) == [category] {
                query = ""
            }
            open(category)
        case .hit(let hit):
            onClose?()
            system.open(hit.url)
        case .action(.island(let action)):
            onCommand?(action.command)
        case .action(.shortcut(let name)):
            onClose?()
            AssistantActions.runShortcut(named: name)
        case .clip(let item):
            onPaste?(item)
        case .command(let command):
            run(command, row: row, byKey: byKey)
        case .settingsPane(let pane):
            guard let url = pane.url else { return }
            onClose?()
            system.open(url)
        case .window(let window):
            // Handed over while Spotlight is still the active app, then closed.
            system.switchTo(window)
            onClose?()
        case .emoji(let emoji):
            onPaste?(ClipboardItem(text: emoji.character, copied: .now))
        case .openURL(let url):
            onClose?()
            NSWorkspace.shared.open(url)
        case .calculation(let calculation):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(calculation.result, forType: .string)
            onClose?()
        case .definition(let definition):
            // The whole entry where answers are shown.
            askTask?.cancel()
            answer = AssistantAnswer(question: definition.word, text: definition.text, isResponding: false, definedWord: definition.word)
        case .contact(let contact):
            // Its ways to reach them, in People & Calendar.
            if category != .people {
                query = ""
                open(.people)
            }
            openedContact = contact
            selection = 0
            selectionIsUsers = false
        case .contactAction(let action):
            if let url = action.url {
                onClose?()
                system.open(url)
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(action.value, forType: .string)
                onClose?()
            }
        case .event(let event):
            // Calendar on the event's day.
            guard let url = URL(string: "calshow:\(Int(event.start.timeIntervalSinceReferenceDate))") else { return }
            onClose?()
            system.open(url)
        case .bookmark(let bookmark):
            onClose?()
            system.open(bookmark.url)
        case .permission(.contacts):
            // macOS's prompt takes the keyboard: Spotlight stays meanwhile.
            permissionRequests += 1
            let sources = sources
            Task { [weak self] in
                let access = await sources.requestContacts()
                guard let self else { return }
                self.permissionRequests -= 1
                self.contactsAccess = access
                self.cachedContactsAccess = nil
                self.onFileAccessSettled?()
                self.search(now: true)
            }
        case .permission(.calendar):
            requestCalendar()
        case .askIntelligence:
            ask()
        case .searchWeb:
            guard let url = AssistantActions.webSearchURL(for: text, engine: settings().searchEngine) else { return }
            onClose?()
            NSWorkspace.shared.open(url)
        case .askChatGPT:
            guard let url = AssistantActions.chatGPTURL(for: text) else { return }
            onClose?()
            NSWorkspace.shared.open(url)
        case .compose(let compose):
            onClose?()
            AssistantActions.perform(compose)
        case .menuItem(let item):
            onClose?()
            // Once Siri has let go of the keyboard: the app takes the command as from its menu.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { AppMenus.press(item) }
        }
    }

    private func run(_ command: AssistantCommand, row: AssistantRow, byKey: Bool) {
        switch command {
        case .page, .settings, .keepOpen, .timer, .cancelTimer, .editWidget, .anchorWindow, .releaseWindow:
            if let appCommand = command.appCommand { onCommand?(appCommand) }
        case .control(let control):
            // `refresh` reads only the switches a widget shows: this one is read now, so the
            // switch goes the right way.
            let on = system.state(command, true) ?? false
            onClose?()
            system.setControl(control, !on)
        case .mac(.emptyTrash) where confirming != row.id:
            confirming = row.id
            confirmArmed = .now
            confirmTask = Task { [weak self] in
                try? await Task.sleep(for: Self.confirmWindow)
                guard !Task.isCancelled else { return }
                self?.cancelConfirmation()
            }
        case .mac(.emptyTrash) where !byKey || ContinuousClock.now - confirmArmed < Self.confirmDelay:
            // Armed: only a Return after the pause empties it.
            break
        case .mac(let mac):
            cancelConfirmation()
            onClose?()
            system.run(mac)
        }
    }

    @ObservationIgnored private var confirmTask: Task<Void, Never>?

    private func cancelConfirmation() {
        confirmTask?.cancel()
        confirmTask = nil
        if confirming != nil { confirming = nil }
    }

    /// Reads the states of the switches among `commands` not read yet this opening.
    private func readStates(of commands: [AssistantCommand]) {
        for command in commands where command.hasState && commandStates[command] == nil {
            if let on = system.state(command, false) { commandStates[command] = on }
        }
    }

    /// Asks Apple Intelligence, streaming the answer into `answer`. A new session per question:
    /// a reused one carries context over (measured: after a question about France, the capital of
    /// Hungary came back as "Paris").
    func ask() {
        let question = trimmedQuery
        guard answersWithIntelligence, !question.isEmpty else { return }
        let length = settings().answerLength
        askTask?.cancel()
        answer = AssistantAnswer(question: question)
        askTask = Task { [weak self] in
            let session = LanguageModelSession(instructions: length.instructions)
            do {
                let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: length.maximumTokens)
                for try await snapshot in session.streamResponse(to: question, options: options) {
                    guard !Task.isCancelled, let self, self.answer?.question == question else { return }
                    self.answer?.text = snapshot.content
                }
                guard !Task.isCancelled else { return }
                self?.answer?.isResponding = false
            } catch {
                guard !Task.isCancelled, let self, self.answer?.question == question else { return }
                self.answer?.isResponding = false
                self.answer?.failure = Self.describe(error)
            }
        }
    }

    // MARK: Files

    /// The file the selection is on (a hit that is not an app).
    private var selectedFile: URL? {
        guard case .hit(let hit) = selectedRow, hit.kind != .app else { return nil }
        return hit.url
    }

    /// Space or ⌘Y on a file the user moved to: Quick Look, Spotlight staying under it. False on
    /// any other row (the key goes on to the field).
    func quickLookSelection() -> Bool {
        guard selectionIsUsers || marksSelection, let url = selectedFile else { return false }
        isPreviewing = true
        system.quickLook(url) { [weak self] in
            self?.isPreviewing = false
            self?.onFileAccessSettled?()
        }
        return true
    }

    /// ⌘R on a file or an app: shown in Finder.
    func revealSelection() -> Bool {
        guard case .hit(let hit) = selectedRow else { return false }
        onClose?()
        system.reveal(hit.url)
        return true
    }

    func openInDictionary(_ word: String) {
        guard let url = DictionaryLookup.url(for: word) else { return }
        onClose?()
        system.open(url)
    }

    func copyAnswer() {
        guard let text = answer?.text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Search

    private func queryChanged() {
        cancelConfirmation()
        cancelDeferredReturn()
        selection = 0
        selectionIsUsers = false
        selectionFollowsPointer = false
        marksSelection = false
        if answer != nil, answer?.isResponding == false { answer = nil }
        // Until the new search lands only the hits that still match stay, so Return never runs a
        // hit from an earlier, shorter query.
        let text = trimmedQuery
        if !text.isEmpty {
            let matching = settings().matching
            apps = apps.filter { $0.matches(text, matching) }
            // A `kind:` word filters by type, not by name.
            let name = AssistantSearch.kindFilter(text).rest
            files = files.filter { AssistantMatch.matches($0.name, name, matching) }
        }
        search(now: false)
    }

    /// Reads what the current list needs: the lists behind a suggestion once, then (for the root
    /// and Files) the query's hits after a short pause.
    private func search(now: Bool) {
        generation &+= 1
        let generation = generation
        let text = trimmedQuery
        let category = category
        searchTask?.cancel()
        searchPending = false
        loadLists(for: category, query: text)
        switch category {
        case .system:
            // Filtered in memory as the user types; the switches' states are read once.
            readStates(of: commands(matching: ""))
            return
        case .applications, .actions, .clipboard, .windows, .emoji:
            // Filtered in memory as the user types.
            return
        case .files:
            break
        case .people:
            // The people come from Contacts for the query; the events are filtered in memory.
            contactsAccess = sources.contactsAccess()
            let sources = sources
            let delay = settings().searchDelay
            guard contactsAccess == .granted, !text.isEmpty else {
                contacts = []
                return
            }
            searchPending = true
            searchTask = Task { [weak self] in
                if !now, delay > 0 {
                    try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(20))
                    guard !Task.isCancelled else { return }
                }
                let found = await sources.contacts(text, 30)
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                self.replaceLists { self.contacts = found }
                self.searchPending = false
                if self.deferredReturn != nil {
                    self.cancelDeferredReturn()
                    self.runSelection()
                }
            }
            return
        case nil:
            guard !text.isEmpty else {
                apps = []
                files = []
                definition = nil
                contacts = []
                languageUnsupported = false
                return
            }
            // A currency typed for the first time today: the rates are fetched, the query is not sent.
            if settings().convertsCurrency, currencyRates == nil, ratesTask == nil, AssistantCalculator.currencyQuery(text) != nil {
                let sources = sources
                ratesTask = Task { [weak self] in
                    let rates = await sources.rates()
                    guard !Task.isCancelled, let self else { return }
                    self.ratesTask = nil
                    if let rates { self.replaceLists { self.currencyRates = rates } }
                }
            }
        }
        let settings = settings()
        let withFiles = category == .files || (filesEnabled && settings.showsFiles && !settings.folders.isEmpty)
        let sources = sources
        let hitLimit = settings.resultsPerKind
        let scope = FileScope(settings)
        let delay = settings.searchDelay
        // The app list in memory in every mode (it has the apps Spotlight's name query misses:
        // "device hub" for DeviceHub, v0.4.10), with Spotlight's other names for them.
        searchPending = true
        let inMemoryApps: [AssistantHit]? = allApps.isEmpty ? nil
            : Array(AssistantSearch.rank(allApps.filter { $0.matches(text, settings.matching) }, for: text)
                .prefix(hitLimit))
        // Read from Spotlight, the list in memory finds what its name query would (other names
        // included): the apps come from it at once, and the index is not asked at every keystroke
        // (each query ~20–30 mJ billed by Spotlight's daemon, measured).
        let appsFromMemory = inMemoryApps != nil && allAppsRead != nil && category == nil
        // Asked of the privacy database once in a while, not at every keystroke.
        let readsPeople = settings.showsPeople && text.count >= 2 && recentContactsAccess() == .granted
        let readsDefinition = category == nil && settings.showsDefinitions && DictionaryLookup.isWord(text)
        let asksServices = category == .files || withFiles || readsDefinition || readsPeople || !appsFromMemory
        // One search of the system's services at a time: the newest waits for the one in flight
        // (which, already asked, cannot be stopped) instead of running next to it.
        let previous = searchTask
        // At utility priority: the sources' work (Spotlight, Contacts, the dictionary, the icons)
        // runs on the efficiency cores. At the main thread's user-initiated priority every
        // keystroke's search spread over several performance cores at once (Energy Impact ~80 for
        // a typed word, measured), for results that came only a few milliseconds sooner.
        searchTask = Task(priority: .utility) { [weak self] in
            if !now, delay > 0 {
                try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(20))
                guard !Task.isCancelled else { return }
            }
            if appsFromMemory, let inMemoryApps {
                await AssistantIcons.prepare(inMemoryApps.map(AssistantIcons.source(for:)))
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                self.replaceLists { self.apps = inMemoryApps }
                guard asksServices else {
                    self.finishSearch(text: text, category: category, settings: settings, hitLimit: hitLimit)
                    return
                }
            }
            // The services only once the typing pauses: while letters keep coming, each query's
            // answer was replaced by the next one's before anyone could read it.
            if !now, delay < Self.servicesPause {
                try? await Task.sleep(for: .seconds(Self.servicesPause - delay), tolerance: .milliseconds(20))
                guard !Task.isCancelled else { return }
            }
            await previous?.value
            guard !Task.isCancelled else { return }
            // The first files read may wait on the system's folder-access prompt.
            let asksAccess = withFiles && self?.filesEnabled == false
            if asksAccess { self?.fileAccessReads += 1 }
            var foundApps: [AssistantHit] = inMemoryApps ?? []
            var foundFiles: [AssistantHit] = []
            var foundDefinition: AssistantDefinition?
            var foundContacts: [AssistantContact] = []
            var unsupported = false
            if category == .files {
                foundFiles = text.isEmpty ? await sources.recentFiles(scope) : await sources.files(text, 30, scope)
            } else {
                async let apps = appsFromMemory ? foundApps : Self.apps(text, hitLimit, inMemory: inMemoryApps, sources: sources)
                async let files = withFiles ? sources.files(text, hitLimit, scope) : []
                // A word alone is looked up; the people only once they were allowed.
                async let definition = readsDefinition ? sources.define(text) : nil
                async let contacts = readsPeople ? sources.contacts(text, hitLimit) : []
                (foundApps, foundFiles, foundDefinition, foundContacts) = await (apps, files, definition, contacts)
                // Once per pause, not per keystroke: the recogniser is not free.
                unsupported = sources.isUnsupportedLanguage(text)
            }
            guard let self else { return }
            if asksAccess {
                // Hits mean the folders were readable: from now on files come with every query.
                if !foundFiles.isEmpty { self.filesEnabled = true }
                self.fileAccessReads -= 1
                if self.fileAccessReads == 0 { self.onFileAccessSettled?() }
            }
            guard !Task.isCancelled, self.generation == generation else { return }
            // The rows come with their icons, drawn off the main thread.
            await AssistantIcons.prepare((foundApps + foundFiles).map(AssistantIcons.source(for:)))
            guard !Task.isCancelled, self.generation == generation else { return }
            self.replaceLists {
                self.apps = foundApps
                self.files = foundFiles
                self.definition = foundDefinition
                self.contacts = foundContacts
                self.languageUnsupported = unsupported
            }
            self.finishSearch(text: text, category: category, settings: settings, hitLimit: hitLimit)
            DiagnosticsFlow.record("siri: \"\(text)\" in \(category.map { String(describing: $0) } ?? "root") → \(foundApps.count) apps, \(foundFiles.count) files (\(settings.matching))")
        }
    }

    /// How long the typing must pause before Spotlight's files, the dictionary and Contacts are
    /// asked (the lists in memory follow every keystroke).
    static let servicesPause: TimeInterval = 0.15

    /// The search's results are in: the switches' states, and a Return that waited for them.
    private func finishSearch(text: String, category: AssistantCategory?, settings: SiriSettings, hitLimit: Int) {
        // The switches the root lists show their state (read once the typing pauses).
        if category == nil, settings.showsSystem {
            readStates(of: Array(commands(matching: text).prefix(min(hitLimit, Self.rootActionLimit))))
        }
        searchPending = false
        if deferredReturn != nil {
            cancelDeferredReturn()
            runSelection()
        }
    }

    /// The root's apps: already matched in memory, or from Spotlight.
    nonisolated private static func apps(_ text: String, _ limit: Int, inMemory: [AssistantHit]?,
                                         sources: AssistantSources) async -> [AssistantHit] {
        let indexed = await sources.apps(text, limit)
        guard let inMemory else { return indexed }
        return Array(AssistantSearch.rank(AssistantSearch.merged(inMemory, indexed), for: text).prefix(limit))
    }

    /// Every app for Applications; the shortcuts for Actions, the panes for System, the running
    /// apps for Windows and the emoji for Emoji; all but the apps for root queries too.
    private func loadLists(for category: AssistantCategory?, query: String) {
        let settings = settings()
        let rootQuery = category == nil && !query.isEmpty
        loadMenus(rootQuery: rootQuery && query.count >= 3, settings: settings)
        loadWindows(for: category, rootQuery: rootQuery, settings: settings)
        let isStale = allAppsRead.map { Date().timeIntervalSince($0) > Self.appsLifetime } ?? true
        // Root queries take their apps from it as well (`search`): an old list is read again then too.
        let needsApps = (category == .applications && (allApps.isEmpty || isStale)) || (rootQuery && !allApps.isEmpty && isStale)
        let needsShortcuts = shortcuts == nil && settings.includesShortcuts && (category == .actions || rootQuery)
        let needsPanes = settingsPanes == nil && settings.showsSystem && (category == .system || rootQuery)
        // Built once per opening, at its first use, and dropped `keepDuration` after `end()`.
        let needsEmoji = emoji == nil && settings.showsEmoji && (category == .emoji || rootQuery)
        let needsBookmarks = bookmarks == nil && settings.showsBookmarks && rootQuery
        guard needsApps || needsShortcuts || needsPanes || needsEmoji || needsBookmarks, loadTask == nil else { return }
        let sources = sources
        // At utility priority, as the searches: the lists are read by Spotlight and the system's
        // tables off the main thread, and nobody waits on them within a frame (the gallery shows
        // the list it has meanwhile).
        loadTask = Task(priority: .utility) { [weak self] in
            async let apps = needsApps ? sources.allApps() : []
            async let shortcuts = needsShortcuts ? sources.shortcuts() : nil
            async let panes = needsPanes ? sources.settingsPanes() : nil
            async let emoji = needsEmoji ? EmojiIndex.build(sources.emoji) : nil
            async let bookmarks = needsBookmarks ? sources.bookmarks() : nil
            let (foundApps, foundShortcuts, foundPanes, foundEmoji, foundBookmarks) = await (apps, shortcuts, panes, emoji, bookmarks)
            // The rows come with their icons, drawn off the main thread.
            var icons = Set<AssistantIcons.Source>()
            if foundShortcuts?.isEmpty == false { icons.insert(AssistantIcons.shortcutsSource) }
            if foundPanes?.isEmpty == false { icons.insert(AssistantIcons.systemSettingsSource) }
            if !icons.isEmpty { await AssistantIcons.prepare(Array(icons)) }
            guard !Task.isCancelled, let self else { return }
            self.loadTask = nil
            self.replaceLists {
                if needsApps {
                    self.allApps = foundApps
                    self.allAppsRead = Date()
                }
                if needsShortcuts { self.shortcuts = foundShortcuts ?? [] }
                if needsPanes { self.settingsPanes = foundPanes ?? [] }
                if needsEmoji { self.emoji = foundEmoji ?? EmojiIndex([]) }
                if needsBookmarks { self.bookmarks = foundBookmarks ?? [] }
            }
            // Asked for something else while this ran (the task is single-flight).
            self.loadLists(for: self.category, query: self.trimmedQuery)
        }
    }

    /// The front app's menu commands, once per opening, at utility priority.
    private func loadMenus(rootQuery: Bool, settings: SiriSettings) {
        guard rootQuery, settings.showsActions, menuItems == nil, menuTask == nil, let pid = menuApp else { return }
        let sources = sources
        menuTask = Task(priority: .utility) { [weak self] in
            let found = await sources.menuItems(pid)
            guard !Task.isCancelled, let self else { return }
            self.replaceLists { self.menuItems = found }
        }
    }

    /// The menu commands whose name (or quick key) matches, those starting with the query first.
    private func menuItems(matching text: String) -> [AssistantMenuItem] {
        guard let menuItems, !text.isEmpty else { return [] }
        let matching = settings().matching
        let found = menuItems.filter { AssistantMatch.matches($0.title, text, matching) }
        return found.filter { AssistantMatch.startsName($0.title, text) } + found.filter { !AssistantMatch.startsName($0.title, text) }
    }

    /// The running apps for root queries (no Accessibility), their windows' titles only for ⌘6.
    private func loadWindows(for category: AssistantCategory?, rootQuery: Bool, settings: SiriSettings) {
        guard settings.showsWindows, windowsTask == nil else { return }
        let titles = category == .windows
        guard titles ? !windowsHaveTitles : (rootQuery && windows == nil) else { return }
        let sources = sources
        windowsTask = Task { [weak self] in
            let found = await sources.windows(titles)
            await AssistantIcons.prepare(found.map { AssistantIcons.Source.app($0.appPath) })
            guard !Task.isCancelled, let self else { return }
            self.windowsTask = nil
            self.replaceLists {
                self.windows = found
                self.windowsHaveTitles = titles
            }
            // ⌘6 opened while the root's list was read.
            self.loadWindows(for: self.category, rootQuery: false, settings: self.settings())
        }
    }

    /// Swaps in new results. A row the user picked stays picked where it still exists; otherwise
    /// the top row is selected, as a new search should.
    private func replaceLists(_ update: () -> Void) {
        let before = rows
        let picked = selectionIsUsers && before.indices.contains(selection) ? before[selection].id : nil
        update()
        let after = rows
        if let picked, let index = after.firstIndex(where: { $0.id == picked }) {
            selection = index
        } else {
            selection = min(selectionIsUsers ? selection : 0, max(after.count - 1, 0))
        }
    }

    /// For tests: waits for the searches and loads in flight.
    func settle() async {
        // A finished load may start the next one (the task is single-flight).
        while let task = loadTask ?? windowsTask ?? searchTask {
            await task.value
            if task == loadTask { loadTask = nil }
            if task == windowsTask { windowsTask = nil }
            if task == searchTask { searchTask = nil }
        }
    }

    // MARK: Language

    /// First words that make a query a question (English and Hungarian).
    nonisolated static let questionWords: Set<String> = [
        "what", "who", "whom", "whose", "why", "how", "when", "where", "which", "is", "are", "was", "were",
        "can", "could", "does", "do", "did", "will", "would", "should", "explain", "tell", "define",
        "mi", "mit", "mik", "ki", "kit", "kik", "miért", "hogyan", "hogy", "mikor", "hol", "honnan", "hova",
        "melyik", "mennyi", "hány", "milyen", "mekkora", "meddig", "mennyibe", "van", "lehet", "kell",
        "magyarázd", "mondd", "írj", "számold",
    ]

    /// A question rather than a name to look up: it ends with a question mark, starts with a
    /// question word, or is a sentence (three words or more). "safari" and "system settings" are
    /// look-ups; "what is 2+2" and "mennyi az idő" are questions.
    nonisolated static func looksLikeQuestion(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if text.hasSuffix("?") { return true }
        let words = text.split(whereSeparator: \.isWhitespace)
        if words.count >= 3 { return true }
        guard words.count >= 2, let first = words.first else { return false }
        return questionWords.contains(first.lowercased())
    }

    /// True only when the recogniser is confident (short words are unreliable, measured) and the
    /// model's supported languages do not include it. Compared by base language: the recogniser
    /// says "zh-Hans" where the model lists "zh".
    nonisolated static func isUnsupportedLanguage(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.8 else { return false }
        let base = language.rawValue.split(separator: "-").first.map(String.init) ?? language.rawValue
        let supported = Set(SystemLanguageModel.default.supportedLanguages.compactMap { $0.languageCode?.identifier })
        return !supported.contains(base)
    }

    private static func describe(_ error: any Error) -> String {
        if let error = error as? LanguageModelError {
            return String(localized: "Apple Intelligence could not answer this (\(String(describing: error))).")
        }
        return String(localized: "Apple Intelligence could not answer: \(error.localizedDescription)")
    }
}

/// Matching names against what the user typed, the way Spotlight does: case and accents do not
/// matter, and every typed word must start a word of the name (or the name itself).
nonisolated enum AssistantMatch {
    /// Whether `name` matches what was typed, in the user's matching mode (`SiriMatching`).
    static func matches(_ name: String, _ query: String, _ mode: SiriMatching = .wordStart) -> Bool {
        let query = folded(query).trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let original = name
        let name = folded(name)
        if name.hasPrefix(query) { return true }
        let words = keptWords(of: original)
        let tokens = query.split(whereSeparator: \.isWhitespace)
        let wordStarts = tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } }
        // Quick keys, as Spotlight's: the first letters of the name's words, all of them ("vsc"
        // Visual Studio Code, "ss" System Settings, "se" Send Email).
        if !wordStarts, tokens.count == 1, query.count >= 2, keptInitials(of: original).contains(query) {
            return true
        }
        switch mode {
        case .wordStart:
            return wordStarts
        case .anywhere:
            return wordStarts || tokens.allSatisfy { name.contains($0) }
        case .fuzzy:
            return wordStarts || tokens.allSatisfy { name.contains($0) } || isSubsequence(query.filter { !$0.isWhitespace }, of: name)
        }
    }

    /// Names folded and split into their words, kept: the same few hundred names (apps, panes and
    /// their synonyms, commands) are matched again at every keystroke, and folding them again was
    /// most of Siri's main-thread time while typing (measured). Long texts (copies in Clipboard)
    /// are not kept; the rest goes with the lists a while after Siri closes (`forget`).
    private struct Kept { var names: [String: String] = [:]; var words: [String: [Substring]] = [:]; var initials: [String: [String]] = [:] }
    private static let known = Mutex(Kept())

    private static func folded(_ text: String) -> String {
        guard text.utf8.count <= 256 else { return fold(text) }
        if let kept = known.withLock({ $0.names[text] }) { return kept }
        let folded = fold(text)
        known.withLock { known in
            if known.names.count >= 4096 { known.names.removeAll() }
            known.names[text] = folded
        }
        return folded
    }

    private static func keptWords(of text: String) -> [Substring] {
        guard text.utf8.count <= 256 else { return words(of: text) }
        if let kept = known.withLock({ $0.words[text] }) { return kept }
        let words = words(of: text)
        known.withLock { known in
            if known.words.count >= 4096 { known.words.removeAll() }
            known.words[text] = words
        }
        return words
    }

    /// The name's quick keys: its words' first letters, split at spaces and marks, and again with
    /// capitals inside a word ("DeviceHub" is "dh" too). Only names of two words or more have one.
    private static func keptInitials(of text: String) -> [String] {
        guard text.utf8.count <= 256 else { return [] }
        if let kept = known.withLock({ $0.initials[text] }) { return kept }
        let initials = initials(of: text)
        known.withLock { known in
            if known.initials.count >= 4096 { known.initials.removeAll() }
            known.initials[text] = initials
        }
        return initials
    }

    static func initials(of name: String) -> [String] {
        let whole = fold(name).split { !$0.isLetter && !$0.isNumber }
        var parts: [String] = []
        var current = "", previousWasLower = false
        for character in name {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { parts.append(current) }
                current = ""; previousWasLower = false
                continue
            }
            if character.isUppercase, previousWasLower, !current.isEmpty { parts.append(current); current = "" }
            current.append(character)
            previousWasLower = character.isLowercase
        }
        if !current.isEmpty { parts.append(current) }
        var found: [String] = []
        for words in [whole.map(String.init), parts] where words.count >= 2 {
            let key = fold(String(words.compactMap(\.first)))
            if !found.contains(key) { found.append(key) }
        }
        return found
    }

    static func forget() { known.withLock { $0 = Kept() } }

    /// The name's words, folded: split at spaces and marks, and where a capital follows a small
    /// letter ("DeviceHub" is "device" and "hub": "device hub" found no app, v0.4.10).
    static func words(of name: String) -> [Substring] {
        var words: [String] = []
        var current = ""
        var previousWasLower = false
        for character in name {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current) }
                current = ""
                previousWasLower = false
                continue
            }
            if character.isUppercase, previousWasLower, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
            previousWasLower = character.isLowercase
        }
        if !current.isEmpty { words.append(current) }
        let whole = fold(name).split { !$0.isLetter && !$0.isNumber }
        return whole + words.map { Substring(fold($0)) }.filter { !whole.contains($0) }
    }

    /// The name starts with what was typed ("application" and "appl" start "Applications"); case
    /// and accents do not matter.
    static func startsName(_ name: String, _ query: String) -> Bool {
        let query = folded(query).trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return false }
        return folded(name).hasPrefix(query)
    }

    /// Every character of `needle` in `haystack`, in order ("sfr" in "safari").
    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle[...]
        for character in haystack where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// Siri's icons, looked up and drawn off the main thread and kept while Siri is used (a list
/// re-renders on every keystroke and hover). A row's is the very picture SwiftUI took from the
/// system's full icon (the same pixels on screen), which the rows used to look up, and SwiftUI to
/// draw, on the main thread; a gallery cell's is drawn once at the size it is shown (2x). An app's
/// picture of either kind is kept on disk as well, for the next launch (`IconDiskCache`).
@MainActor enum AssistantIcons {
    /// Where an icon comes from.
    nonisolated enum Source: Hashable, Sendable {
        /// An app's, resolved first: a linked app (Safari in /Applications) shows an alias arrow.
        case app(String)
        /// A folder's own (Downloads, a custom icon), or the plain one.
        case folder(String)
        /// A file's type's, without reading the file.
        case type(String)
    }

    /// A row's icon on a screen of a scale: SwiftUI took the icon's variant for that scale.
    private struct Key: Hashable {
        let source: Source
        let scale: CGFloat
    }

    /// Where app icons are kept across launches: the app's Caches from its start (`AppModel.start`),
    /// nowhere before (tests).
    static var disk = IconDiskCache(folder: nil)

    private static var icons: [Key: NSImage] = [:]
    private static var thumbnails: [String: NSImage] = [:]
    /// The scale the rows last showed at, which `prepare` draws for.
    private static var rowScale: CGFloat = 2

    /// The rows' icon side.
    nonisolated static let rowIconSize: CGFloat = 22

    static func source(for hit: AssistantHit) -> Source {
        switch hit.kind {
        case .app: .app(hit.url.path)
        case .file: .type(hit.contentType ?? UTType.data.identifier)
        case .folder: .folder(hit.url.path)
        }
    }

    static let shortcutsSource = Source.app(AssistantSearch.shortcutsApp)
    static let systemSettingsSource = Source.app("/System/Applications/System Settings.app")

    /// A row's icon: drawn ahead with the rows' search (`prepare`), or here the first time.
    static func icon(for hit: AssistantHit, scale: CGFloat) -> NSImage { icon(source(for: hit), scale: scale) }

    static func shortcuts(scale: CGFloat) -> NSImage { icon(shortcutsSource, scale: scale) }

    static func systemSettings(scale: CGFloat) -> NSImage { icon(systemSettingsSource, scale: scale) }

    /// A running app's (Windows, ⌘6).
    static func app(_ path: String, scale: CGFloat) -> NSImage { icon(.app(path), scale: scale) }

    private static func icon(_ source: Source, scale: CGFloat) -> NSImage {
        rowScale = scale
        let key = Key(source: source, scale: scale)
        if let icon = icons[key] { return icon }
        // On the main thread: read from disk at most, never written (`prepare` keeps them).
        let icon = rowPicture(source, scale: scale, disk: disk, writes: false).map { rowImage($0, scale: scale) } ?? systemIcon(source)
        icons[key] = icon
        return icon
    }

    private static func rowImage(_ cgImage: CGImage, scale: CGFloat) -> NSImage {
        NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
    }

    /// Draws the icons of rows about to be shown (a search's hits) before they show.
    static func prepare(_ sources: [Source]) async {
        let scale = rowScale, disk = disk
        let missing = Set(sources).filter { icons[Key(source: $0, scale: scale)] == nil }
        guard !missing.isEmpty else { return }
        let pictures = await Thrifty.run {
            missing.compactMap { source in rowPicture(source, scale: scale, disk: disk, writes: true).map { (source, $0) } }
        }
        for (source, picture) in pictures {
            let key = Key(source: source, scale: scale)
            // A row may have drawn it meanwhile: the one it shows stays.
            if icons[key] == nil { icons[key] = rowImage(picture, scale: scale) }
        }
    }

    /// A gallery icon, drawn once at the size it is shown (2x) off the main thread: a hundred full
    /// icons, looked up and scaled on the main thread as the gallery scrolled in, were what made
    /// it slow to open. Only cells on screen ask (the grid is lazy).
    static func cachedThumbnail(for hit: AssistantHit, points: CGFloat) -> NSImage? { thumbnails[thumbnailKey(hit, points)] }

    /// Per size: the gallery's icon size can change.
    private static func thumbnailKey(_ hit: AssistantHit, _ points: CGFloat) -> String { "\(Int(points)) \(hit.url.path)" }

    static func thumbnail(for hit: AssistantHit, points: CGFloat, prewarming: Bool = false) async -> NSImage? {
        let key = thumbnailKey(hit, points)
        if let image = thumbnails[key] { return image }
        let source = Source.app(hit.url.path)
        let pixels = Int(points * 2), disk = disk
        let rendered = prewarming ? await Thrifty.runInBackground { thumbnail(source, pixels: pixels, disk: disk) }
                                  : await render(source, pixels: pixels, disk: disk)
        guard let cgImage = rendered, !Task.isCancelled else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: points, height: points))
        thumbnails[key] = image
        return image
    }

    /// On the `Thrifty` queue: a gallery of icons drawn in parallel from its cells ran every
    /// performance core at full clock (measured 2.2 W for half a second).
    private static func render(_ source: Source, pixels: Int, disk: IconDiskCache) async -> CGImage? {
        await Thrifty.run { thumbnail(source, pixels: pixels, disk: disk) }
    }

    nonisolated private static func systemIcon(_ source: Source) -> NSImage {
        switch source {
        case .app(let path): NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
        case .folder(let path): NSWorkspace.shared.icon(forFile: path)
        case .type(let identifier): NSWorkspace.shared.icon(for: UTType(identifier) ?? .data)
        }
    }

    /// The system icon's own picture for a row: its variant for the row's size at the screen's
    /// scale (48 pixels for 22 points at 2x), which Core Animation scales to the row as it did the
    /// full icon's. An app's comes from disk while the app is unchanged (`IconDiskCache`).
    nonisolated private static func rowPicture(_ source: Source, scale: CGFloat, disk: IconDiskCache, writes: Bool) -> CGImage? {
        let picture = {
            var rect = CGRect(x: 0, y: 0, width: rowIconSize, height: rowIconSize)
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            return systemIcon(source).cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: transform])
        }
        guard case .app(let path) = source else { return picture() }
        return disk.image(forApp: path, variant: "row \(scale)x", style: IconDiskCache.iconStyle(), writes: writes, draw: picture)
    }

    /// A gallery thumbnail: from disk while the app is unchanged, else drawn (`draw`).
    nonisolated private static func thumbnail(_ source: Source, pixels: Int, disk: IconDiskCache) -> CGImage? {
        guard case .app(let path) = source else { return draw(source, pixels: pixels) }
        return disk.image(forApp: path, variant: "gallery \(pixels)px", style: IconDiskCache.iconStyle()) {
            draw(source, pixels: pixels)
        }
    }

    nonisolated private static func draw(_ source: Source, pixels: Int) -> CGImage? {
        var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        guard let full = systemIcon(source).cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      // Core Animation's own layout (BGRA), as the wallpapers: it
                                      // copies an RGBA picture into one before drawing it.
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(full, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }

    /// The rows' icons go; the gallery's thumbnails stay, so the gallery never draws a hundred
    /// icons again at an opening.
    static func purge() {
        icons = [:]
    }

    private static var purgeTask: Task<Void, Never>?
    /// How long the icons outlive the last opening of Siri.
    static let keep: Duration = .seconds(10 * 60)

    /// Frees the icons once Siri has not been opened for `keep`; an opening meanwhile keeps them.
    static func purgeLater() {
        purgeTask?.cancel()
        purgeTask = Task {
            try? await Task.sleep(for: keep, tolerance: .seconds(60))
            guard !Task.isCancelled else { return }
            purge()
            purgeTask = nil
        }
    }

    /// When the icons on disk were last tidied.
    static var diskTidied: Date?
    /// How often at most.
    static let tidyInterval: TimeInterval = 24 * 60 * 60

    /// Tidies the icons kept on disk (`IconDiskCache.purge`) on the background queue, at most once
    /// every `tidyInterval`: nil when it was done more recently.
    @discardableResult static func tidyDisk() -> Task<Void, Never>? {
        if let diskTidied, Date().timeIntervalSince(diskTidied) < tidyInterval { return nil }
        diskTidied = Date()
        let disk = disk
        return Task { await Thrifty.runInBackground { disk.purge(style: IconDiskCache.iconStyle()) } }
    }
}

/// A web address typed into the field: with its scheme, or a bare host ("github.com/apple",
/// "localhost:3000"). A file name ("notes.md", "report.pdf") is not one: a top-level domain must be
/// two letters (a country) or a common one, and not a file extension.
nonisolated enum AssistantURL {
    static let commonDomains: Set<String> = [
        "com", "org", "net", "io", "dev", "app", "ai", "co", "edu", "gov", "info", "me", "tv", "xyz", "site", "online",
        "tech", "store", "blog", "news", "cloud", "page", "so", "gg", "ly", "fm", "biz", "shop", "live", "design",
    ]
    /// Two-letter file extensions that are also countries' domains.
    static let fileExtensions: Set<String> = ["md", "py", "js", "ts", "rb", "sh", "cs", "kt", "db", "gz", "ps"]

    static func url(from text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2048, !text.contains(where: \.isWhitespace) else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = URL(string: text), url.host?.isEmpty == false else { return nil }
            return url
        }
        guard !text.contains("@") else { return nil }
        var host = String(text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        var hasPort = false
        if let colon = host.lastIndex(of: ":") {
            let port = host[host.index(after: colon)...]
            guard !port.isEmpty, port.allSatisfy(\.isNumber) else { return nil }
            host = String(host[..<colon])
            hasPort = true
        }
        let labels = host.lowercased().split(separator: ".", omittingEmptySubsequences: false)
        let isLocal = host.lowercased() == "localhost"
        let isAddress = labels.count == 4 && labels.allSatisfy { UInt8($0) != nil }
        if isLocal || isAddress {
            // A bare "1.2.3.4" is as likely a version number.
            guard isLocal || hasPort || text.contains("/") else { return nil }
            return URL(string: "http://" + text)
        }
        guard labels.count >= 2, labels.allSatisfy({ label in
            !label.isEmpty && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }), let top = labels.last.map(String.init) else { return nil }
        let isCountry = top.count == 2 && top.allSatisfy(\.isLetter) && !fileExtensions.contains(top)
        guard isCountry || commonDomains.contains(top) else { return nil }
        return URL(string: "https://" + text)
    }

    /// "github.com/apple", as the row names it.
    static func display(_ url: URL) -> String {
        var text = url.absoluteString
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) { text.removeFirst(scheme.count) }
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }
}

/// Hand-offs to other apps.
@MainActor enum AssistantActions {
    static func webSearchURL(for query: String, engine: SiriSearchEngine = .google) -> URL? {
        handOffURL(engine.base, query: query)
    }

    static func chatGPTURL(for query: String) -> URL? {
        handOffURL("https://chatgpt.com/", query: query)
    }

    /// `base?q=query`. '+' is legal in a query so URLComponents leaves it, but search boxes read it
    /// as a space ("c++" would arrive as "c  "), so it is encoded too.
    private static func handOffURL(_ base: String, query: String) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        let encoded = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = encoded
        return components?.url
    }

    /// A new email or message through the system's sharing services (Mail, Messages), which fill
    /// in the text; Maps by its URL.
    static func perform(_ compose: AssistantCompose) {
        let service: NSSharingService? = switch compose.kind {
        case .email: NSSharingService(named: .composeEmail)
        case .message: NSSharingService(named: .composeMessage)
        case .maps: nil
        }
        if let service {
            if compose.isAddress { service.recipients = [compose.text] }
            let items: [Any] = compose.text.isEmpty || compose.isAddress ? [] : [compose.text]
            if service.canPerform(withItems: items) {
                service.perform(withItems: items)
                return
            }
        }
        if let url = compose.url { NSWorkspace.shared.open(url) }
    }

    /// Runs one of the user's shortcuts in the background, the way the Shortcuts menu does.
    static func runShortcut(named name: String) {
        do {
            try Process.run(URL(fileURLWithPath: AssistantSearch.shortcutsTool), arguments: ["run", name])
            Log.app.info("assistant: ran a shortcut")
        } catch {
            Log.app.error("assistant: shortcut failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The system's dictation into the focused field (the mic in the field).
    static func startDictation() {
        NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
    }
}


/// Spotlight's quick actions that take what follows them: a new email, a new message, Maps.
nonisolated struct AssistantCompose: Hashable, Sendable {
    nonisolated enum Kind: String, Sendable, CaseIterable { case email, message, maps }

    let kind: Kind
    /// What follows the action's word.
    let text: String
    /// Typed by its quick key ("se", "sm", "sim"), not by name.
    let isQuickKey: Bool

    /// The words that start each, its quick key first.
    static let words: [Kind: [String]] = [
        .email: ["se", "email", "e-mail", "mail", "level"],
        .message: ["sm", "message", "imessage", "msg", "uzenet"],
        .maps: ["sim", "maps", "map", "terkep", "directions"],
    ]

    static func parse(_ query: String) -> AssistantCompose? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let first = trimmed.prefix { !$0.isWhitespace }
        let word = String(first).lowercased().folding(options: .diacriticInsensitive, locale: nil)
        guard let kind = Kind.allCases.first(where: { words[$0]?.contains(word) == true }) else { return nil }
        let text = trimmed.dropFirst(first.count).trimmingCharacters(in: .whitespaces)
        // Maps needs something to look for.
        if kind == .maps, text.isEmpty { return nil }
        return AssistantCompose(kind: kind, text: text, isQuickKey: words[kind]?.first == word)
    }

    var title: String {
        switch kind {
        case .email: text.isEmpty ? String(localized: "Send Email") : String(localized: "Send Email: “\(text)”")
        case .message: text.isEmpty ? String(localized: "Send Message") : String(localized: "Send Message: “\(text)”")
        case .maps: String(localized: "Search Maps for “\(text)”")
        }
    }

    var symbol: String {
        switch kind {
        case .email: "envelope.fill"
        case .message: "message.fill"
        case .maps: "map.fill"
        }
    }

    /// What follows is an email address alone: the recipient.
    var isAddress: Bool { kind == .email && !text.contains(" ") && text.contains("@") }

    /// Where it goes when the sharing service cannot (an address alone is the recipient; anything
    /// else is the text).
    var url: URL? {
        var components = URLComponents()
        switch kind {
        case .email:
            components.scheme = "mailto"
            if !text.contains(" "), text.contains("@") { components.path = text }
            else if !text.isEmpty { components.queryItems = [URLQueryItem(name: "body", value: text)] }
        case .message:
            components.scheme = "sms"
            components.path = ""
            if !text.isEmpty { components.queryItems = [URLQueryItem(name: "body", value: text)] }
        case .maps:
            components.scheme = "maps"
            components.queryItems = [URLQueryItem(name: "q", value: text)]
        }
        return components.url
    }
}
