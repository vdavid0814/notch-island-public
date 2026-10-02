import AppKit
import CoreGraphics
import Foundation
import Metal
import QuartzCore
import Synchronization
import SwiftUI
import Testing
@testable import NotchIslandKit

/// A clock a test moves by hand: sleepers wake when it is moved past their deadline.
final class ManualClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
        var nextID = 0
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = state.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let wake: (any Error)?? = state.withLock { state in
                    if Task.isCancelled { return .some(CancellationError()) }
                    if deadline <= state.now { return .some(nil) }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return nil
                }
                switch wake {
                case .some(.some(let error)): continuation.resume(throwing: error)
                case .some(.none): continuation.resume()
                case .none: break
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return state.sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in due { sleeper.continuation.resume() }
    }
}

/// What a closed Siri keeps, and for how long; the root's lookups per keystroke.
@MainActor @Suite struct AssistantKeepTests {
    /// Turns of the main actor until `done` (a woken task has to run).
    func settle(until done: () -> Bool) async {
        for _ in 0..<200 where !done() { await Task.yield() }
    }

    @Test func listsOutliveACloseForTheKeepDurationOnly() async {
        let clock = ManualClock()
        let reads = Mutex([String: Int]())
        var sources = stubSources()
        sources.shortcuts = {
            reads.withLock { $0["shortcuts", default: 0] += 1 }
            return ["Wiki"]
        }
        sources.settingsPanes = {
            reads.withLock { $0["panes", default: 0] += 1 }
            return [SystemSettingsPane(title: "Wi-Fi", extensionID: "com.apple.wifi-settings-extension")]
        }
        sources.emoji = {
            reads.withLock { $0["emoji", default: 0] += 1 }
            return [AssistantEmoji(character: "🧙", name: "mage", aliases: ["wizard"])]
        }
        sources.windows = { _ in
            reads.withLock { $0["windows", default: 0] += 1 }
            return []
        }
        let model = AssistantModel(defaults: UserDefaults(suiteName: "AssistantKeepTests.\(UUID().uuidString)")!, sources: sources)
        model.clock = clock
        func open() async {
            model.begin()
            model.query = "wi"
            await model.settle()
        }
        await open()
        #expect(reads.withLock { $0 } == ["shortcuts": 1, "panes": 1, "emoji": 1, "windows": 1])
        #expect(model.rows.contains(.emoji(AssistantEmoji(character: "🧙", name: "mage", aliases: ["wizard"]))))

        // Closed, and opened again before the keep ran out: nothing is read or built again but
        // the running apps (read live at every opening).
        model.end()
        await settle { clock.sleeperCount == 1 }
        clock.advance(by: AssistantModel.listsKeepDuration - .milliseconds(100))
        await settle { false }
        #expect(model.shortcuts != nil && model.settingsPanes != nil && model.emoji != nil && model.windows == nil)
        await open()
        #expect(reads.withLock { $0 } == ["shortcuts": 1, "panes": 1, "emoji": 1, "windows": 2])
        // The opening stopped the pending release.
        #expect(clock.sleeperCount == 0)

        // Closed for the whole keep: everything goes, and the next opening reads it again.
        model.end()
        await settle { clock.sleeperCount == 1 }
        clock.advance(by: AssistantModel.listsKeepDuration)
        await settle { model.emoji == nil }
        #expect(model.shortcuts == nil && model.settingsPanes == nil && model.emoji == nil)
        await open()
        #expect(reads.withLock { $0 } == ["shortcuts": 2, "panes": 2, "emoji": 2, "windows": 3])
        model.end()
    }

    @Test func emojiIndexRanksExactlyAsTheWholeTable() async {
        let table = await EmojiTable.build()
        let index = EmojiIndex(table)
        func ranked(_ text: String) -> [AssistantEmoji] {
            table.compactMap { item in item.rank(for: text).map { (item, $0) } }
                .enumerated().sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
                .map(\.element.0)
        }
        let letters = "abcdefghijklmnopqrstuvwxyz0123456789".map(String.init)
        let queries = letters + letters.flatMap { first in ["a", "e", "o", "r"].map { first + $0 } } + [
            "heart", "thumbs u", "thumbs up", "+1", "-1", "ok", "face tears", "tears face", "flag", "hungary flag",
            "côte", "cote", "HUN", "Fire", "man tech", "red heart", "face with", "cat face", "😂", "zz top", "flag hu", "e",
        ]
        for query in queries {
            #expect(index.matching(query) == ranked(query), "\(query)")
        }
        #expect(index.matching("") == table)
    }

