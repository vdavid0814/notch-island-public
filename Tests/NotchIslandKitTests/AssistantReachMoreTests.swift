import AppKit
import Foundation
import Synchronization
import Testing
@testable import NotchIslandKit

/// A value a stubbed source and its test share.
nonisolated final class Shared<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func update(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}

/// Spotlight's reach added in 0.6.1: the dictionary, People & Calendar (⌘8), bookmarks, Quick Look
/// and Reveal — with stubbed sources, so no test reads a contact, an event or a browser's file.
@MainActor @Suite struct AssistantPeopleTests {
    static let anna = AssistantContact(id: "A1", name: "Anna Kovács", organization: "Studio", phones: ["+36 30 123 4567"], emails: ["anna@example.com"])
    static let adam = AssistantContact(id: "A2", name: "Ádám Nagy", organization: nil, phones: [], emails: ["adam@example.com"])

    static func event(_ title: String, in hours: Double = 2) -> CalendarEvent {
        CalendarEvent(id: title, title: title, start: Date().addingTimeInterval(hours * 3600), end: Date().addingTimeInterval(hours * 3600 + 3600),
                      isAllDay: false, calendarID: "c", red: 0.2, green: 0.5, blue: 1, location: nil)
    }

    /// Sources with people, a dictionary and bookmarks; `contactsAccess` as a test sets it.
    func sources(access: Shared<AccessState> = Shared(.granted), apps: [String] = []) -> AssistantSources {
        var sources = stubSources(apps: apps)
        let people = [Self.anna, Self.adam]
        sources.contacts = { query, limit in Array(people.filter { AssistantMatch.matches($0.name, query) }.prefix(limit)) }
        sources.contactsAccess = { access.value }
        sources.requestContacts = {
            access.value = .granted
            return .granted
        }
        sources.define = { word in word.lowercased() == "island" ? AssistantDefinition(word: word, text: "island | noun\nA piece of land surrounded by water.") : nil }
        sources.bookmarks = {
            [AssistantBookmark(title: "Apple Developer", url: URL(string: "https://developer.apple.com")!, browser: "Safari"),
             AssistantBookmark(title: "Island Docs", url: URL(string: "https://example.com/island")!, browser: "Chrome")]
        }
        return sources
    }

    func model(_ sources: AssistantSources, recorder: SystemRecorder? = nil, settings: SiriSettings = SiriSettings()) -> AssistantModel {
        let model = AssistantModel(defaults: UserDefaults(suiteName: "AssistantPeopleTests.\(UUID().uuidString)")!, sources: sources)
        if let recorder { model.system = recorder.system }
        model.settings = { settings }
        model.begin()
        return model
    }

