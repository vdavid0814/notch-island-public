import Foundation
import Testing
@testable import NotchIslandKit

// Every permission Siri's search leans on, broken every way at once, without touching the Mac's
// real permissions: each source is stubbed as working, refused (nothing back) or hanging (a
// privacy prompt nobody answers, a busy Spotlight index). A tester saw "xcode" list only Search
// the Web and Ask ChatGPT until a permission Reset (v0.8.1).

/// How a source behaves.
nonisolated enum SourceFault: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case works, refused, hangs
    var testDescription: String { rawValue }

    func run<T: Sendable>(_ answer: T, refused empty: T) async -> T {
        switch self {
        case .works: return answer
        case .refused: return empty
        case .hangs:
            try? await Task.sleep(for: .seconds(3600))
            return empty
        }
    }
}

/// One broken Mac: how Spotlight's name query, Spotlight's app list, the file folders, the
/// dictionary and Contacts each behave.
nonisolated struct BrokenMac: Sendable, CustomTestStringConvertible {
    var apps: SourceFault, appList: SourceFault, files: SourceFault, dictionary: SourceFault, contacts: SourceFault

    var testDescription: String {
        "apps \(apps.rawValue), list \(appList.rawValue), files \(files.rawValue), dictionary \(dictionary.rawValue), contacts \(contacts.rawValue)"
    }

    static let all: [BrokenMac] = SourceFault.allCases.flatMap { apps in
        SourceFault.allCases.flatMap { appList in
            SourceFault.allCases.flatMap { files in
                SourceFault.allCases.flatMap { dictionary in
                    SourceFault.allCases.map { contacts in
                        BrokenMac(apps: apps, appList: appList, files: files, dictionary: dictionary, contacts: contacts)
                    }
                }
            }
        }
    }
}

@MainActor @Suite(.timeLimit(.minutes(1))) struct BrokenPermissionsTests {
    nonisolated static let xcode = AssistantHit(kind: .app, url: URL(fileURLWithPath: "/Users/someone/Downloads/Xcode.app"), name: "Xcode",
                                    contentType: "com.apple.application-bundle", lastUsed: nil)
    nonisolated static let notes = AssistantHit(kind: .file, url: URL(fileURLWithPath: "/Users/someone/Documents/xcode notes.txt"),
                                    name: "xcode notes.txt", contentType: nil, lastUsed: nil)
    nonisolated static let person = AssistantContact(id: "1", name: "Xcode Support", organization: nil, phones: [], emails: [])

    func sources(_ mac: BrokenMac) -> AssistantSources {
        var sources = stubSources()
        sources.apps = { query, _ in await mac.apps.run(AssistantMatch.matches("Xcode", query) ? [Self.xcode] : [], refused: []) }
        sources.allApps = { await mac.appList.run([Self.xcode], refused: []) }
        sources.files = { query, _, _ in await mac.files.run(AssistantMatch.matches(Self.notes.name, query) ? [Self.notes] : [], refused: []) }
        sources.define = { word in await mac.dictionary.run(AssistantDefinition(word: word, text: "Xcode | noun\nApple's IDE."), refused: nil) }
        sources.contacts = { _, _ in await mac.contacts.run([Self.person], refused: []) }
        sources.contactsAccess = { mac.contacts == .refused ? .denied : .granted }
        return sources
    }

    func model(_ mac: BrokenMac) -> AssistantModel {
        let defaults = UserDefaults(suiteName: "BrokenPermissionsTests.\(UUID().uuidString)")!
        // Files were allowed once: they come with every query (as on the tester's Mac).
        defaults.set(true, forKey: AssistantModel.filesKey)
        let model = AssistantModel(defaults: defaults, sources: sources(mac))
        model.sourceLimit = .milliseconds(150)
        model.begin()
        return model
    }

    @Test(arguments: BrokenMac.all)
    func whatStillWorksIsListedAndNothingWaitsForWhatDoesNot(_ mac: BrokenMac) async {
        let model = model(mac)
        model.query = "xcode"
        // A hanging source sleeps for an hour: getting past this at all means none was waited
        // for beyond its deadline (with no deadline, 211 of the 243 Macs never got past it).
        await model.settle()
        let rows = model.rows
        let hasApp = rows.contains(.hit(Self.xcode))
        #expect(hasApp == (mac.apps == .works || mac.appList == .works), "Xcode listed: \(hasApp)")
        #expect(rows.contains(.hit(Self.notes)) == (mac.files == .works))
        #expect(rows.contains { if case .definition = $0 { true } else { false } } == (mac.dictionary == .works))
        #expect(rows.contains { if case .contact = $0 { true } else { false } } == (mac.contacts == .works))
        // The answers that need no permission are always there.
        #expect(rows.contains(.searchWeb))
    }

    @Test func theFilesSuggestionDoesNotWaitForAFolderThatNeverAnswers() async {
        let model = model(BrokenMac(apps: .works, appList: .works, files: .hangs, dictionary: .works, contacts: .works))
        model.open(.files)
        model.query = "xcode"
        await model.settle()
        #expect(model.rows.isEmpty)
    }

    @Test func anAppListThatLandsAfterTheQueryIsSearchedToo() async {
        let gate = Shared(false)
        var sources = stubSources()
        sources.allApps = {
            while !gate.value { try? await Task.sleep(for: .milliseconds(10)) }
            return [Self.xcode]
        }
        let model = AssistantModel(defaults: UserDefaults(suiteName: "BrokenPermissionsTests.\(UUID().uuidString)")!, sources: sources)
        model.begin()
        // Spotlight's name query misses it; only the full list has it, and it is late.
        model.query = "xcode"
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!model.rows.contains(.hit(Self.xcode)))
        gate.value = true
        await model.settle()
        #expect(model.rows.contains(.hit(Self.xcode)))
    }
}