    @Test func paneMatchesFollowTheMatchingMode() async {
        let model = AssistantModel(defaults: UserDefaults(suiteName: "AssistantKeepTests.\(UUID().uuidString)")!,
                                   sources: stubSources(panes: await SystemSettingsPane.table()))
        model.begin()
        model.open(.system)
        await model.settle()
        func panes() -> [String] { model.rows.compactMap { if case .settingsPane(let pane) = $0 { pane.title } else { nil } } }
        model.query = "tooth"
        #expect(panes().isEmpty)
        var settings = SiriSettings()
        settings.matching = .anywhere
        model.settings = { settings }
        #expect(panes().contains("Bluetooth"))
        model.end()
    }
}

/// Typing "smile" as `demo/siritype` does, with every kind of result on: the rows each query shows,
/// and which steps tell the views reading them (the list, the island's size) to update.
@MainActor @Suite struct AssistantTypingTests {
    static let typed = ["s", "sm", "smi", "smil", "smile"]

    static func typingModel() async -> AssistantModel {
        let defaults = UserDefaults(suiteName: "AssistantTypingTests.\(UUID().uuidString)")!
        defaults.set(true, forKey: AssistantModel.filesKey)
        let sources = stubSources(
            apps: ["Smile Studio", "Simulator", "Messages", "Slack"], files: ["smile.png", "Small print.pdf", "sms.txt"],
            allApps: ["Safari", "Smile Studio", "Simulator", "Slack", "System Settings", "Messages"],
            shortcuts: ["Smile back", "Send message"], panes: await SystemSettingsPane.table(),
            windows: [AssistantWindow(pid: 1, appName: "Slack", appPath: "/Applications/Slack.app"),
                      AssistantWindow(pid: 2, appName: "Smile Studio", appPath: "/Applications/Smile Studio.app")],
            emoji: await EmojiTable.build())
        let model = AssistantModel(defaults: defaults, sources: sources)
        var settings = SiriSettings()
        settings.searchDelay = 0
        model.settings = { settings }
        return model
    }

    /// Whether `step` told a reader of `rows` and `room` to update.
    static func invalidates(_ model: AssistantModel, _ step: () async -> Void) async -> Bool {
        let fired = Mutex(false)
        withObservationTracking {
            _ = model.rows
            _ = model.room
        } onChange: {
            fired.withLock { $0 = true }
        }
        await step()
        return fired.withLock { $0 }
    }

