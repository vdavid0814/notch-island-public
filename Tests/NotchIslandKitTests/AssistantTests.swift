import AppKit
import CoreGraphics
import Foundation
import FoundationModels
import Testing
@testable import NotchIslandKit

@Suite struct AssistantPresentationTests {
    @Test func fieldGrowsIntoSuggestionsAndListAtThePanelWidth() {
        let layout = IslandLayout(notch: CGSize(width: 156, height: 28), scale: .standard)
        let expanded = layout.size(for: .expanded(.home))
        let field = layout.size(for: .assistant(.field))
        let suggestions = layout.size(for: .assistant(.suggestions))
        let list = layout.size(for: .assistant(.list))
        #expect(field.width == expanded.width && suggestions.width == expanded.width && list.width == expanded.width)
        // Only the field: the top inset, the 40 pt field and the bottom inset.
        #expect(field.height == CGFloat(28 + 8 + 40 + 12))
        // The four suggestions exactly: four rows and their spacing, one inset between.
        #expect(suggestions.height == field.height + 8 + 4 * 32 + 3 * 2)
        #expect(list.height == 28 + IslandLayout.assistantPageHeight)
        #expect(field.height < suggestions.height && suggestions.height < list.height)
        #expect(layout.bottomRadius(for: .assistant(.field)) == layout.bottomRadius(for: .expanded(.home)))
    }

    @Test func assistantOpensAndClosesWithThePanelSprings() {
        #expect(Motion.animation(from: .idle, to: .assistant(.field), reduceMotion: false) == Motion.open)
        #expect(Motion.animation(from: .expanded(.home), to: .assistant(.list), reduceMotion: false) == Motion.open)
        #expect(Motion.animation(from: .assistant(.suggestions), to: .idle, reduceMotion: false) == Motion.close)
        #expect(Motion.animation(from: .assistant(.field), to: .expanded(.home), reduceMotion: false) == Motion.close)
        #expect(Motion.animation(from: .expanded(.home), to: .expanded(.shelf), reduceMotion: false) == Motion.content)
    }

    @Test func roomChangesAreShortSprings() {
        let grow = Motion.animation(from: .assistant(.field), to: .assistant(.suggestions), reduceMotion: false)
        let shrink = Motion.animation(from: .assistant(.list), to: .assistant(.field), reduceMotion: false)
        #expect(grow == .lean(Motion.openSpring(duration: Motion.defaultDuration * 0.7)))
        #expect(shrink == .lean(Motion.closeSpring(duration: Motion.defaultDuration * 0.7)))
        #expect(Motion.animation(from: .assistant(.field), to: .assistant(.list), reduceMotion: true) == Motion.reduced)
    }

    @Test func everyRoomIsOneSurface() {
        for room in AssistantRoom.allCases {
            let presentation = IslandPresentation.assistant(room)
            #expect(presentation.surfaceKey == "assistant")
            #expect(presentation.isAssistant && presentation.isOpen && !presentation.isExpanded)
        }
        #expect(!IslandPresentation.expanded(.home).isAssistant)
    }
}

@Suite struct AssistantSearchTests {
    @Test func escapesTheQueryLanguage() {
        #expect(AssistantSearch.escaped("  a*b \"c\" \\d ") == #"a\*b \"c\" \\d"#)
    }

    @Test func ranksNamePrefixFirstThenRecentUse() {
        func hit(_ name: String, _ days: Double) -> AssistantHit {
            AssistantHit(kind: .file, url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, contentType: nil,
                         lastUsed: Date(timeIntervalSinceReferenceDate: days * 86_400))
        }
        let ranked = AssistantSearch.rank([hit("My Safari notes", 30), hit("safari old", 1), hit("Safari new", 10)],
                                          for: "SAFARI")
        #expect(ranked.map(\.name) == ["Safari new", "safari old", "My Safari notes"])
    }

    @Test func matchesWordPrefixesIgnoringCaseAndAccents() {
        #expect(AssistantMatch.matches("System Settings", "sett"))
        #expect(AssistantMatch.matches("System Settings", "sys set"))
        #expect(AssistantMatch.matches("Zene", "zé"))
        #expect(AssistantMatch.matches("Next Track", "next"))
        #expect(!AssistantMatch.matches("Safari", "fari"))
        #expect(!AssistantMatch.matches("WhatsApp", "what is"))
        #expect(AssistantMatch.matches("Anything", "  "))
    }
}

