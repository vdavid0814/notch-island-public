import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct AppEnergyTests {
    private func reading(_ pid: pid_t, start: UInt64, joules: Double) -> ProcessEnergyReading {
        ProcessEnergyReading(pid: pid, start: start, energyNJ: UInt64(joules * 1e9))
    }

    @Test func sweepsCountWhatEachAppUsedSinceTheLastOne() {
        let keys: [pid_t: String] = [1: "safari", 2: "safari", 3: "mail", 4: "notes"]
        // The baseline: nothing counted, whatever ran before it.
        var step = AppEnergySweep.step(seen: [:], readings: [reading(1, start: 10, joules: 50), reading(3, start: 20, joules: 5)],
                                       lastSweep: nil) { keys[$0]! }
        #expect(step.joules.isEmpty)
        // Safari's helper (2) started since: all of it counts, to Safari. Mail's pid was used again
        // by Notes (another start): counted from its start as Notes, not as Mail going backwards.
        step = AppEnergySweep.step(seen: step.seen, readings: [reading(1, start: 10, joules: 58), reading(2, start: 150, joules: 3),
                                                               reading(3, start: 160, joules: 1)],
                                   lastSweep: 100) { $0 == 3 ? "notes" : keys[$0]! }
        #expect(step.joules["safari"].map { abs($0 - 11) < 1e-6 } == true)
        #expect(step.joules["notes"].map { abs($0 - 1) < 1e-6 } == true)
        #expect(step.joules["mail"] == nil)
        // A process already running at the baseline but first seen later counts nothing.
        step = AppEnergySweep.step(seen: step.seen, readings: [reading(4, start: 5, joules: 30)], lastSweep: 200) { keys[$0]! }
        #expect(step.joules.isEmpty)
    }

    @Test func rowsAddUpToWhatTheDayUsed() {
        var ledger = AppEnergyLedger()
        let day = Date(timeIntervalSince1970: 1_000_000)
        let apps = ["a": AppEnergyApp(name: "Alpha", path: "/Applications/Alpha.app"), "b": AppEnergyApp(name: "Beta", path: nil)]
        // A percent shared 3 : 1 by energy, then two percents all Alpha's.
        ledger.add(AppEnergyLedger.share(1, by: ["a": 30, "b": 10]), apps: apps, on: day)
        ledger.add(AppEnergyLedger.share(2, by: ["a": 5]), apps: apps, on: day)
        #expect(ledger.rows(on: day).map(\.name) == ["Alpha", "Beta"])
        #expect(ledger.rows(on: day).map(\.points) == [2.75, 0.25])
        // Daily Usage says 10: the 7 no app was measured for is a row of its own.
        let rows = ledger.rows(on: day, used: 10)
        #expect(rows.map(\.key) == [AppAttribution.unmeasuredKey, "a", "b"])
        #expect(rows.map(\.points).reduce(0, +) == 10)
        // A day used before anything was measured: all of it not measured; one unused: nothing.
        #expect(ledger.rows(on: day.addingTimeInterval(86_400), used: 5).map(\.key) == [AppAttribution.unmeasuredKey])
        #expect(ledger.rows(on: day.addingTimeInterval(86_400), used: 0).isEmpty)
        // A drop with nothing measured goes to macOS.
        #expect(AppEnergyLedger.share(1, by: [:]) == [AppAttribution.systemKey: 1])
        // Old days go, and the apps only they had.
        ledger.add(["b": 1], apps: apps, on: day.addingTimeInterval(9 * 86_400))
        ledger.prune(before: day.addingTimeInterval(86_400))
        #expect(ledger.days.count == 1 && ledger.apps.keys.sorted() == ["b"])
    }

    @Test func processesBelongToTheirOutermostApp() {
        #expect(AppAttribution.appBundle(in: "/Applications/Google Chrome.app/Contents/Frameworks/x.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/h")
            == "/Applications/Google Chrome.app")
        #expect(AppAttribution.appBundle(in: "/Applications/Notes.app") == "/Applications/Notes.app")
        #expect(AppAttribution.appBundle(in: "/usr/libexec/trustd") == nil)
        #expect(AppAttribution.app(forPath: "/usr/libexec/trustd").key == AppAttribution.systemKey)
        #expect(AppAttribution.app(forPath: "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock").key == AppAttribution.systemKey)
        #expect(AppAttribution.app(forPath: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder").key == "com.apple.finder")
        #expect(AppAttribution.app(forPath: "/System/Applications/Notes.app/Contents/MacOS/Notes").app.path == "/System/Applications/Notes.app")
        // This test process has someone responsible for it (itself at least).
        #expect(AppAttribution.responsible(for: getpid()) > 0)
    }

    @Test func eachPercentLostGoesToTheAppsThatUsedIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = folder.appendingPathComponent("app-battery.json")
        defer { try? FileManager.default.removeItem(at: folder) }
        let counter = Counter()
        let recorder = AppEnergyRecorder(url: url, read: { [counter] in
            [ProcessEnergyReading(pid: 7, start: 1, energyNJ: counter.next())]
        }, resolve: { _ in ("app", AppEnergyApp(name: "App", path: nil)) })
        recorder.power(onBattery: true, level: 80)    // the baseline
        recorder.power(onBattery: true, level: 78)    // two percents, the app's
        recorder.power(onBattery: true, level: 79)    // a rise: nothing
        recorder.power(onBattery: false, level: 79)   // plugged in: nothing more
        recorder.power(onBattery: false, level: 70)
        recorder.drain()
        let saved = try JSONDecoder().decode(AppEnergyLedger.self, from: Data(contentsOf: url))
        #expect(saved.rows(on: Calendar.autoupdatingCurrent.startOfDay(for: Date())).map(\.points) == [2])
        #expect(counter.reads == 2)
    }
}

private nonisolated final class Counter: @unchecked Sendable {
    private(set) var reads = 0
    func next() -> UInt64 {
        reads += 1
        return UInt64(reads) * 1_000_000_000
    }
}