    @Test func typedRowsStayAsTheyWere() async {
        let model = await Self.typingModel()
        model.begin()
        await model.settle()
        var shown: [String] = []
        for text in Self.typed {
            model.query = text
            await model.settle()
            // Apple Intelligence's row only where this Mac has it.
            shown.append(text + ": " + model.rows.filter { $0 != .askIntelligence }.map(\.id).joined(separator: " | "))
        }
        #expect(shown == [
            "s: hit:/stub/app/Safari | hit:/stub/app/Smile Studio | hit:/stub/app/Simulator | command:settings:general | command:settings:widgets | pane:com.apple.Software-Update-Settings.extension | pane:com.apple.settings.Storage | hit:/stub/file/smile.png | hit:/stub/file/Small print.pdf | hit:/stub/file/sms.txt | window:1:0 | window:2:0 | action:island:stopwatch | action:island:shelf | web | chatgpt",
            "sm: hit:/stub/app/Smile Studio | hit:/stub/file/smile.png | hit:/stub/file/Small print.pdf | hit:/stub/file/sms.txt | window:2:0 | action:shortcut:Smile back | emoji:🔸 | emoji:🔹 | web | chatgpt",
            "smi: hit:/stub/app/Smile Studio | hit:/stub/file/smile.png | window:2:0 | action:shortcut:Smile back | emoji:😀 | emoji:😃 | category:7 | web | chatgpt",
            "smil: hit:/stub/app/Smile Studio | hit:/stub/file/smile.png | window:2:0 | action:shortcut:Smile back | emoji:😀 | emoji:😃 | category:7 | web | chatgpt",
            "smile: hit:/stub/app/Smile Studio | hit:/stub/file/smile.png | window:2:0 | action:shortcut:Smile back | emoji:😀 | emoji:😊 | category:7 | web | chatgpt",
        ])
        model.end()
    }

    /// Matching a kept name is matching it afresh (`AssistantMatch` keeps names folded).
    @Test func keptNamesMatchAsFresh() async {
        let model = await Self.typingModel()
        let names = (await SystemSettingsPane.table()).flatMap { [$0.title] + $0.synonyms }
            + model.commands(matching: "").flatMap(\.searchNames)
            + ["DeviceHub", "Visual Studio Code", "Zene", "Côte d’Ivoire", "WhatsApp", "App Store", ""]
        let queries = ["s", "sm", "smile", "blue", "wi fi", "wifi", "device hub", "zé", "SOUND", "  ", "vsc", "tooth", "sys set"]
        for mode in SiriMatching.allCases {
            let fresh = queries.map { query in
                names.map { name in
                    AssistantMatch.forget()
                    return AssistantMatch.matches(name, query, mode)
                }
            }
            let kept = queries.map { query in names.map { AssistantMatch.matches($0, query, mode) } }
            #expect(fresh == kept, "\(mode)")
        }
        let starts = queries.map { query in names.map { AssistantMatch.startsName($0, query) } }
        AssistantMatch.forget()
        #expect(starts == queries.map { query in names.map { name in
            AssistantMatch.forget()
            return AssistantMatch.startsName(name, query)
        } })
    }

    @Test func onlyWhatChangesUpdatesTheList() async {
        let model = await Self.typingModel()
        model.begin()
        await model.settle()
        // Closed and opened again with nothing typed (`spam-siri`): the suggestions stay as they are.
        #expect(await !Self.invalidates(model) { model.end() })
        #expect(await !Self.invalidates(model) {
            model.begin()
            await model.settle()
        })
        model.query = "smil"
        await model.settle()
        model.query = "smile"
        // Its search finds the hits the typing kept: nothing to redraw when it lands.
        #expect(await !Self.invalidates(model) { await model.settle() })
        model.end()
    }

    /// `NI_BENCH=1`: the model's side of typing "smile" and closing, many times over: time, and how
    /// many steps updated the views reading the rows.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NI_BENCH"] == "1"))
    func benchmarkTyping() async {
        let model = await Self.typingModel()
        var updates = 0, steps = 0
        var runs: [Duration] = []
        for _ in 0..<50 {
            let started = ContinuousClock.now
            model.begin()
            await model.settle()
            for text in Self.typed {
                for step in [{ model.query = text }, { await model.settle() }] as [() async -> Void] {
                    steps += 1
                    if await Self.invalidates(model, step) { updates += 1 }
                }
            }
            steps += 1
            if await Self.invalidates(model, { model.end() }) { updates += 1 }
            runs.append(ContinuousClock.now - started)
        }
        print("siri typing bench: \(runs.sorted()[runs.count / 2]) a run (median); \(updates) of \(steps) steps updated the rows")
    }

    /// Siri hosted offscreen (the app's own sources), its rows showing.
    static func hosted() -> (model: AppModel, host: NSHostingView<some View>, window: NSWindow) {
        let model = AppModel()
        model.island.apply(.assistant(.list), animation: nil)
        let size = model.layout.size(for: .assistant(.list))
        let host = NSHostingView(rootView: AssistantView().environment(model))
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        return (model, host, window)
    }

    static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { textField(in: $0) }.first
    }

    /// `demo/siritype` sets the query from outside the field: the field shows every step of it.
    @Test func aQuerySetFromOutsideShowsInTheField() async throws {
        let (model, host, window) = Self.hosted()
        defer { window.contentView = nil }
        model.assistant.begin()
        defer { model.assistant.end() }
        for text in Self.typed {
            model.assistant.query = text
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            #expect(try #require(Self.textField(in: host)).stringValue == text)
        }
    }

    /// `NI_BENCH=1`: the main thread's time for typing "smile" into Siri hosted offscreen (its
    /// searches landing between the keys) and closing it.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NI_BENCH"] == "1"))
    func benchmarkTypingInTheView() async {
        let (model, host, window) = Self.hosted()
        defer { window.contentView = nil }
        func threadSeconds() -> Double {
            var time = timespec()
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
            return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
        }
        // Opening, each key, each search landing and closing, apart; the median run of each (the
        // test may run on either kind of core).
        var busy: [String: [Double]] = [:]
        for run in 0..<31 {
            var phases: [String: Double] = [:]
            func measure(_ phase: String, _ step: () async -> Void) async {
                let started = threadSeconds()
                await step()
                await Task.yield()
                host.layoutSubtreeIfNeeded()
                phases[phase, default: 0] += threadSeconds() - started
            }
            await measure("open") {
                model.assistant.begin()
                await Task.yield()
                host.layoutSubtreeIfNeeded()
                await model.assistant.settle()
            }
            for text in Self.typed {
                await measure("keys") { model.assistant.query = text }
                await measure("landings") { await model.assistant.settle() }
            }
            await measure("close") { model.assistant.end() }
            phases["total"] = phases.values.reduce(0, +)
            // The first run builds the views and reads the lists: left out.
            if run > 0 { for (phase, time) in phases { busy[phase, default: []].append(time) } }
        }
        let report = ["open", "keys", "landings", "close", "total"].map { phase in
            "\(phase) \(Int(busy[phase, default: [0]].sorted()[busy[phase, default: [0]].count / 2] * 1e6))"
        }
        print("siri view typing bench (µs of main thread, median run of typing \"smile\"): " + report.joined(separator: ", "))
    }
}