/// Fixed lists instead of Spotlight and `shortcuts list`.
@MainActor func stubSources(
    apps: [String] = [], files: [String] = [], recent: [String] = [], allApps: [String] = [], shortcuts: [String] = []
) -> AssistantSources {
    func hits(_ names: [String], _ kind: AssistantHit.Kind) -> [AssistantHit] {
        names.enumerated().map { index, name in
            AssistantHit(kind: kind, url: URL(fileURLWithPath: "/stub/\(kind)/\(name)"), name: name, contentType: nil,
                         lastUsed: Date(timeIntervalSinceReferenceDate: Double(1000 - index)))
        }
    }
    let appHits = hits(apps, .app), fileHits = hits(files, .file), recentHits = hits(recent, .file)
    let allAppHits = hits(allApps, .app)
    return AssistantSources(
        apps: { query, limit in Array(appHits.filter { AssistantMatch.matches($0.name, query) }.prefix(limit)) },
        files: { query, limit, _ in Array(fileHits.filter { AssistantMatch.matches($0.name, query) }.prefix(limit)) },
        recentFiles: { _ in recentHits },
        allApps: { allAppHits },
        shortcuts: { shortcuts },
        isUnsupportedLanguage: { _ in false }
    )
}

@Suite struct AssistantModelTests {
    func freshDefaults() -> UserDefaults {
        let name = "AssistantModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func model(_ sources: AssistantSources = stubSources(), defaults: UserDefaults? = nil) -> AssistantModel {
        let model = AssistantModel(defaults: defaults ?? freshDefaults(), sources: sources)
        model.begin()
        return model
    }

    @Test func bareFieldListsTheSuggestionsButNeedsNoList() {
        let model = model()
        #expect(model.rows == [.category(.applications), .category(.files), .category(.actions), .category(.clipboard)])
        #expect(!model.needsList && !model.revealsSuggestions)
        // Return on the bare field does nothing: nothing is shown to run.
        model.activateSelection()
        #expect(model.category == nil)
    }

    @Test func firstArrowRevealsTheSuggestionsThenMoves() {
        let model = model()
        model.moveSelection(by: 1)
        #expect(model.revealsSuggestions && model.selection == 0)
        model.moveSelection(by: 1)
        #expect(model.selection == 1)
        model.activateSelection()
        #expect(model.category == .files && model.needsList)
    }

    @Test func roomFollowsWhatShows() async {
        let model = model(stubSources(apps: ["Safari", "Safari Technology Preview", "Safe"]))
        #expect(model.room == .field)
        model.isPointerOver = true
        #expect(model.room == .suggestions)
        model.isPointerOver = false
        #expect(model.room == .field)
        model.moveSelection(by: 1)
        #expect(model.room == .suggestions)
        // A query is exactly as tall as its rows, up to the full list.
        model.query = "zzqx"
        await model.settle()
        #expect(model.room == .rows(model.rows.count))
        model.query = "saf"
        await model.settle()
        #expect(model.rows.count > 3 && model.room == .rows(model.rows.count))
        let layout = IslandLayout(notch: CGSize(width: 156, height: 28), scale: .standard)
        #expect(layout.size(for: .assistant(model.room)).height < layout.size(for: .assistant(.list)).height)
        #expect(layout.size(for: .assistant(.rows(40))).height == layout.size(for: .assistant(.list)).height)
        model.query = ""
        model.open(.applications)
        #expect(model.room == .gallery)
    }

    @Test func galleryIsTheLargestRoom() {
        let layout = IslandLayout(notch: CGSize(width: 156, height: 28), scale: .standard)
        let list = layout.size(for: .assistant(.list)), gallery = layout.size(for: .assistant(.gallery))
        #expect(gallery.width > list.width && gallery.height > list.height)
    }

    @Test func overTheFieldTheFirstArrowMoves() {
        let model = model()
        model.isPointerOver = true
        model.moveSelection(by: 1)
        #expect(model.selection == 1)
    }