    @Test func peopleIsTheEighthSuggestionWithItsKeyAndToggle() throws {
        #expect(AssistantCategory.people.rawValue == 8)
        #expect(AssistantCategory.allCases.map(\.rawValue) == Array(1...8))
        // Settings saved before it existed turn it on; the opt-ins stay off.
        let old = try JSONDecoder().decode(SiriSettings.self, from: Data(#"{"showsEmoji": false}"#.utf8))
        #expect(old.showsPeople && old.showsDefinitions && !old.showsBookmarks && !old.convertsCurrency && !old.searchesFileContents)
        #expect(old.categories.last == .people)
        // The home folder is a new scope: folders chosen before it stay as they were.
        #expect(!old.folders.contains(.home))
        var settings = SiriSettings()
        settings.showsPeople = false
        let model = model(sources(), settings: settings)
        model.open(.people)
        #expect(model.category == nil)
        #expect(AssistantModel.categories(named: "contacts", in: AssistantCategory.allCases) == [.people])
        #expect(AssistantModel.categories(named: "calendar", in: AssistantCategory.allCases) == [.people])
    }

    /// Nothing is read before it is allowed: ⌘8 then shows only the rows that ask.
    @Test func peopleAreReadOnlyOnceAllowedFromTheirOwnRow() async {
        let access = Shared(AccessState.notDetermined)
        let model = model(sources(access: access))
        var calendar = AccessState.notDetermined
        var asked = 0
        model.calendarAccess = { calendar }
        model.requestCalendar = { asked += 1; calendar = .granted }
        model.calendarEvents = { _ in [Self.event("Design Review")] }
        model.open(.people)
        #expect(model.rows == [.permission(.contacts), .permission(.calendar)])
        model.query = "anna"
        await model.settle()
        #expect(model.rows == [.permission(.contacts), .permission(.calendar)])
        // The root lists no contact either.
        model.open(nil)
        await model.settle()
        #expect(!model.rows.contains { if case .contact = $0 { true } else { false } })

        model.open(.people)
        model.perform(.permission(.contacts))
        #expect(model.isAwaitingFileAccess)
        try? await Task.sleep(for: .milliseconds(50))
        await model.settle()
        #expect(!model.isAwaitingFileAccess)
        #expect(model.rows.first == .permission(.calendar))
        #expect(model.rows.contains(.contact(Self.anna)))
        model.perform(.permission(.calendar))
        #expect(asked == 1)
        #expect(!model.rows.contains(.permission(.calendar)))
        // The query filters the events too.
        #expect(!model.rows.contains { if case .event = $0 { true } else { false } } || model.calendarEvents("anna").isEmpty == false)
    }

    @Test func aContactOpensItsWaysAndEachDoesItsThing() async {
        let recorder = SystemRecorder()
        let model = model(sources(), recorder: recorder)
        var closed = 0
        model.onClose = { closed += 1 }
        model.open(.people)
        model.query = "ann"
        await model.settle()
        #expect(model.rows.contains(.contact(Self.anna)) && !model.rows.contains(.contact(Self.adam)))
        model.perform(.contact(Self.anna))
        #expect(model.openedContact == Self.anna)
        let kinds = model.rows.compactMap { row -> ContactAction.Kind? in if case .contactAction(let action) = row { action.kind } else { nil } }
        #expect(kinds == [.call, .message, .email, .copy, .copy, .openCard])

        model.perform(.contactAction(Self.anna.actions[0]))
        #expect(recorder.calls.last == "open tel:+36301234567" && closed == 1)
        model.perform(.contactAction(Self.anna.actions[1]))
        #expect(recorder.calls.last == "open sms:+36301234567")
        model.perform(.contactAction(Self.anna.actions[2]))
        #expect(recorder.calls.last == "open mailto:anna@example.com")
        let calls = recorder.calls.count
        model.perform(.contactAction(Self.anna.actions[3]))
        #expect(NSPasteboard.general.string(forType: .string) == "+36 30 123 4567" && recorder.calls.count == calls)
        model.perform(.contactAction(Self.anna.actions[5]))
        #expect(recorder.calls.last == "open addressbook://A1")

        // Esc goes back to the people, then on as it always did.
        model.escape()
        #expect(model.openedContact == nil && model.category == .people)
    }

    @Test func aContactFromTheRootOpensInPeople() async {
        let model = model(sources(apps: ["Anki"]))
        model.query = "an"
        await model.settle()
        let rows = model.rows
        let app = rows.firstIndex { if case .hit = $0 { true } else { false } }
        let contact = rows.firstIndex(of: .contact(Self.anna))
        // After the apps, before the web.
        #expect(app != nil && contact != nil && app! < contact! && contact! < rows.firstIndex(of: .searchWeb)!)
        model.perform(.contact(Self.anna))
        #expect(model.category == .people && model.openedContact == Self.anna && model.query.isEmpty)
    }

    @Test func eventsAreListedAndOpenCalendarOnTheirDay() async {
        let recorder = SystemRecorder()
        let model = model(sources(), recorder: recorder)
        var leases: [Bool] = []
        model.onCalendarLease = { leases.append($0) }
        model.calendarAccess = { .granted }
        let events = [Self.event("Design Review"), Self.event("Lunch", in: 5)]
        model.calendarEvents = { query in query.isEmpty ? events : events.filter { $0.title.localizedCaseInsensitiveContains(query) } }
        model.open(.people)
        #expect(leases == [true])
        #expect(model.rows == events.map(AssistantRow.event))
        model.query = "lun"
        await model.settle()
        #expect(model.rows == [.event(events[1])])
        model.perform(.event(events[1]))
        #expect(recorder.calls.last == "open calshow:\(Int(events[1].start.timeIntervalSinceReferenceDate))")
        // Leaving ⌘8, and closing Spotlight, stop reading the calendar.
        model.open(nil)
        #expect(leases == [true, false])
        model.open(.people)
        model.end()
        #expect(leases == [true, false, true, false])
        // From the root, by name, from three letters on.
        model.begin()
        model.query = "des"
        await model.settle()
        #expect(model.rows.contains(.event(events[0])))
    }

    @Test func aWordAloneIsDefinedAndReturnShowsTheEntry() async {
        let recorder = SystemRecorder()
        let model = model(sources(), recorder: recorder)
        model.query = "island"
        await model.settle()
        guard case .definition(let definition)? = model.rows.first else {
            Issue.record("no definition first: \(model.rows.map(\.id))")
            return
        }
        #expect(definition.summary == "noun")
        #expect(AssistantDefinition(word: "Island", text: "island | ˈʌɪlənd | noun 1 a piece of land").summary == "noun 1 a piece of land")
        #expect(AssistantDefinition(word: "go", text: "go").summary == "go")
        model.perform(.definition(definition))
        #expect(model.answer?.definedWord == "island" && model.answer?.isResponding == false)
        #expect(model.answer?.text.contains("surrounded by water") == true)
        model.openInDictionary("island")
        #expect(recorder.calls.last == "open dict://island")

        // Two words, a number or a word the dictionary lacks are not defined.
        for query in ["island docs", "12", "qwzx"] {
            model.query = query
            await model.settle()
            #expect(!model.rows.contains { if case .definition = $0 { true } else { false } }, "\(query)")
        }
        #expect(DictionaryLookup.isWord("don't") && DictionaryLookup.isWord("well-known") && !DictionaryLookup.isWord("a") && !DictionaryLookup.isWord("new york")
                && !DictionaryLookup.isWord("km2"))
    }

    @Test func definitionsCanBeSwitchedOff() async {
        var settings = SiriSettings()
        settings.showsDefinitions = false
        let model = model(sources(), settings: settings)
        model.query = "island"
        await model.settle()
        #expect(!model.rows.contains { if case .definition = $0 { true } else { false } })
    }

    @Test func bookmarksAreReadOnlyWhenSwitchedOn() async {
        let reads = Shared(0)
        var sources = sources()
        let bookmarks = sources.bookmarks
        sources.bookmarks = {
            reads.update { $0 += 1 }
            return await bookmarks()
        }
        let off = model(sources)
        off.query = "island"
        await off.settle()
        #expect(reads.value == 0 && !off.rows.contains { if case .bookmark = $0 { true } else { false } })

        var settings = SiriSettings()
        settings.showsBookmarks = true
        let recorder = SystemRecorder()
        let on = model(sources, recorder: recorder, settings: settings)
        on.query = "island"
        await on.settle()
        let found = on.rows.compactMap { row -> AssistantBookmark? in if case .bookmark(let bookmark) = row { bookmark } else { nil } }
        #expect(found.map(\.title) == ["Island Docs"])
        // Once per opening, whatever is typed.
        on.query = "apple"
        await on.settle()
        #expect(reads.value == 1)
        #expect(on.rows.contains { if case .bookmark(let bookmark) = $0 { bookmark.title == "Apple Developer" } else { false } })
        on.perform(.bookmark(found[0]))
        #expect(recorder.calls.last == "open https://example.com/island")
    }

    @Test func aFileIsPreviewedAndRevealed() async {
        let recorder = SystemRecorder()
        let defaults = UserDefaults(suiteName: "AssistantPeopleTests.\(UUID().uuidString)")!
        defaults.set(true, forKey: AssistantModel.filesKey)
        let model = AssistantModel(defaults: defaults, sources: stubSources(apps: ["Notes"], files: ["Notes.txt"]))
        model.system = recorder.system
        model.begin()
        var closed = 0
        model.onClose = { closed += 1 }
        model.query = "notes"
        await model.settle()
        // A row the list merely starts at is not previewed (Space types a space).
        #expect(!model.quickLookSelection())
        let file = model.rows.firstIndex { if case .hit(let hit) = $0 { hit.kind == .file } else { false } }!
        model.moveSelection(by: file)
        #expect(model.quickLookSelection())
        #expect(recorder.calls.last == "quicklook /stub/file/Notes.txt")
        // Spotlight stays under the preview, and takes the keyboard back when it closes.
        #expect(model.isAwaitingFileAccess && closed == 0)
        recorder.closePreview?()
        #expect(!model.isAwaitingFileAccess)
        #expect(model.revealSelection())
        #expect(recorder.calls.last == "reveal /stub/file/Notes.txt" && closed == 1)
        // An app is revealed too, but not previewed.
        model.moveSelection(by: -file)
        #expect(!model.quickLookSelection())
    }

    @Test func currenciesNeedTheirSwitchAndAreFetchedOnlyForACurrency() async {
        let fetches = Shared(0)
        var sources = sources()
        sources.rates = {
            fetches.update { $0 += 1 }
            return ["USD": 1.1, "HUF": 400]
        }
        let off = model(sources)
        off.query = "100 usd in huf"
        await off.settle()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(fetches.value == 0 && !off.rows.contains { if case .calculation = $0 { true } else { false } })

        var settings = SiriSettings()
        settings.convertsCurrency = true
        let on = model(sources, settings: settings)
        on.query = "12 km in mi"
        await on.settle()
        #expect(fetches.value == 0)
        on.query = "110 usd in huf"
        await on.settle()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fetches.value == 1)
        guard case .calculation(let result)? = on.rows.first else {
            Issue.record("no conversion: \(on.rows.map(\.id))")
            return
        }
        #expect(result.result.hasSuffix("HUF") && result.result.filter(\.isNumber) == "40000")
    }
}