/// Siri's app icons on disk: kept, found again, replaced when the app changes, purged.
@Suite struct IconDiskCacheTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("IconDiskCacheTests-\(UUID().uuidString)", isDirectory: true)
    var folder: URL { root.appendingPathComponent("Icons", isDirectory: true) }
    static let style = "Dark|RegularAutomatic|-|-|Version 27.0 (Build 27A1)"

    /// An app bundle of its own, with its `Contents/Info.plist`.
    func app(_ name: String) throws -> String {
        let url = root.appendingPathComponent("Apps/\(name).app", isDirectory: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("<plist/>".utf8).write(to: url.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: url.path)
        return url.path
    }

    /// A small picture with every byte different, in the given layout.
    static func picture(space: CFString = CGColorSpace.sRGB,
                        info: UInt32 = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) -> CGImage {
        let context = CGContext(data: nil, width: 6, height: 5, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: space)!, bitmapInfo: info)!
        for y in 0..<5 {
            for x in 0..<6 {
                context.setFillColor(red: CGFloat(x) / 6, green: CGFloat(y) / 5, blue: 0.4, alpha: 0.5 + CGFloat(x * y) / 60)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return context.makeImage()!
    }

    static func same(_ a: CGImage?, _ b: CGImage) -> Bool {
        guard let a else { return false }
        return a.width == b.width && a.height == b.height && a.bytesPerRow == b.bytesPerRow && a.bitmapInfo == b.bitmapInfo
            && a.colorSpace?.name == b.colorSpace?.name && a.dataProvider?.data as Data? == b.dataProvider?.data as Data?
    }

    func entries() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] }

    func used(_ app: String, _ variant: String, style: String = Self.style) throws -> Date {
        let file = folder.appendingPathComponent(IconDiskCache.name(app: app, variant: variant, style: style))
        return try #require(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    }

    func setUsed(_ app: String, _ variant: String, style: String = Self.style, _ date: Date) throws {
        let file = folder.appendingPathComponent(IconDiskCache.name(app: app, variant: variant, style: style))
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
    }

    @Test func aKeptIconComesBackWithTheSamePixelsWithoutDrawing() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let safari = try app("Safari")
        let picture = Self.picture()
        var draws = 0
        let drawn = IconDiskCache(folder: folder).image(forApp: safari, variant: "gallery 96px", style: Self.style) { draws += 1; return picture }
        // Another launch: from disk.
        let kept = IconDiskCache(folder: folder).image(forApp: safari, variant: "gallery 96px", style: Self.style) { draws += 1; return picture }
        #expect(draws == 1)
        #expect(Self.same(drawn, picture) && Self.same(kept, picture))
        // Another size or icon style is another entry.
        _ = IconDiskCache(folder: folder).image(forApp: safari, variant: "row 2.0x", style: Self.style) { draws += 1; return picture }
        _ = IconDiskCache(folder: folder).image(forApp: safari, variant: "row 2.0x", style: "-" + Self.style.dropFirst(4)) { draws += 1; return picture }
        #expect(draws == 3)
        // A picture in another layout and colour space comes back as it was, too.
        let p3 = Self.picture(space: CGColorSpace.displayP3, info: CGImageAlphaInfo.premultipliedLast.rawValue)
        let data = try #require(IconDiskCache.encode(p3, app: safari, variant: "p3", style: Self.style, modified: 1))
        #expect(Self.same(IconDiskCache.decode(data)?.1, p3))
    }

    @Test func anUpdatedAppIsDrawnAgain() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = try app("Notes")
        let cache = IconDiskCache(folder: folder)
        var draws = 0
        _ = cache.image(forApp: notes, variant: "gallery", style: Self.style) { draws += 1; return Self.picture() }
        // A new custom icon: the bundle's own date.
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: notes)
        _ = cache.image(forApp: notes, variant: "gallery", style: Self.style) { draws += 1; return Self.picture() }
        _ = cache.image(forApp: notes, variant: "gallery", style: Self.style) { draws += 1; return Self.picture() }
        #expect(draws == 2)
        // An update in place: only the contents change, the bundle keeps its date (Chrome, Cursor).
        let bundleDate = try #require(try URL(fileURLWithPath: notes).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: notes + "/Contents/Info.plist")
        #expect(try URL(fileURLWithPath: notes).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == bundleDate)
        _ = cache.image(forApp: notes, variant: "gallery", style: Self.style) { draws += 1; return Self.picture() }
        _ = cache.image(forApp: notes, variant: "gallery", style: Self.style) { draws += 1; return Self.picture() }
        #expect(draws == 3)
        // The new drawing took the old one's place.
        #expect(entries().count == 1)
        // An app that cannot be read is drawn every time and never kept.
        _ = cache.image(forApp: root.appendingPathComponent("Gone.app").path, variant: "gallery", style: Self.style) { draws += 1; return Self.picture() }
        #expect(draws == 4 && entries().count == 1)
    }

    @Test func aReadOnlyLookupNeitherKeepsNorMarksUsed() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let maps = try app("Maps"), mail = try app("Mail")
        let cache = IconDiskCache(folder: folder)
        var draws = 0
        // Drawn, not kept.
        _ = cache.image(forApp: maps, variant: "row 2.0x", style: Self.style, writes: false) { draws += 1; return Self.picture() }
        #expect(draws == 1 && entries().isEmpty)
        // A kept one is read, and its date stays.
        _ = cache.image(forApp: mail, variant: "row 2.0x", style: Self.style) { draws += 1; return Self.picture() }
        let long = Date(timeIntervalSinceNow: -86_400)
        try setUsed(mail, "row 2.0x", long)
        let read = cache.image(forApp: mail, variant: "row 2.0x", style: Self.style, writes: false) { draws += 1; return Self.picture() }
        #expect(draws == 2 && Self.same(read, Self.picture()))
        #expect(abs(try used(mail, "row 2.0x").timeIntervalSince(long)) < 1)
        // A read that may write marks it used.
        _ = cache.image(forApp: mail, variant: "row 2.0x", style: Self.style) { draws += 1; return Self.picture() }
        #expect(draws == 2)
        #expect(abs(try used(mail, "row 2.0x").timeIntervalSinceNow) < 60)
    }

    @Test func purgeDropsGoneAppsAndStylesThenTheLeastRecentlyUsed() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let names = ["Maps", "Mail", "Music", "Photos"]
        let apps = try names.map(app)
        var cache = IconDiskCache(folder: folder)
        for (index, app) in apps.enumerated() {
            _ = cache.image(forApp: app, variant: "gallery", style: Self.style) { Self.picture() }
            try setUsed(app, "gallery", Date(timeIntervalSinceNow: Double(index - 10) * 60))
        }
        // Maps, the oldest written, is used now: Mail is the least recently used.
        _ = cache.image(forApp: apps[0], variant: "gallery", style: Self.style) { Self.picture() }
        // The same icons in light mode stay; in an icon style or macOS build that is gone, they go.
        let light = "-" + Self.style.dropFirst(4)
        let oldBuild = "Dark|RegularAutomatic|-|-|Version 26.4 (Build 25E1)"
        _ = cache.image(forApp: apps[1], variant: "row 2.0x", style: light) { Self.picture() }
        _ = cache.image(forApp: apps[1], variant: "row 2.0x", style: oldBuild) { Self.picture() }
        try Data("not an icon".utf8).write(to: folder.appendingPathComponent("stray.icon"))
        try FileManager.default.removeItem(atPath: apps[3])
        cache.limit = 3
        cache.purge(style: Self.style)
        let left = Set(entries())
        // Photos is gone, the stray file unreadable, the old build's entry of a style that is gone,
        // Mail's gallery entry the least recently used of the four left.
        #expect(left == [IconDiskCache.name(app: apps[0], variant: "gallery", style: Self.style),
                         IconDiskCache.name(app: apps[2], variant: "gallery", style: Self.style),
                         IconDiskCache.name(app: apps[1], variant: "row 2.0x", style: light)])
    }
}