    @Test func applicationsGalleryFiltersInMemory() async {
        let model = model(stubSources(allApps: ["Safari", "Music", "System Settings", "Mail"]))
        model.open(.applications)
        await model.settle()
        #expect(model.rows.count == 4)
        model.query = "set"
        #expect(model.rows.compactMap { if case .hit(let hit) = $0 { hit.name } else { nil } } == ["System Settings"])
    }

    @Test func actionsFollowNowPlayingAndIncludeShortcuts() async {
        let model = model(stubSources(shortcuts: ["Find Music", "Count Songs"]))
        model.open(.actions)
        await model.settle()
        var titles = model.rows.compactMap { if case .action(let action) = $0 { action.title } else { nil } }
        #expect(!titles.contains("Pause") && titles.contains("Timer") && titles.contains("Find Music"))
        model.mediaState = { .playing }
        model.query = "p"
        titles = model.rows.compactMap { if case .action(let action) = $0 { action.title } else { nil } }
        #expect(titles.contains("Pause") && titles.contains("Previous Track") && !titles.contains("Timer"))
    }

    @Test func islandActionsGoThroughTheApp() async {
        let model = model()
        var commands: [AppCommand] = []
        var closed = false
        model.onCommand = { commands.append($0) }
        model.onClose = { closed = true }
        model.open(.actions)
        model.query = "stopw"
        model.activateSelection()
        #expect(commands == [.startStopwatch])
        // The app decides how to close (the panel may take the assistant's place).
        #expect(!closed)
    }

    @Test func typingASuggestionsNameOffersItFirstAndReturnOpensIt() async {
        let model = model(stubSources(apps: ["App Store"], allApps: ["Safari", "Music"]))
        model.query = "application"
        await model.settle()
        #expect(model.rows.first == .category(.applications))
        model.activateSelection()
        await model.settle()
        // Its name is not a filter for the list it opens.
        #expect(model.category == .applications && model.query.isEmpty && model.rows.count == 2)
        model.open(nil)
        // "app" starts an app's name: the app comes first, the suggestion after it.
        model.query = "app"
        await model.settle()
        #expect(model.rows.first.map { if case .hit(let hit) = $0 { hit.name == "App Store" } else { false } } == true)
        #expect(model.rows.contains(.category(.applications)))
        // Too short to mean a suggestion.
        #expect(AssistantModel.categories(named: "ap", in: AssistantCategory.allCases).isEmpty)
        #expect(AssistantModel.categories(named: "shortcuts", in: AssistantCategory.allCases) == [.actions])
    }

    @Test func rootQueryListsHitsActionsThenHandOffs() async {
        let model = model(stubSources(apps: ["Timer Pro"]))
        model.query = "timer"
        await model.settle()
        let rows = model.rows
        guard case .hit(let hit) = rows.first else {
            Issue.record("no hit first: \(rows)")
            return
        }
        #expect(hit.name == "Timer Pro")
        #expect(rows.contains(.action(.island(.timer))))
        #expect(rows.suffix(2) == [.searchWeb, .askChatGPT])
        // Files are read only once the user has asked for them (the folders are protected).
        #expect(!rows.contains { if case .hit(let hit) = $0 { hit.kind == .file } else { false } })
    }

    @Test func aLongerQueryDropsHitsThatNoLongerMatchAtOnce() async {
        let model = model(stubSources(apps: ["WhatsApp"]))
        model.query = "what"
        await model.settle()
        #expect(model.rows.first == model.apps.first.map(AssistantRow.hit))
        model.query = "what is 2+2"
        // Before the new search lands, Return must not open WhatsApp.
        #expect(model.apps.isEmpty)
        #expect(model.rows.first == .askChatGPT || model.rows.first == .askIntelligence)
    }

    @Test func aPickedRowStaysPickedWhenResultsLand() async {
        let model = model(stubSources(apps: ["Mail"]))
        model.query = "ma"
        await model.settle()
        let web = model.rows.firstIndex(of: .searchWeb)!
        model.select(.searchWeb)
        #expect(model.selection == web)
        model.query = "mai"
        model.select(.searchWeb)
        await model.settle()
        #expect(model.rows[model.selection] == .searchWeb)
    }