@MainActor @Suite struct QuickAppsTests {
    @Test func theAppsOnDiskAreListedWhileSpotlightsListIsStillRead() async {
        let gate = Shared(false)
        var sources = stubSources()
        sources.allApps = {
            while !gate.value { try? await Task.sleep(for: .milliseconds(10)) }
            return [BrokenPermissionsTests.xcode]
        }
        sources.quickApps = { [BrokenPermissionsTests.xcode] }
        let model = AssistantModel(defaults: UserDefaults(suiteName: "QuickAppsTests.\(UUID().uuidString)")!, sources: sources)
        model.begin()
        model.open(.applications)
        for _ in 0..<100 where !model.rows.contains(.hit(BrokenPermissionsTests.xcode)) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.rows.contains(.hit(BrokenPermissionsTests.xcode)))
        gate.value = true
        await model.settle()
        #expect(model.rows.contains(.hit(BrokenPermissionsTests.xcode)))
    }
}

@MainActor @Suite struct CurrencyOfferTests {
    @Test func aConversionWithCurrenciesOffOffersToTurnThemOn() async {
        var sources = stubSources()
        sources.rates = { ["USD": 1.1, "HUF": 400] }
        var settings = SiriSettings()
        let model = AssistantModel(defaults: UserDefaults(suiteName: "CurrencyOfferTests.\(UUID().uuidString)")!, sources: sources)
        model.settings = { settings }
        model.enableCurrencies = { settings.convertsCurrency = true }
        model.begin()
        model.query = "100 usd in huf"
        await model.settle()
        #expect(model.rows.first == .permission(.currencies))
        // Not for anything else.
        model.query = "12 km in mi"
        await model.settle()
        #expect(!model.rows.contains(.permission(.currencies)))
        model.query = "100 usd in huf"
        await model.settle()
        model.activateSelection()
        #expect(settings.convertsCurrency)
        await model.settle()
        try? await Task.sleep(for: .milliseconds(50))
        guard case .calculation(let result)? = model.rows.first else {
            Issue.record("no conversion after turning currencies on: \(model.rows.map(\.id))")
            return
        }
        #expect(result.result.hasSuffix("HUF"))
        #expect(!model.rows.contains(.permission(.currencies)))
    }
}

@Suite struct AppNameReachTests {
    @Test func aNameTypedWithoutItsSpacesIsFound() {
        #expect(AssistantMatch.matches("App Store", "appstore"))
        #expect(AssistantMatch.matches("App Store", "appst"))
        #expect(AssistantMatch.matches("Visual Studio Code", "studiocode"))
        #expect(AssistantMatch.matches("Visual Studio Code", "visualstudioc"))
        #expect(AssistantMatch.matches("Device Hub", "devicehub"))
        // Not across a word's middle, not with letters left over.
        #expect(!AssistantMatch.matches("App Store", "apxs"))
        #expect(!AssistantMatch.matches("App Store", "ppstore"))
        #expect(!AssistantMatch.matches("App Store", "appstorex"))
    }

    @Test func appsSpotlightFoundElsewhereAreKeptAndListedWithoutIt() {
        let defaults = UserDefaults(suiteName: "AppNameReachTests.\(UUID().uuidString)")!
        func app(_ path: String) -> AssistantHit {
            AssistantHit(kind: .app, url: URL(fileURLWithPath: path), name: "", contentType: nil, lastUsed: nil)
        }
        let downloads = NSHomeDirectory() + "/Downloads/Xcode.app"
        AssistantSearch.remember([app("/Applications/Safari.app"), app(downloads),
                                  app(downloads + "/Contents/Applications/DeviceHub.app"),
                                  app("/System/Applications/Notes.app"), app("/Users/Shared/Tools/Thing.app")], defaults: defaults)
        #expect(AssistantSearch.remembered(defaults) == [downloads, "/Users/Shared/Tools/Thing.app"])
        let listed = AssistantSearch.diskApps(defaults: defaults)
        #expect(listed.contains { $0.url.path == downloads && $0.name == "Xcode" })
        // The next answer without it: gone.
        AssistantSearch.remember([app("/Users/Shared/Tools/Thing.app")], defaults: defaults)
        #expect(AssistantSearch.remembered(defaults) == ["/Users/Shared/Tools/Thing.app"])
        #expect(AssistantSearch.isProtected(downloads) && !AssistantSearch.isProtected("/Users/Shared/Tools/Thing.app"))
    }
}