/// Siri's icons kept on disk: where, when, and never from the main thread.
@MainActor @Suite struct AssistantIconsDiskTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("AssistantIconsDiskTests-\(UUID().uuidString)", isDirectory: true)
    var folder: URL { root.appendingPathComponent("Icons", isDirectory: true) }

    func app(_ name: String) throws -> String {
        let url = root.appendingPathComponent("Apps/\(name).app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.deletingLastPathComponent().path
    }

    func entry(_ app: String, scale: CGFloat) -> Bool {
        let name = IconDiskCache.name(app: app, variant: "row \(scale)x", style: IconDiskCache.iconStyle())
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
    }

    @Test func rowsDrawnOnTheMainThreadAreNotKeptPreparedOnesAre() async throws {
        AssistantIcons.disk = IconDiskCache(folder: folder)
        defer {
            AssistantIcons.disk = IconDiskCache(folder: nil)
            try? FileManager.default.removeItem(at: root)
        }
        let first = try app("First"), second = try app("Second")
        // A row shown before its search drew it: drawn here, not written.
        _ = AssistantIcons.app(first, scale: 3)
        #expect(!entry(first, scale: 3))
        // Drawn ahead by a search (at the rows' scale): kept for the next launch.
        await AssistantIcons.prepare([.app(second)])
        #expect(entry(second, scale: 3))
    }

    @Test func closingSiriTidiesTheDiskAtMostOnceADay() async throws {
        AssistantIcons.disk = IconDiskCache(folder: folder)
        defer {
            AssistantIcons.disk = IconDiskCache(folder: nil)
            try? FileManager.default.removeItem(at: root)
        }
        let kept = try app("Kept")
        let stale = IconDiskCache(folder: folder)
        _ = stale.image(forApp: kept, variant: "row 2.0x", style: "Dark|Gone|-|-|Version 1") { IconDiskCacheTests.picture() }
        func staleCount() -> Int { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).count }
        #expect(staleCount() == 1)
        // Siri opened first, so no prewarm tidied: its close does.
        AssistantIcons.diskTidied = nil
        let model = AssistantModel(defaults: UserDefaults(suiteName: "AssistantIconsDiskTests.\(UUID().uuidString)")!, sources: stubSources())
        model.begin()
        model.end()
        #expect(AssistantIcons.diskTidied != nil)
        // On the background queue: done after a turn of it that follows the tidy's.
        for _ in 0..<20 where staleCount() > 0 { await Thrifty.runInBackground {} }
        #expect(staleCount() == 0)
        // Not again within the day.
        #expect(AssistantIcons.tidyDisk() == nil)
    }
}