    @Test func filesAreRememberedOnceTheyWereReadable() async {
        let defaults = freshDefaults()
        let sources = stubSources(files: ["Report.pdf"], recent: ["Report.pdf"])
        let first = model(sources, defaults: defaults)
        var settled = 0
        first.onFileAccessSettled = { settled += 1 }
        first.open(.files)
        await first.settle()
        #expect(settled == 1 && !first.isAwaitingFileAccess)
        #expect(defaults.bool(forKey: AssistantModel.filesKey))
        #expect(first.rows.count == 1)
        let later = model(sources, defaults: defaults)
        later.query = "rep"
        await later.settle()
        #expect(later.rows.contains { if case .hit(let hit) = $0 { hit.name == "Report.pdf" } else { false } })
    }

    @Test func escapeStepsBackThenCloses() async {
        let model = model()
        var closed = false
        model.onClose = { closed = true }
        model.moveSelection(by: 1)
        model.open(.files)
        model.query = "hello"
        model.escape()
        #expect(model.query.isEmpty && model.category == .files && !closed)
        model.escape()
        #expect(model.category == nil && model.revealsSuggestions && !closed)
        model.escape()
        #expect(!model.revealsSuggestions && !closed)
        model.escape()
        #expect(closed)
    }

    @Test func deleteInAnEmptyFieldLeavesTheSuggestion() {
        let model = model()
        #expect(!model.deleteBackwardInEmptyField())
        model.open(.actions)
        model.query = "x"
        #expect(!model.deleteBackwardInEmptyField())
        model.query = ""
        #expect(model.deleteBackwardInEmptyField() && model.category == nil)
    }

    @Test func endForgetsEverything() async {
        let model = model(stubSources(allApps: ["Safari"]))
        model.open(.applications)
        await model.settle()
        model.query = "s"
        model.end()
        #expect(model.query.isEmpty && model.category == nil && model.allApps.isEmpty && model.answer == nil)
        #expect(!model.needsList && !model.revealsSuggestions)
    }

    @Test func questionsAreAnsweredOnReturn() async {
        #expect(AssistantModel.looksLikeQuestion("what is 2+2"))
        #expect(AssistantModel.looksLikeQuestion("mennyi az idő"))
        #expect(AssistantModel.looksLikeQuestion("weather?"))
        #expect(AssistantModel.looksLikeQuestion("mi van"))
        #expect(!AssistantModel.looksLikeQuestion("safari"))
        #expect(!AssistantModel.looksLikeQuestion("system settings"))
        let model = model(stubSources(apps: ["Whatever"]))
        model.query = "what is the weather"
        await model.settle()
        let first = model.rows.first
        #expect(first == .askIntelligence || first == .askChatGPT)
        // Each hand-off once.
        #expect(model.rows.filter { $0 == .askChatGPT }.count == 1)
    }

    @Test func languageGateIsConservative() {
        // Single words are unreliable, so they never demote the Ask row.
        #expect(!AssistantModel.isUnsupportedLanguage("safari"))
        #expect(!AssistantModel.isUnsupportedLanguage("What is the capital of France?"))
        #expect(AssistantModel.isUnsupportedLanguage("Mi Magyarország fővárosa és hány lakosa van?"))
    }

    @Test func languageGateComparesBaseLanguages() {
        // The recogniser says zh-Hans, the model lists zh.
        let supported = SystemLanguageModel.default.supportedLanguages.compactMap { $0.languageCode?.identifier }
        guard supported.contains("zh") else { return }
        #expect(!AssistantModel.isUnsupportedLanguage("北京 是 中国 的 首都 吗 今天 天气 怎么样"))
    }

    @Test func handOffURLs() {
        #expect(AssistantActions.webSearchURL(for: "a b&c")?.absoluteString == "https://www.google.com/search?q=a%20b%26c")
        #expect(AssistantActions.chatGPTURL(for: "hi")?.absoluteString == "https://chatgpt.com/?q=hi")
        // '+' would reach the search box as a space.
        #expect(AssistantActions.webSearchURL(for: "c++ 2+2")?.absoluteString == "https://www.google.com/search?q=c%2B%2B%202%2B2")
        #expect(AssistantActions.chatGPTURL(for: "1+1")?.absoluteString == "https://chatgpt.com/?q=1%2B1")
    }
}

