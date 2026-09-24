import AppKit
import FoundationModels
import NaturalLanguage
import UniformTypeIdentifiers

/// The suggestions shown before anything is typed, as in the system's Search window: each one
/// lists everything of its kind (⌘1, ⌘2, ⌘3) and the field then filters that list.
nonisolated enum AssistantCategory: Int, CaseIterable, Hashable, Sendable {
    case applications = 1, files, actions
}

/// What the assistant can do with the query, in the order its list shows them.
nonisolated enum AssistantRow: Hashable, Identifiable, Sendable {
    case category(AssistantCategory)
    case hit(AssistantHit)
    case action(AssistantAction)
    case askIntelligence
    case searchWeb
    case askChatGPT

    var id: String {
        switch self {
        case .category(let category): "category:\(category.rawValue)"
        case .hit(let hit): "hit:\(hit.url.path)"
        case .action(let action): "action:\(action.id)"
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
    var files: @Sendable (_ query: String, _ limit: Int) async -> [AssistantHit]
    var recentFiles: @Sendable () async -> [AssistantHit]
    var allApps: @Sendable () async -> [AssistantHit]
    var shortcuts: @Sendable () async -> [String]
    var isUnsupportedLanguage: @Sendable (String) -> Bool

    static let live = AssistantSources(
        apps: { await AssistantSearch.apps(matching: $0, limit: $1) },
        files: { await AssistantSearch.files(matching: $0, limit: $1) },
        recentFiles: { await AssistantSearch.recentFiles() },
        allApps: { await AssistantSearch.allApps() },
        shortcuts: { await AssistantSearch.shortcuts() },
        isUnsupportedLanguage: { AssistantModel.isUnsupportedLanguage($0) }
    )
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
    /// The suggestion the user opened (⌘1, ⌘2, ⌘3); nil is the root.
    private(set) var category: AssistantCategory?
    /// Root search hits.
    private(set) var apps: [AssistantHit] = []
    /// Root search hits, or the Files list (recent files, or the ones matching the query).
    private(set) var files: [AssistantHit] = []
    /// Every app, most recently used first: the Applications gallery, filtered in memory.
    private(set) var allApps: [AssistantHit] = []
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
    /// Files reads running that may be waiting on the system's folder-access prompt.
    @ObservationIgnored private var fileAccessReads = 0

    /// Pause after a keystroke before searching.
    static let searchDelay: Duration = .milliseconds(120)
    /// Root search: hits of each kind.
    static let rootHitLimit = 3
    static let rootActionLimit = 2
    /// Columns of the Applications gallery (↑/↓ move by a row of them).
    static let galleryColumns = 7
    static let instructions = """
        You are Siri, in the notch of the user's Mac. Answer the question directly and briefly, in a \
        few sentences at most, in the same language as the question. No preamble.
        """

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Something to list: a query, an open suggestion or an answer (the island then shows the list).
    var needsList: Bool { !query.isEmpty || category != nil || answer != nil }

    /// How much of the island the assistant needs: the field alone until the pointer is over it or
    /// ↓ is pressed, the suggestions' height for up to three rows, the full list beyond that (and
    /// for the gallery and answers, which scroll).
    var room: AssistantRoom {
        if answer != nil || category == .applications { return .list }
        if needsList { return rows.count <= AssistantCategory.allCases.count ? .suggestions : .list }
        return revealsSuggestions || isPointerOver ? .suggestions : .field
    }

    /// A folder-access prompt may have the keyboard: the assistant must not close when it loses it.
    var isAwaitingFileAccess: Bool { fileAccessReads > 0 }

    /// The rows can be seen and chosen (the field alone shows none).
    private var rowsAreShowing: Bool { needsList || revealsSuggestions || isPointerOver }

    var rows: [AssistantRow] {
        let text = trimmedQuery
        switch category {
        case .applications:
            guard !text.isEmpty else { return allApps.map(AssistantRow.hit) }
            return AssistantSearch.rank(allApps.filter { AssistantMatch.matches($0.name, text) }, for: text)
                .map(AssistantRow.hit)
        case .files:
            return files.map(AssistantRow.hit)
        case .actions:
            return actions(matching: text).map(AssistantRow.action)
        case nil:
            guard !text.isEmpty else { return AssistantCategory.allCases.map(AssistantRow.category) }
            var rows = apps.map(AssistantRow.hit) + files.map(AssistantRow.hit)
            rows += actions(matching: text).prefix(Self.rootActionLimit).map(AssistantRow.action)
            let ask: [AssistantRow] = intelligenceAvailable ? [.askIntelligence] : []
            if !languageUnsupported { rows += ask }
            rows += [.searchWeb, .askChatGPT]
            if languageUnsupported { rows += ask }
            return rows
        }
    }

    /// The island's actions (Now Playing ones only with a track), then the user's shortcuts.
    func actions(matching text: String) -> [AssistantAction] {
        var island: [IslandAction] = switch mediaState() {
        case .playing: [.pause, .next, .previous]
        case .paused: [.play, .next, .previous]
        case .none: []
        }
        island += [.timer, .stopwatch, .shelf, .customize, .settings]
        let all = island.map(AssistantAction.island) + (shortcuts ?? []).map(AssistantAction.shortcut)
        guard !text.isEmpty else { return all }
        return all.filter { AssistantMatch.matches($0.title, text) }
    }

    // MARK: Lifecycle

    /// The assistant opened.
    func begin() {
        end()
        if case .available = SystemLanguageModel.default.availability {
            intelligenceAvailable = true
        } else {
            intelligenceAvailable = false
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
        allApps = []
        shortcuts = nil
        selection = 0
        selectionIsUsers = false
        answer = nil
        languageUnsupported = false
        revealsSuggestions = false
        AssistantIcons.purge()
    }

    // MARK: Keys

    /// ↑/↓ (and ←/→ in the gallery). The first press on the bare field brings the suggestions down
    /// with the first one selected.
    func moveSelection(by delta: Int) {
        guard answer == nil else { return }
        if !rowsAreShowing {
            revealsSuggestions = true
            selection = 0
            return
        }
        revealsSuggestions = true
        let count = rows.count
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
        selectionIsUsers = true
    }

    func select(_ row: AssistantRow) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        selection = index
        selectionIsUsers = true
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
        files = []
        apps = []
        search(now: true)
    }

    // MARK: Actions

    func perform(_ row: AssistantRow) {
        // From the answer pane the hand-offs take the question that was answered.
        let text = answer?.question ?? trimmedQuery
        switch row {
        case .category(let category):
            open(category)
        case .hit(let hit):
            onClose?()
            NSWorkspace.shared.open(hit.url)
        case .action(.island(let action)):
            onCommand?(action.command)
        case .action(.shortcut(let name)):
            onClose?()
            AssistantActions.runShortcut(named: name)
        case .askIntelligence:
            ask()
        case .searchWeb:
            guard let url = AssistantActions.webSearchURL(for: text) else { return }
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
        guard intelligenceAvailable, !question.isEmpty else { return }
        askTask?.cancel()
        answer = AssistantAnswer(question: question)
        askTask = Task { [weak self] in
            let session = LanguageModelSession(instructions: Self.instructions)
            do {
                let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 400)
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
        if answer != nil, answer?.isResponding == false { answer = nil }
        // Until the new search lands only the hits that still match stay, so Return never runs a
        // hit from an earlier, shorter query.
        let text = trimmedQuery
        if !text.isEmpty {
            apps = apps.filter { AssistantMatch.matches($0.name, text) }
            files = files.filter { AssistantMatch.matches($0.name, text) }
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
        case .applications, .actions:
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
        let withFiles = category == .files || filesEnabled
        let sources = sources
        let hitLimit = Self.rootHitLimit
        searchTask = Task { [weak self] in
            if !now {
                try? await Task.sleep(for: Self.searchDelay, tolerance: .milliseconds(20))
                guard !Task.isCancelled else { return }
            }
            // The first files read may wait on the system's folder-access prompt.
            let asksAccess = withFiles && self?.filesEnabled == false
            if asksAccess { self?.fileAccessReads += 1 }
            var foundApps: [AssistantHit] = []
            var foundFiles: [AssistantHit] = []
            var unsupported = false
            if category == .files {
                foundFiles = text.isEmpty ? await sources.recentFiles() : await sources.files(text, 30)
            } else {
                async let apps = sources.apps(text, hitLimit)
                async let files = withFiles ? sources.files(text, hitLimit) : []
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
            self.replaceLists {
                self.apps = foundApps
                self.files = foundFiles
                self.languageUnsupported = unsupported
            }
        }
    }

    /// Every app for Applications; the shortcuts for Actions and for root queries.
    private func loadLists(for category: AssistantCategory?, query: String) {
        let needsApps = category == .applications && allApps.isEmpty
        let needsShortcuts = shortcuts == nil && (category == .actions || (category == nil && !query.isEmpty))
        guard needsApps || needsShortcuts, loadTask == nil else { return }
        let sources = sources
        loadTask = Task { [weak self] in
            async let apps = needsApps ? sources.allApps() : []
            async let shortcuts = needsShortcuts ? sources.shortcuts() : nil
            let (foundApps, foundShortcuts) = await (apps, shortcuts)
            guard !Task.isCancelled, let self else { return }
            self.loadTask = nil
            self.replaceLists {
                if needsApps { self.allApps = foundApps }
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
        await searchTask?.value
        await loadTask?.value
        await searchTask?.value
    }

    // MARK: Language

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
    static func matches(_ name: String, _ query: String) -> Bool {
        let name = fold(name)
        let query = fold(query).trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        if name.hasPrefix(query) { return true }
        let words = name.split { !$0.isLetter && !$0.isNumber }
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { token in
            words.contains { $0.hasPrefix(token) }
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// Row icons, kept while the assistant is open (a list re-renders on every keystroke and hover).
@MainActor enum AssistantIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for hit: AssistantHit) -> NSImage {
        if let icon = cache[hit.url.path] { return icon }
        let icon: NSImage = switch hit.kind {
        case .app:
            // Resolved, or a linked app (Safari in /Applications) shows an alias arrow.
            NSWorkspace.shared.icon(forFile: hit.url.resolvingSymlinksInPath().path)
        case .file:
            // The type's icon, without reading the file.
            NSWorkspace.shared.icon(for: hit.contentType.flatMap(UTType.init) ?? .data)
        }
        cache[hit.url.path] = icon
        return icon
    }

    static var shortcuts: NSImage {
        if let icon = cache[AssistantSearch.shortcutsApp] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: AssistantSearch.shortcutsApp)
        cache[AssistantSearch.shortcutsApp] = icon
        return icon
    }

    static func purge() { cache = [:] }
}

/// Hand-offs to other apps.
@MainActor enum AssistantActions {
    static func webSearchURL(for query: String) -> URL? {
        handOffURL("https://www.google.com/search", query: query)
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