/// Siri's answering glow: its flow played by the render server on a copy of SwiftUI's own layer.
@MainActor @Suite struct AssistantGlowFlowTests {
    static let size = CGSize(width: 180, height: 4)
    static let scale: CGFloat = 2

    /// The layer SwiftUI draws the band with at `phase`, in a window (not shown) at 2x.
    static func swiftUIBand(phase: TimeInterval) throws -> CAGradientLayer {
        let host = NSHostingView(rootView: AssistantGlow.band(phase: phase).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        func gradient(in layer: CALayer) -> CAGradientLayer? {
            layer as? CAGradientLayer ?? layer.sublayers?.lazy.compactMap(gradient).first
        }
        let layer = try #require(host.layer.flatMap(gradient))
        #expect(layer.contentsScale == scale)
        layer.removeFromSuperlayer()
        return layer
    }

    /// Step `index` of the flow, as `GlowFlow` shows it in a window at 2x.
    static func flowBand(at index: Int) throws -> CAGradientLayer {
        let layer = try #require(AssistantGlow.bandLayer(size: size))
        layer.contentsScale = scale
        // Held in the middle of the step.
        layer.add(AssistantGlow.flow(frozenAt: AssistantGlow.phase(ofFrame: index) + AssistantGlow.period / Double(2 * AssistantGlow.frameCount)),
                  forKey: "flow")
        return layer
    }

    /// `layer` drawn by Core Animation's own renderer (the render server's) at 2x, `size` points
    /// large over `background`: BGRA bytes. A layer of a window is put back in it afterwards.
    static func rendered(_ layer: CALayer, size: CGSize = size, background: CGColor? = nil) throws -> [UInt8] {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let root = CALayer()
        root.anchorPoint = .zero
        root.frame = CGRect(x: 0, y: 0, width: width, height: height)
        root.backgroundColor = background
        root.sublayerTransform = CATransform3DMakeScale(scale, scale, 1)
        let window = layer.superlayer
        defer { window?.addSublayer(layer) }
        layer.frame = CGRect(origin: .zero, size: size)
        root.addSublayer(layer)
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        renderer.layer = root
        renderer.bounds = root.bounds
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        let finished = try #require(queue.makeCommandBuffer())
        finished.commit()
        finished.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return bytes
    }

    @Test func eachStepIsTheBandSwiftUIDrawsAtItsPhase() throws {
        // One turn at the 30 fps the band was drawn at.
        #expect(abs(Double(AssistantGlow.frameCount) / AssistantGlow.period - 30) < 0.1)
        var previous: [UInt8]?
        for index in 0..<AssistantGlow.frameCount {
            let phase = AssistantGlow.phase(ofFrame: index)
            let reference = try Self.rendered(Self.swiftUIBand(phase: phase))
            #expect(reference.contains { $0 != 0 })
            #expect(try Self.rendered(Self.flowBand(at: index)) == reference, "step \(index)")
            // It flows.
            #expect(reference != previous)
            previous = reference
            let copied = try #require(AssistantGlow.bandLayer(size: Self.size, phase: phase))
            let point = AssistantGlow.endPoint(phase: phase)
            #expect(abs(copied.endPoint.x - point.x) < 1e-12 && abs(copied.endPoint.y - point.y) < 1e-12)
        }
    }

    @Test func theFlowingBandLiesWhereSwiftUIsStillOneDoesAndTurnsTheSameWay() throws {
        let model = AppModel()
        func hosted(flowing: Bool) -> (NSWindow, NSHostingView<some View>) {
            let host = NSHostingView(rootView: AssistantGlow(isFlowing: flowing).environment(model)
                .frame(width: Self.size.width).padding(20))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 220, height: 44), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            return (window, host)
        }
        func conic(in layer: CALayer) -> CAGradientLayer? {
            if let gradient = layer as? CAGradientLayer, gradient.type == .conic { return gradient }
            return layer.sublayers?.lazy.compactMap(conic).first
        }
        let (stillWindow, still) = hosted(flowing: false)
        let (flowWindow, flowing) = hosted(flowing: true)
        let swiftUIBand = try #require(still.layer.flatMap(conic))
        let band = try #require(flowing.layer.flatMap(conic))
        #expect(type(of: band) == CAGradientLayer.self && band.animation(forKey: "flow") != nil)
        #expect(band.contentsScale == swiftUIBand.contentsScale)
        // The same corners in the window, top-left first: not mirrored.
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: Self.size.width, y: Self.size.height)] {
            #expect(band.convert(corner, to: flowWindow.contentView?.layer?.superlayer)
                    == swiftUIBand.convert(corner, to: stillWindow.contentView?.layer?.superlayer))
        }
    }

    @Test func freezeHoldsTheFlow() {
        let frozen = AssistantGlow.flow(frozenAt: 2.0)
        #expect(frozen.speed == 0 && abs(frozen.timeOffset - (2.0 - AssistantGlow.period)) < 1e-9)
        let running = AssistantGlow.flow(frozenAt: nil)
        #expect(running.speed == 1 && running.repeatCount == .infinity && running.calculationMode == .discrete)
        #expect(running.values?.count == AssistantGlow.frameCount && running.keyTimes?.count == AssistantGlow.frameCount + 1)
        // Stepped at the band's 30 fps, not the display's rate.
        #expect(running.preferredFrameRateRange == CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30))
    }

    /// The base's glow, its timeline held at `phase`: its own view.
    struct TimelineGlow: View {
        let phase: TimeInterval

        var body: some View {
            TimelineView(ExplicitTimelineSchedule([Date(timeIntervalSinceReferenceDate: phase)])) { context in
                Capsule()
                    .fill(AngularGradient(colors: AssistantGlow.colors, center: .center,
                                          angle: .degrees((context.date.timeIntervalSinceReferenceDate * 220).truncatingRemainder(dividingBy: 360))))
                    .frame(height: 4)
                    .background {
                        Capsule()
                            .fill(LinearGradient(colors: AssistantGlow.colors, startPoint: .leading, endPoint: .trailing))
                            .blur(radius: 8)
                            .opacity(0.7)
                    }
                    .accessibilityHidden(true)
            }
        }
    }

    @Observable final class Look {
        var style = IslandGlassStyle.liquidGlass
        /// The glow's fade in or out (`.transition(.opacity)`), held.
        var opacity = 1.0
    }

    /// A glow along Siri's field, as the island shows it: under the island's legibility shadow.
    struct Field<Glow: View>: View {
        let glow: Glow
        let look: Look

        var body: some View {
            Color.clear
                .frame(height: IslandLayout.assistantFieldHeight)
                .background(.white.opacity(0.08), in: Capsule())
                .overlay(alignment: .bottom) {
                    glow
                        .padding(.horizontal, Metrics.Spacing.xLarge)
                        .offset(y: 2)
                        .opacity(look.opacity)
                }
                .frame(width: 300)
                .padding(20)
                .modifier(GlassLegibility(isInNotchBand: false))
                .environment(\.islandGlassStyle, look.style)
        }
    }

    @Test func inTheIslandTheFlowIsTheBaseTimelineToThePixel() throws {
        let model = AppModel()
        let size = CGSize(width: 340, height: 80)
        defer { LeanSpring.frozenTime = nil }
        func hosted(_ view: some View) -> (NSWindow, NSView) {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            return (window, host)
        }
        func largestDifference(_ a: [UInt8], _ b: [UInt8]) -> Int {
            zip(a, b).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
        }
        for index in [0, 16, 33] {
            let phase = AssistantGlow.phase(ofFrame: index)
            LeanSpring.frozenTime = phase + AssistantGlow.period / Double(2 * AssistantGlow.frameCount)
            // Glass (the shadow), black (none), and glass taken on while the glow shows.
            for (style, opacity, switched) in [(IslandGlassStyle.liquidGlass, 1.0, false), (.liquidGlass, 0.5, false), (.black, 1.0, false),
                                               (.liquidGlass, 0.5, true)] {
                let before = Look(), after = Look()
                for look in [before, after] {
                    look.style = switched ? .black : style
                    look.opacity = opacity
                }
                let (baseWindow, base) = hosted(Field(glow: TimelineGlow(phase: phase), look: before))
                let (flowWindow, flow) = hosted(Field(glow: AssistantGlow(isFlowing: true).environment(model), look: after))
                if switched {
                    for look in [before, after] { look.style = style }
                    for (window, host) in [(baseWindow, base), (flowWindow, flow)] {
                        host.layoutSubtreeIfNeeded()
                        window.displayIfNeeded()
                    }
                }
                for background in [CGColor(gray: 1, alpha: 1), CGColor(gray: 0, alpha: 1)] {
                    let reference = try Self.rendered(try #require(base.layer), size: size, background: background)
                    let drawn = try Self.rendered(try #require(flow.layer), size: size, background: background)
                    #expect(largestDifference(reference, drawn) <= 1, "step \(index) \(style) opacity \(opacity) switched \(switched)")
                }
            }
        }
    }

    @Test func aBandThatCannotBeCopiedFlowsAsSwiftUIsOwn() throws {
        // Copied at 180 points wide, not at 240.
        let view = GlowFlowView { size in size.width < 200 ? AssistantGlow.bandLayer(size: size) : nil }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 4), styleMask: .borderless, backing: .buffered, defer: false)
        let content = try #require(window.contentView)
        content.addSubview(view)
        view.frame = CGRect(x: 0, y: 0, width: 180, height: 4)
        content.layoutSubtreeIfNeeded()
        func conic(in layer: CALayer?) -> CAGradientLayer? {
            if let gradient = layer as? CAGradientLayer, gradient.type == .conic { return gradient }
            return layer?.sublayers?.lazy.compactMap(conic).first
        }
        #expect(conic(in: view.layer)?.animation(forKey: "flow") != nil && view.subviews.isEmpty)
        view.frame.size.width = 240
        content.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // SwiftUI's own band, flowing as a timeline, the band's size: never no band.
        let fallback = try #require(view.subviews.first)
        #expect(fallback.frame == view.bounds)
        let band = try #require(conic(in: fallback.layer))
        #expect(band.animation(forKey: "flow") == nil && band.convert(band.bounds, to: view.layer).size == view.bounds.size)
        #expect(view.layer?.sublayers?.contains { $0.animation(forKey: "flow") != nil } != true)
    }
}