@Suite struct CommandSpaceTapTests {
    @Test func swallowsCommandSpaceAndItsKeyUpOnly() {
        var pressed = false
        // ⌘Space down, a repeat, then the key-up: all ours.
        #expect(CommandSpaceTap.swallows(keyCode: 49, isDown: true, flags: .maskCommand, pressed: &pressed))
        #expect(CommandSpaceTap.swallows(keyCode: 49, isDown: true, flags: .maskCommand, pressed: &pressed))
        #expect(CommandSpaceTap.swallows(keyCode: 49, isDown: false, flags: [], pressed: &pressed))
        #expect(!pressed)
        // Other shortcuts on Space are left alone.
        #expect(!CommandSpaceTap.swallows(keyCode: 49, isDown: true, flags: [.maskCommand, .maskAlternate], pressed: &pressed))
        #expect(!CommandSpaceTap.swallows(keyCode: 49, isDown: true, flags: [.maskCommand, .maskShift], pressed: &pressed))
        #expect(!CommandSpaceTap.swallows(keyCode: 49, isDown: true, flags: .maskControl, pressed: &pressed))
        #expect(!CommandSpaceTap.swallows(keyCode: 49, isDown: true, flags: [], pressed: &pressed))
        // A key-up whose down we never saw (the tap armed mid-press) goes through.
        #expect(!CommandSpaceTap.swallows(keyCode: 49, isDown: false, flags: [], pressed: &pressed))
        // Other keys with ⌘ are never touched.
        #expect(!CommandSpaceTap.swallows(keyCode: 12, isDown: true, flags: .maskCommand, pressed: &pressed))
    }
}

@Suite struct IslandPanelKeyboardTests {
    func key(_ characters: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: 0)!
    }

    @Test func appShortcutsAreSwallowedEditingOnesAreNot() {
        #expect(IslandPanel.isSwallowedShortcut(key("q", .command)))
        #expect(IslandPanel.isSwallowedShortcut(key("h", [.command, .option])))
        #expect(IslandPanel.isSwallowedShortcut(key("w", .command)))
        #expect(!IslandPanel.isSwallowedShortcut(key("v", .command)))
        #expect(!IslandPanel.isSwallowedShortcut(key("c", .command)))
        #expect(!IslandPanel.isSwallowedShortcut(key("q", [])))
    }
}

@Suite struct IslandSettingsTests {
    @Test func settingsIsALargeOpenSurface() {
        let layout = IslandLayout(notch: CGSize(width: 156, height: 28), scale: .standard)
        let settings = layout.size(for: .settings)
        #expect(settings.width > layout.size(for: .expanded(.home)).width)
        #expect(IslandPresentation.settings.isOpen && IslandPresentation.settings.takesKeyboard)
        #expect(!IslandPresentation.expanded(.home).takesKeyboard)
        #expect(Motion.animation(from: .expanded(.home), to: .settings, reduceMotion: false) == Motion.open)
        #expect(Motion.animation(from: .settings, to: .idle, reduceMotion: false) == Motion.close)
    }

    @Test func settingsOutranksThePanelButNotSiri() {
        var inputs = IslandInputs()
        inputs.wantsExpanded = true
        inputs.wantsSettings = true
        #expect(IslandResolver.resolve(inputs) == .settings)
        inputs.wantsAssistant = true
        #expect(IslandResolver.resolve(inputs).isAssistant)
    }

    @Test func settingsRoutes() {
        #expect(AppCommand.parse(URL(string: "notchisland://settings")!) == .showSettings)
        #expect(AppCommand.parse(URL(string: "notchisland://settings/widgets")!) == .showSettingsPane(.widgets))
        #expect(AppCommand.parse(URL(string: "notchisland://settings/nope")!) == nil)
    }
}

@Suite struct WidgetStyleTests {
    @Test func oldBoardsDecodeWithDefaults() throws {
        let json = #"{"widgets":[{"kind":"timer","frame":{"column":7,"row":0,"width":5,"height":2},"options":["ruler","readout","bogus"]}]}"#
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        let timer = try #require(board.widget(.timer))
        #expect(timer.options == [.ruler, .readout])
        #expect(timer.tint == .automatic && timer.showsPlate && !timer.mirrored)
    }

