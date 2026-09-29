import AppKit
import FoundationModels
import NaturalLanguage
import UniformTypeIdentifiers

/// The suggestions shown before anything is typed, as in the system's Search window: each one
/// lists everything of its kind (⌘1, ⌘2, ⌘3) and the field then filters that list.
nonisolated enum AssistantCategory: Int, CaseIterable, Hashable, Sendable {
    case applications = 1, files, actions, clipboard

    /// What the user may type to find the suggestion itself: its title, and its English names in
    /// any language (the title is localized).
    var searchNames: [String] {
        let english: [String] = switch self {
        case .applications: ["Applications", "Apps"]
        case .files: ["Files", "Documents"]
        case .actions: ["Actions", "Shortcuts"]
        case .clipboard: ["Clipboard", "Pasteboard", "Copied"]
        }
        let title = switch self {
        case .applications: String(localized: "Applications")
        case .files: String(localized: "Files")
        case .actions: String(localized: "Actions")
        case .clipboard: String(localized: "Clipboard")
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
    /// A sum or a unit conversion worked out from the query (Return copies the result).
    case calculation(AssistantCalculation)
    /// The query is a web address: Return opens it.
    case openURL(URL)
    case askIntelligence
    case searchWeb
    case askChatGPT

    var id: String {
        switch self {
        case .category(let category): "category:\(category.rawValue)"
        case .hit(let hit): "hit:\(hit.url.path)"
        case .action(let action): "action:\(action.id)"
        case .clip(let item): "clip:\(item.id)"
        case .calculation: "calculation"
        case .openURL: "url"
        case .askIntelligence: "ask"
        case .searchWeb: "web"
        case .askChatGPT: "chatgpt"
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

    static let live = AssistantSources(
        apps: { await AssistantSearch.apps(matching: $0, limit: $1) },
        files: { await AssistantSearch.files(matching: $0, limit: $1, scope: $2) },
        recentFiles: { await AssistantSearch.recentFiles(scope: $0) },
        allApps: { await AssistantSearch.allApps() },
        shortcuts: { await AssistantSearch.shortcuts() },
        isUnsupportedLanguage: { AssistantModel.isUnsupportedLanguage($0) }
    )
}

/// Where files are looked for (Settings ▸ Siri ▸ Files) and how a name must match.
nonisolated struct FileScope: Sendable, Equatable {
    var paths: [String]
    /// The query may sit anywhere in the name (else at a word's start).
    var anywhere: Bool
    /// How far back the recent files go.
    var days: Int

    init(paths: [String] = SiriFolder.allCases.map(\.path), anywhere: Bool = false, days: Int = 30) {
        self.paths = paths
        self.anywhere = anywhere
        self.days = days
    }

    init(_ settings: SiriSettings) {
        self.init(paths: SiriFolder.allCases.filter { settings.folders.contains($0) }.map(\.path),
                  anywhere: settings.matching != .wordStart, days: settings.recentDays)
    }
}

/// Siri in the notch: the query, the live search, the list's selection, and answers from the
/// on-device model. Everything is torn down when the assistant closes (`end()`), so nothing runs
/// while it is not on screen.
@Observable final class AssistantModel {
    /// Typed by the user; every change re-runs the search after a short pause.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            queryChanged()
        }
    }
    /// The suggestion the user opened (⌘1–⌘4); nil is the root.
    private(set) var category: AssistantCategory?
    /// Root search hits.
    private(set) var apps: [AssistantHit] = []
    /// Root search hits, or the Files list (recent files, or the ones matching the query).
    private(set) var files: [AssistantHit] = []
    /// Every app, most recently used first: the Applications gallery, filtered in memory.
    private(set) var allApps: [AssistantHit] = []
    /// When `allApps` was read from Spotlight: it is kept across openings (asking Spotlight and
    /// drawing the icons again on every opening of the gallery was most of its energy, measured)
    /// and read again in the background once it is older than `appsLifetime`.
    @ObservationIgnored private var allAppsRead: Date?
    static let appsLifetime: TimeInterval = 10 * 60
    /// The user's shortcuts, read once per opening.
    private(set) var shortcuts: [String]?
    private(set) var selection = 0
    /// Shown instead of the list while present.
    private(set) var answer: AssistantAnswer?
    /// Apple Intelligence can answer on this Mac.
    private(set) var intelligenceAvailable = false
    /// The query's language is one the on-device model does not support (it then answers poorly
    /// or refuses, measured with Hungarian), so the "Ask" row moves down.
    private(set) var languageUnsupported = false
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
    var isAwaitingFileAccess: Bool { fileAccessReads > 0 }

    /// The rows can be seen and chosen (the field alone shows none).
    private var rowsAreShowing: Bool { needsList || revealsSuggestions || hoverReveals }

    var rows: [AssistantRow] {
        let text = trimmedQuery
        let settings = settings()
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
            let items = clipboard()
            guard !text.isEmpty else { return items.map(AssistantRow.clip) }
            return items.filter { AssistantMatch.matches($0.text, text, .anywhere) }.map(AssistantRow.clip)
        case nil:
            guard !text.isEmpty else { return settings.categories.map(AssistantRow.category) }
            // A sum or a conversion is worked out at once and comes first, above everything, as in
            // Spotlight: "12 + 30 * 2" had five words and went to Apple Intelligence (seen, v0.4.5).
            // A typed web address first of all, as in Spotlight ("github.com", Return).
            let calculation = (AssistantURL.url(from: text).map { [AssistantRow.openURL($0)] } ?? [])
                + (calculation(for: text).map { [AssistantRow.calculation($0)] } ?? [])
            let hits = (settings.showsApplications ? apps.map(AssistantRow.hit) : [])
                + (settings.showsFiles ? files.map(AssistantRow.hit) : [])
                + (settings.showsActions ? actions(matching: text).prefix(Self.rootActionLimit).map(AssistantRow.action) : [])
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
            var rows = calculation + (hitStarts ? hits + named : named + hits)
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
        let result = AssistantCalculator.calculate(text)
        calculated = (text, result)
        return result
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

    /// The copied item the selection is on, in Clipboard (the field shows it, as Spotlight does).
    var selectedClip: ClipboardItem? {
        guard category == .clipboard, answer == nil else { return nil }
        let rows = rows
        guard rows.indices.contains(selection), case .clip(let item) = rows[selection] else { return nil }
        return item
    }

    /// ⌘C in Clipboard: the copy the selection is on goes back on the pasteboard, without a click
    /// on it. False when the selection is on none (the key goes on to the field).
    func copySelectedClip() -> Bool {
        guard let item = selectedClip else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        return true
    }

    // MARK: Lifecycle

    /// The assistant opened.
    func begin() {
        end()
        // Read ahead in the background (`prewarm`): the first query loads the framework's model
        // catalogue on the calling thread (~0.1 s on the main thread at the first opening, measured).
        if let known = knownIntelligence {
            intelligenceAvailable = known
            Task { [weak self] in
                let now = await Self.readIntelligence()
                self?.knownIntelligence = now
                if self?.intelligenceAvailable != now { self?.intelligenceAvailable = now }
            }
        } else {
            intelligenceAvailable = Self.readIntelligenceNow()
            knownIntelligence = intelligenceAvailable
        }
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
    /// availability, the app list and the gallery's first icons — done a while after launch on
    /// the background queue (efficiency cores), a little at a time. The first opening then only
    /// builds its views (it cost Energy Impact 130, the app gallery 300, measured cold).
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
            _ = await AssistantIcons.thumbnail(for: hit, points: AssistantIcons.galleryIconSize, prewarming: true)
        }
    }

    /// The assistant closed: cancel everything and forget the query and the lists.
    func end() {
        generation &+= 1
        searchTask?.cancel()
        searchTask = nil
        loadTask?.cancel()
        loadTask = nil
        askTask?.cancel()
        askTask = nil
        category = nil
        query = ""
        apps = []
        files = []
        shortcuts = nil
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
        selection = min(max(selection + delta, 0), count - 1)
        selectionIsUsers = true
        selectionFollowsPointer = false
        marksSelection = true
    }

    func select(_ row: AssistantRow) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        selection = index
        selectionIsUsers = true
        selectionFollowsPointer = true
        marksSelection = false
    }

    /// Return: runs the selected row. On an answer it asks again if the question was edited; on the
    /// bare field it does nothing (nothing is shown to run).
    func activateSelection() {
        if let answer {
            if !trimmedQuery.isEmpty, trimmedQuery != answer.question { ask() }
            return
        }
        guard rowsAreShowing else { return }
        let rows = rows
        guard rows.indices.contains(selection) else { return }
        perform(rows[selection])
    }

    /// Esc: from an answer back to the list, then clear the query, then leave the suggestion, then
    /// fold the suggestions away, then close.
    func escape() {
        if answer != nil {
            askTask?.cancel()
            answer = nil
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
        open(nil)
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

    func perform(_ row: AssistantRow) {
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
            NSWorkspace.shared.open(hit.url)
        case .action(.island(let action)):
            onCommand?(action.command)
        case .action(.shortcut(let name)):
            onClose?()
            AssistantActions.runShortcut(named: name)
        case .clip(let item):
            onPaste?(item)
        case .openURL(let url):
            onClose?()
            NSWorkspace.shared.open(url)
        case .calculation(let calculation):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(calculation.result, forType: .string)
            onClose?()
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

    func copyAnswer() {
        guard let text = answer?.text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Search

    private func queryChanged() {
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
            apps = apps.filter { AssistantMatch.matches($0.name, text, matching) }
            files = files.filter { AssistantMatch.matches($0.name, text, matching) }
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
        loadLists(for: category, query: text)
        switch category {
        case .applications, .actions, .clipboard:
            // Filtered in memory as the user types.
            return
        case .files:
            break
        case nil:
            guard !text.isEmpty else {
                apps = []
                files = []
                languageUnsupported = false
                return
            }
        }
        let settings = settings()
        let withFiles = category == .files || (filesEnabled && settings.showsFiles && !settings.folders.isEmpty)
        let sources = sources
        let hitLimit = settings.resultsPerKind
        let scope = FileScope(settings)
        let delay = settings.searchDelay
        // The app list in memory in every mode (it has the apps Spotlight's name query misses:
        // "device hub" for DeviceHub, v0.4.10), with Spotlight's hits (other names: localized,
        // alternate) merged in.
        let inMemoryApps: [AssistantHit]? = allApps.isEmpty ? nil
            : Array(AssistantSearch.rank(allApps.filter { AssistantMatch.matches($0.name, text, settings.matching) }, for: text)
                .prefix(hitLimit))
        searchTask = Task { [weak self] in
            if !now, delay > 0 {
                try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(20))
                guard !Task.isCancelled else { return }
            }
            // The first files read may wait on the system's folder-access prompt.
            let asksAccess = withFiles && self?.filesEnabled == false
            if asksAccess { self?.fileAccessReads += 1 }
            var foundApps: [AssistantHit] = []
            var foundFiles: [AssistantHit] = []
            var unsupported = false
            if category == .files {
                foundFiles = text.isEmpty ? await sources.recentFiles(scope) : await sources.files(text, 30, scope)
            } else {
                async let apps = Self.apps(text, hitLimit, inMemory: inMemoryApps, sources: sources)
                async let files = withFiles ? sources.files(text, hitLimit, scope) : []
                (foundApps, foundFiles) = await (apps, files)
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
                self.languageUnsupported = unsupported
            }
            DiagnosticsFlow.record("siri: \"\(text)\" in \(category.map { String(describing: $0) } ?? "root") → \(foundApps.count) apps, \(foundFiles.count) files (\(settings.matching))")
        }
    }

    /// The root's apps: already matched in memory, or from Spotlight.
    nonisolated private static func apps(_ text: String, _ limit: Int, inMemory: [AssistantHit]?,
                                         sources: AssistantSources) async -> [AssistantHit] {
        let indexed = await sources.apps(text, limit)
        guard let inMemory else { return indexed }
        return Array(AssistantSearch.rank(AssistantSearch.merged(inMemory, indexed), for: text).prefix(limit))
    }

    /// Every app for Applications; the shortcuts for Actions and for root queries.
    private func loadLists(for category: AssistantCategory?, query: String) {
        let isStale = allAppsRead.map { Date().timeIntervalSince($0) > Self.appsLifetime } ?? true
        let needsApps = category == .applications && (allApps.isEmpty || isStale)
        let needsShortcuts = shortcuts == nil && settings().includesShortcuts
            && (category == .actions || (category == nil && !query.isEmpty))
        guard needsApps || needsShortcuts, loadTask == nil else { return }
        let sources = sources
        loadTask = Task { [weak self] in
            async let apps = needsApps ? sources.allApps() : []
            async let shortcuts = needsShortcuts ? sources.shortcuts() : nil
            let (foundApps, foundShortcuts) = await (apps, shortcuts)
            // The shortcuts' rows come with their icon, drawn off the main thread.
            if foundShortcuts?.isEmpty == false { await AssistantIcons.prepare([AssistantIcons.shortcutsSource]) }
            guard !Task.isCancelled, let self else { return }
            self.loadTask = nil
            self.replaceLists {
                if needsApps {
                    self.allApps = foundApps
                    self.allAppsRead = Date()
                }
                if needsShortcuts { self.shortcuts = foundShortcuts ?? [] }
            }
            // Asked for something else while this ran (the task is single-flight).
            self.loadLists(for: self.category, query: self.trimmedQuery)
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
        while let task = loadTask ?? searchTask {
            await task.value
            if task == loadTask { loadTask = nil }
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
        let original = name
        let name = fold(name)
        let query = fold(query).trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        if name.hasPrefix(query) { return true }
        let words = Self.words(of: original)
        let tokens = query.split(whereSeparator: \.isWhitespace)
        let wordStarts = tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } }
        switch mode {
        case .wordStart:
            return wordStarts
        case .anywhere:
            return wordStarts || tokens.allSatisfy { name.contains($0) }
        case .fuzzy:
            return wordStarts || tokens.allSatisfy { name.contains($0) } || isSubsequence(query.filter { !$0.isWhitespace }, of: name)
        }
    }

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
        let name = fold(name)
        let query = fold(query).trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return false }
        return name.hasPrefix(query)
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
/// draw, on the main thread; a gallery cell's is drawn once at the size it is shown (2x).
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

    /// A row's icon: drawn ahead with the rows' search (`prepare`), or here the first time.
    static func icon(for hit: AssistantHit, scale: CGFloat) -> NSImage { icon(source(for: hit), scale: scale) }

    static func shortcuts(scale: CGFloat) -> NSImage { icon(shortcutsSource, scale: scale) }

    private static func icon(_ source: Source, scale: CGFloat) -> NSImage {
        rowScale = scale
        let key = Key(source: source, scale: scale)
        if let icon = icons[key] { return icon }
        let icon = rowPicture(source, scale: scale).map { rowImage($0, scale: scale) } ?? systemIcon(source)
        icons[key] = icon
        return icon
    }

    private static func rowImage(_ cgImage: CGImage, scale: CGFloat) -> NSImage {
        NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
    }

    /// Draws the icons of rows about to be shown (a search's hits) before they show.
    static func prepare(_ sources: [Source]) async {
        let scale = rowScale
        let missing = Set(sources).filter { icons[Key(source: $0, scale: scale)] == nil }
        guard !missing.isEmpty else { return }
        let pictures = await Thrifty.run { missing.compactMap { source in rowPicture(source, scale: scale).map { (source, $0) } } }
        for (source, picture) in pictures {
            let key = Key(source: source, scale: scale)
            // A row may have drawn it meanwhile: the one it shows stays.
            if icons[key] == nil { icons[key] = rowImage(picture, scale: scale) }
        }
    }

    /// A gallery icon, drawn once at the size it is shown (2x) off the main thread: a hundred full
    /// icons, looked up and scaled on the main thread as the gallery scrolled in, were what made
    /// it slow to open. Only cells on screen ask (the grid is lazy).
    static func cachedThumbnail(for hit: AssistantHit) -> NSImage? { thumbnails[hit.url.path] }

    /// The gallery cells' icon side.
    static let galleryIconSize: CGFloat = 48

    static func thumbnail(for hit: AssistantHit, points: CGFloat, prewarming: Bool = false) async -> NSImage? {
        let key = hit.url.path
        if let image = thumbnails[key] { return image }
        let source = Source.app(hit.url.path)
        let pixels = Int(points * 2)
        let rendered = prewarming ? await Thrifty.runInBackground { draw(source, pixels: pixels) }
                                  : await render(source, pixels: pixels)
        guard let cgImage = rendered, !Task.isCancelled else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: points, height: points))
        thumbnails[key] = image
        return image
    }

    /// On the `Thrifty` queue: a gallery of icons drawn in parallel from its cells ran every
    /// performance core at full clock (measured 2.2 W for half a second).
    private static func render(_ source: Source, pixels: Int) async -> CGImage? {
        await Thrifty.run { draw(source, pixels: pixels) }
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
    /// full icon's.
    nonisolated private static func rowPicture(_ source: Source, scale: CGFloat) -> CGImage? {
        var rect = CGRect(x: 0, y: 0, width: rowIconSize, height: rowIconSize)
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        return systemIcon(source).cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: transform])
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