@Suite struct AssistantReachSourcesTests {
    @Test func chromiumBookmarksAreWalkedAndOnlyWebLinksKept() {
        let json = #"""
        {"roots": {"bookmark_bar": {"type": "folder", "name": "Bar", "children": [
            {"type": "url", "name": "Apple", "url": "https://www.apple.com/"},
            {"type": "folder", "name": "Work", "children": [
                {"type": "url", "name": "", "url": "http://intranet.example/"},
                {"type": "url", "name": "Run", "url": "javascript:alert(1)"}]}]},
          "other": {"type": "folder", "children": [{"type": "url", "name": "Swift", "url": "https://swift.org"}]},
          "synced": 3}}
        """#
        let found = BrowserBookmarks.chromium(Data(json.utf8), browser: "Chrome")
        #expect(Set(found.map(\.title)) == ["Apple", "http://intranet.example/", "Swift"])
        #expect(found.allSatisfy { $0.browser == "Chrome" })
        #expect(BrowserBookmarks.chromium(Data("not json".utf8), browser: "Chrome").isEmpty)
    }

    @Test func safariBookmarksLeaveTheReadingListOut() throws {
        let plist: [String: Any] = ["Children": [
            ["WebBookmarkType": "WebBookmarkTypeList", "Title": "BookmarksBar", "Children": [
                ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://developer.apple.com", "URIDictionary": ["title": "Developer"]],
                ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://example.com", "URIDictionary": ["title": ""]]]],
            ["WebBookmarkType": "WebBookmarkTypeList", "Title": "com.apple.ReadingList", "Children": [
                ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "https://later.example", "URIDictionary": ["title": "Later"]]]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let found = BrowserBookmarks.safari(data)
        #expect(found.map(\.title) == ["Developer", "https://example.com"])
        #expect(found.allSatisfy { $0.browser == "Safari" })
    }

    @Test func aContactsWaysFollowWhatItHas() {
        let full = AssistantContact(id: "1", name: "N", organization: nil, phones: ["+1 (555) 010-0199"], emails: ["n@example.com"])
        #expect(full.actions.map(\.kind) == [.call, .message, .email, .copy, .copy, .openCard])
        #expect(full.actions[0].url?.absoluteString == "tel:+15550100199")
        #expect(full.detail == "+1 (555) 010-0199")
        let bare = AssistantContact(id: "2", name: "N", organization: "Org", phones: [], emails: [])
        #expect(bare.actions.map(\.kind) == [.openCard] && bare.detail == "Org")
        #expect(Set(full.actions.map(\.id)).count == full.actions.count)
    }

    @Test func theDictionaryOpensByWord() {
        #expect(DictionaryLookup.url(for: "island")?.absoluteString == "dict://island")
        #expect(DictionaryLookup.url(for: "naïve")?.absoluteString == "dict://na%C3%AFve")
    }

    @Test func theEcbsFileIsParsedAndKeptForADay() async throws {
        let xml = #"""
        <Cube><Cube time='2026-09-29'><Cube currency='USD' rate='1.0742'/><Cube currency="HUF" rate="398.15"/><Cube currency='XXX' rate='0'/></Cube></Cube>
        """#
        #expect(CurrencyRates.parse(Data(xml.utf8)) == ["USD": 1.0742, "HUF": 398.15])
        #expect(CurrencyRates.parse(Data("<html>".utf8)) == nil)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("rates-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let fetches = Shared(0)
        let rates = CurrencyRates(fileURL: file) {
            fetches.update { $0 += 1 }
            return Data(xml.utf8)
        }
        let now = Date()
        #expect(await rates.rates(now: now)?["USD"] == 1.0742)
        #expect(await rates.rates(now: now.addingTimeInterval(3600))?["HUF"] == 398.15)
        #expect(fetches.value == 1)
        // A new launch within the day reads the file, not the network.
        let again = CurrencyRates(fileURL: file) {
            fetches.update { $0 += 1 }
            return nil
        }
        #expect(await again.rates(now: now.addingTimeInterval(7200))?["USD"] == 1.0742)
        #expect(fetches.value == 1)
        // A day later it is fetched again; a failed fetch keeps the old rates, and is not retried at once.
        #expect(await again.rates(now: now.addingTimeInterval(25 * 3600))?["USD"] == 1.0742)
        #expect(await again.rates(now: now.addingTimeInterval(25 * 3600 + 5))?["USD"] == 1.0742)
        #expect(fetches.value == 2)
    }

    @Test func fileScopesCarryTheContentsSwitchAndTheHomeFolder() {
        var settings = SiriSettings()
        #expect(!FileScope(settings).contents)
        settings.searchesFileContents = true
        settings.folders = [.home]
        let scope = FileScope(settings)
        #expect(scope.contents && scope.paths == [NSHomeDirectory()])
        // The default scope (no settings) is the four folders it always was.
        #expect(!FileScope().paths.contains(NSHomeDirectory()) && FileScope().paths.count == 4)
    }
}

@Suite struct AssistantCalculatorReachTests {
    /// Thursday 24 September 2026, 9:41 in Budapest.
    private let context = AssistantCalculator.Context(now: Date(timeIntervalSince1970: 1_790_235_660), timeZone: TimeZone(identifier: "Europe/Budapest")!,
                                                      locale: Locale(identifier: "en_GB"))

    private func result(_ text: String, rates: [String: Double]? = nil) -> String? {
        var context = context
        context.rates = rates
        return AssistantCalculator.calculate(text, context: context)?.result
    }

    @Test func theTimeSomewhereElse() {
        #expect(result("time in tokyo") == "16:41 Tokyo")
        #expect(result("Tokyo time") == "16:41 Tokyo")
        #expect(result("what is the time in new york?") == "03:41 New York")
        #expect(result("time in nyc") == "03:41 New York")
        #expect(result("time in utc") == "07:41 UTC")
        // A day ahead or behind says so.
        #expect(result("time in honolulu") == "21:41 Honolulu, the day before")
        #expect(result("time in nowhere") == nil)
    }

    @Test func aTimeMovedBetweenCities() {
        #expect(result("15:00 london in budapest") == "16:00 Budapest")
        #expect(result("15:00 in tokyo") == "22:00 Tokyo")
        #expect(result("3pm tokyo in new york") == "02:00 New York")
        #expect(result("9 am london to tokyo") == "17:00 Tokyo")
        // New Zealand is still on standard time on 24 September (UTC+12).
        #expect(result("23:30 budapest in auckland") == "09:30 Auckland, the next day")
        // Not a time: a bare number, an impossible hour, the same place.
        #expect(result("5 in tokyo") == nil)
        #expect(result("25:00 in tokyo") == nil)
        #expect(result("13pm in tokyo") == nil)
        #expect(result("15:00 budapest in budapest") == nil)
    }

    @Test func daysFromNowAndUntilADate() {
        #expect(result("30 days from now") == "Saturday 24 October 2026" || result("30 days from now") == "Saturday, 24 October 2026")
        #expect(result("2 weeks ago")?.contains("10 September 2026") == true)
        #expect(result("1 year from today")?.contains("24 September 2027") == true)
        #expect(result("3 months later")?.contains("24 December 2026") == true)
        #expect(result("days until 24 dec") == "91 days")
        #expect(result("days until christmas") == "92 days")
        #expect(result("weeks until 2026-12-24") == "13 weeks")
        #expect(result("days until 2026-09-24") == "Today")
        #expect(result("days until 2026-09-25") == "1 day")
        // A day without a year that has passed means the next one.
        #expect(result("days until 1 jan") == "99 days")
        #expect(result("days since 2026-09-14") == "10 days ago")
        #expect(result("days until blah") == nil)
    }

    @Test func moreUnits() {
        // In the user's number format, as the calculator always answered.
        func number(_ text: String) -> Double? {
            result(text).flatMap { $0.split(separator: " ").first }.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        }
        #expect(abs((number("1 bar in psi") ?? 0) - 14.5038) < 0.001)
        #expect(abs((number("100 hp in kw") ?? 0) - 74.57) < 0.01)
        #expect(abs((number("180 deg in rad") ?? 0) - Double.pi) < 0.0001)
        #expect(number("2 days in hours") == 48)
        #expect(number("1 week in days") == 7)
        #expect(abs((number("3 tbsp in tsp") ?? 0) - 9) < 0.001)
        #expect(number("1 kwh in kj") == 3600)
        #expect(number("1 gib in mib") == 1024)
        #expect(result("1 week in days")?.hasSuffix(" d") == true)
    }

    @Test func currenciesOnlyWithRates() {
        let rates = ["USD": 1.1, "HUF": 400.0, "GBP": 0.85]
        #expect(result("100 usd in eur") == nil)
        #expect(result("110 usd in eur", rates: rates) == "100 EUR")
        #expect(result("€50 to huf", rates: rates)?.filter(\.isNumber) == "20000")
        #expect(result("20 dollars in forint", rates: rates)?.hasSuffix("HUF") == true)
        #expect(result("1 eur in gbp", rates: rates)?.replacingOccurrences(of: ",", with: ".") == "0.85 GBP")
        #expect(result("100 usd in xyz", rates: rates) == nil)
        #expect(result("100 usd in usd", rates: rates) == nil)
        // A unit conversion is never taken for a currency.
        #expect(AssistantCalculator.currencyQuery("10 km in mi") == nil)
        #expect(AssistantCalculator.currencyQuery("100 usd in eur")?.to == "EUR")
        #expect(AssistantCalculator.currencyQuery("time in tokyo") == nil)
    }

    /// What was a sum, a conversion or a plain search stays one.
    @Test func theOldAnswersAreUnchanged() {
        #expect(result("12 + 30 * 2") == "72")
        #expect(result("10 km in mi")?.replacingOccurrences(of: ",", with: ".").hasPrefix("6.21") == true)
        #expect(result("safari") == nil)
        #expect(result("system settings") == nil)
        #expect(result("what time is it") == nil)
    }
}