    @Test func styleRoundTripsAndKeepsTheFrame() throws {
        var board = WidgetBoard.standard
        board.update(.timer) { widget in
            widget.tint = .teal
            widget.mirrored = true
            widget.frame = GridRect(column: 0, row: 0, width: 1, height: 1)   // ignored
        }
        let data = try JSONEncoder().encode(board)
        let decoded = try JSONDecoder().decode(WidgetBoard.self, from: data)
        let timer = try #require(decoded.widget(.timer))
        #expect(timer.tint == .teal && timer.mirrored)
        #expect(timer.frame == WidgetBoard.standard.widget(.timer)?.frame)
    }

    @Test func everyControlIsItsOwnWidget() {
        let controls = WidgetCategory.controls.kinds
        #expect(controls.count == SystemControl.allCases.count)
        #expect(Set(controls.compactMap(\.systemControl)) == Set(SystemControl.allCases))
        for kind in controls {
            #expect(kind.minimumSize == GridSize(width: 1, height: 1))
            #expect(kind.options == [.controlName, .controlStatus])
        }
        var board = WidgetBoard(widgets: [])
        let wifi = board.add(.wifi), bluetooth = board.add(.bluetooth)
        #expect(wifi && bluetooth && board.widget(.wifi)?.frame.size == GridSize(width: 2, height: 1))
    }

    @Test func anUnknownWidgetDoesNotLoseTheBoard() throws {
        // A board saved by the version with one combined Controls widget.
        let json = #"{"widgets":[{"kind":"controls","frame":{"column":0,"row":0,"width":5,"height":1},"options":[]},{"kind":"timer","frame":{"column":7,"row":0,"width":5,"height":2},"options":["ruler"]}]}"#
        let board = try JSONDecoder().decode(WidgetBoard.self, from: Data(json.utf8))
        #expect(board.widgets.map(\.kind) == [.timer])
    }

    @Test func settingsFitsTheScreen() {
        let screen = CGSize(width: 1280, height: 832)
        let layout = IslandLayout(notch: CGSize(width: 156, height: 32), scale: .standard, screen: screen)
        let size = layout.size(for: .settings)
        #expect(size.width <= screen.width - 2 * IslandLayout.settingsSideMargin)
        #expect(size.height <= screen.height - IslandLayout.settingsBottomMargin)
        #expect(size.width >= 1000 && size.height >= 600)
        let huge = IslandLayout(notch: CGSize(width: 180, height: 38), scale: .standard, screen: CGSize(width: 3000, height: 2000))
        #expect(huge.size(for: .settings).width == IslandLayout.settingsMaximum.width)
    }
}


@Suite struct SiriSettingsTests {
    @Test func matchingModes() {
        #expect(AssistantMatch.matches("Safari", "saf"))
        #expect(!AssistantMatch.matches("Safari", "far"))
        #expect(AssistantMatch.matches("Safari", "far", .anywhere))
        #expect(!AssistantMatch.matches("Safari", "sfr", .anywhere))
        #expect(AssistantMatch.matches("Safari", "sfr", .fuzzy))
        #expect(!AssistantMatch.matches("Safari", "zzz", .fuzzy))
        #expect(AssistantMatch.isSubsequence("vsc", of: "visual studio code"))
    }

    @Test func oldOrPartialValuesKeepDefaults() throws {
        let decoded = try JSONDecoder().decode(SiriSettings.self, from: Data(#"{"galleryColumns": 40, "matching": "fuzzy"}"#.utf8))
        #expect(decoded.galleryColumns == SiriSettings.galleryColumnsRange.upperBound)
        #expect(decoded.matching == .fuzzy)
        #expect(decoded.resultsPerKind == 3 && decoded.shortcut == .commandSpace && decoded.folders.count == 4)
        let roundTrip = try JSONDecoder().decode(SiriSettings.self, from: JSONEncoder().encode(decoded))
        #expect(roundTrip == decoded)
    }

    @Test func windowSizesFollowTheSettings() {
        let notch = CGSize(width: 180, height: 32)
        let standard = IslandLayout(notch: notch, scale: .standard)
        var settings = SiriSettings()
        #expect(IslandLayout(notch: notch, scale: .standard, siri: settings.layout).size(for: .assistant(.list))
                == standard.size(for: .assistant(.list)))
        settings.galleryColumns = 12
        settings.galleryRows = 6
        settings.panelSize = .large
        let custom = IslandLayout(notch: notch, scale: .standard, siri: settings.layout)
        #expect(custom.size(for: .assistant(.gallery)).width > standard.size(for: .assistant(.gallery)).width)
        #expect(custom.size(for: .assistant(.gallery)).height > standard.size(for: .assistant(.gallery)).height)
        #expect(custom.size(for: .assistant(.field)).width > standard.size(for: .assistant(.field)).width)
    }

    @Test func otherShortcutModifiers() {
        var pressed = false
        #expect(CommandSpaceTap.swallows(keyCode: 49, isDown: true, flags: .maskAlternate, modifiers: .maskAlternate, pressed: &pressed))
        pressed = false
        #expect(!CommandSpaceTap.swallows(keyCode: 49, isDown: true, flags: .maskCommand, modifiers: .maskAlternate, pressed: &pressed))
    }

    @Test func webSearchEngines() {
        #expect(AssistantActions.webSearchURL(for: "a b", engine: .duckDuckGo)?.absoluteString == "https://duckduckgo.com/?q=a%20b")
    }
}

@MainActor @Suite struct ClipboardTests {
    func history() -> (ClipboardHistory, NSPasteboard) {
        let board = NSPasteboard(name: NSPasteboard.Name("ClipboardTests.\(UUID().uuidString)"))
        return (ClipboardHistory(pasteboard: board, storeURL: nil), board)
    }

    @Test func keepsCopiesNewestFirstWithoutDuplicatesUpToTheLimit() {
        let (history, _) = history()
        history.add("one")
        history.add("two")
        history.add("one")
        #expect(history.items.map(\.text) == ["one", "two"])
        for i in 0..<(ClipboardHistory.limit + 5) { history.add("item \(i)") }
        #expect(history.items.count == ClipboardHistory.limit)
        #expect(history.items.first?.text == "item \(ClipboardHistory.limit + 4)")
        history.add("   \n")
        #expect(history.items.first?.text == "item \(ClipboardHistory.limit + 4)")
    }

    @Test func readsNewCopiesButNeverConcealedOnes() {
        let (history, board) = history()
        board.clearContents()
        board.setString("hello", forType: .string)
        history.check()
        #expect(history.items.map(\.text) == ["hello"])
        board.clearContents()
        board.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        board.setString("secret", forType: .string)
        history.check()
        #expect(history.items.map(\.text) == ["hello"])
        // Placing an item puts it on top without it counting as a new copy.
        history.add("other")
        history.place(history.items[1])
        history.check()
        #expect(history.items.map(\.text) == ["hello", "other"])
        #expect(board.string(forType: .string) == "hello")
    }

    @Test func clipboardSuggestionListsAndFiltersCopiesAndPastesTheSelection() {
        let defaults = UserDefaults(suiteName: "ClipboardTests.\(UUID().uuidString)")!
        let model = AssistantModel(defaults: defaults, sources: stubSources())
        model.begin()
        let items = [ClipboardItem(text: "DELIVERY/screenshots/P3-fitness/", copied: .now),
                     ClipboardItem(text: "fitness,apple,watch\nrun", copied: .now)]
        model.clipboard = { items }
        var pasted: ClipboardItem?
        model.onPaste = { pasted = $0 }
        #expect(model.rows.contains(.category(.clipboard)))
        model.open(.clipboard)
        #expect(model.rows == items.map(AssistantRow.clip))
        #expect(model.room == .rows(2))
        #expect(model.selectedClip == items[0])
        model.moveSelection(by: 1)
        #expect(model.selectedClip?.preview == "fitness,apple,watch")
        model.activateSelection()
        #expect(pasted == items[1])
        model.query = "screens"
        #expect(model.rows == [.clip(items[0])])
    }
}
