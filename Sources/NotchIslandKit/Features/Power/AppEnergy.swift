import Darwin
import Foundation

/// An app as Usage by App lists it: its name and its bundle (for the icon); nil for macOS's own
/// processes taken together.
nonisolated struct AppEnergyApp: Sendable, Codable, Equatable {
    var name: String
    var path: String?
}

/// One row of Usage by App: the battery an app used over a day, in percentage points (the rows of
/// a day add up to what Daily Usage says the day used), and its share of the day's.
nonisolated struct AppUsageRow: Sendable, Equatable, Identifiable {
    var key: String
    var name: String
    var path: String?
    /// Percentage points of the battery.
    var points: Double
    /// Of the day's use, 0…1.
    var share: Double

    var id: String { key }
    var isSystem: Bool { key == AppAttribution.systemKey }
    var isUnmeasured: Bool { key == AppAttribution.unmeasuredKey }
}

/// The battery each app used, a day each, as the iPhone's Battery Usage by App counts it: every
/// percent the battery drops goes to the apps by the energy each used since the drop before.
/// Kept for the days Daily Usage shows.
nonisolated struct AppEnergyLedger: Sendable, Codable, Equatable {
    /// Percentage points by app, by the day's local midnight.
    var days: [Date: [String: Double]] = [:]
    var apps: [String: AppEnergyApp] = [:]

    static let retention = BatteryHistory.retention

    mutating func add(_ points: [String: Double], apps found: [String: AppEnergyApp], on day: Date) {
        guard !points.isEmpty else { return }
        days[day, default: [:]].merge(points, uniquingKeysWith: +)
        for key in points.keys { if let app = found[key] { apps[key] = app } }
    }

    /// `drop` percentage points shared out by `energy` (joules by app); with no energy measured,
    /// all of it to macOS.
    static func share(_ drop: Double, by energy: [String: Double]) -> [String: Double] {
        let total = energy.values.reduce(0, +)
        guard drop > 0 else { return [:] }
        guard total > 0 else { return [AppAttribution.systemKey: drop] }
        return energy.compactMapValues { $0 > 0 ? drop * $0 / total : nil }
    }

    /// Forgets the days before `oldest`, and the apps only they had.
    mutating func prune(before oldest: Date) {
        days = days.filter { $0.key >= oldest }
        let used = Set(days.values.flatMap(\.keys))
        apps = apps.filter { used.contains($0.key) }
    }

    /// The day's apps, the most first. With `used` (Daily Usage's figure for the day), what the
    /// apps were not measured for — the hours before recording began, the app not running — is a
    /// row of its own, so the rows add up to it.
    func rows(on day: Date, used: Double? = nil) -> [AppUsageRow] {
        var values = (days[day] ?? [:]).filter { $0.value > 0 }
        let counted = values.values.reduce(0, +)
        if let used, used - counted >= 0.5 { values[AppAttribution.unmeasuredKey] = used - counted }
        let total = values.values.reduce(0, +)
        guard total > 0 else { return [] }
        return values.map { key, value in
            let app = key == AppAttribution.unmeasuredKey ? AppAttribution.unmeasured : apps[key] ?? AppEnergyApp(name: key, path: nil)
            return AppUsageRow(key: key, name: app.name, path: app.path, points: value, share: value / total)
        }
        .sorted { ($0.points, $1.name) > ($1.points, $0.name) }
    }
}

/// Which app a process works for: the app responsible for it (macOS's own record: a browser's
/// helpers, a command run in Terminal, an app's XPC services), as the outermost `.app` on its path.
/// Processes of no app, and macOS's own apps that are not opened by name (the Dock, the menu bar,
/// Control Center), count as macOS.
nonisolated enum AppAttribution {
    static let systemKey = "macOS"
    static var system: AppEnergyApp { AppEnergyApp(name: String(localized: "macOS"), path: nil) }
    /// What the day used that no app was measured for.
    static let unmeasuredKey = "unmeasured"
    static var unmeasured: AppEnergyApp { AppEnergyApp(name: String(localized: "Not measured"), path: nil) }

    /// The outermost app bundle on `path`.
    static func appBundle(in path: String) -> String? {
        if let range = path.range(of: ".app/") { return String(path[..<range.lowerBound]) + ".app" }
        return path.hasSuffix(".app") ? path : nil
    }

    /// One of macOS's own parts rather than an app someone opens.
    static func isSystem(bundle: String) -> Bool {
        guard bundle.hasPrefix("/System/Library/") else { return false }
        return !bundle.hasSuffix("/Finder.app") && !bundle.hasPrefix("/System/Library/CoreServices/Applications/")
    }

    /// The key and the app for a process run from `path`.
    static func app(forPath path: String?) -> (key: String, app: AppEnergyApp) {
        guard let path, let bundle = appBundle(in: path), !isSystem(bundle: bundle) else { return (systemKey, system) }
        let key = Bundle(path: bundle)?.bundleIdentifier ?? bundle
        var name = FileManager.default.displayName(atPath: bundle)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return (key, AppEnergyApp(name: name, path: bundle))
    }

    /// The process that `pid` works for (itself where macOS keeps no other).
    static func responsible(for pid: pid_t) -> pid_t {
        guard let lookup = responsibleLookup else { return pid }
        let owner = lookup(pid)
        return owner > 0 ? owner : pid
    }

    private typealias Lookup = @convention(c) (pid_t) -> pid_t
    /// `responsibility_get_pid_responsible_for_pid`, libsystem's (no header): what Activity Monitor
    /// groups an app's processes by.
    private static let responsibleLookup: Lookup? = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                                          "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: Lookup.self) }

    static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}

/// A process's energy counter as one sweep read it.
nonisolated struct ProcessEnergyReading: Sendable, Equatable {
    var pid: pid_t
    /// When it started (mach time): a pid used again is another process.
    var start: UInt64
    var energyNJ: UInt64
}

/// The arithmetic between two sweeps: each process's energy since the last one, by app. A process
/// started since the last sweep counts from its start; one already running at the first sweep
/// counts from that sweep (the baseline).
nonisolated enum AppEnergySweep {
    struct Seen: Sendable, Equatable {
        var start: UInt64
        var energyNJ: UInt64
        var key: String
    }

    static func step(seen: [pid_t: Seen], readings: [ProcessEnergyReading], lastSweep: UInt64?,
                     key: (pid_t) -> String) -> (seen: [pid_t: Seen], joules: [String: Double]) {
        var next: [pid_t: Seen] = [:]
        next.reserveCapacity(readings.count)
        var joules: [String: Double] = [:]
        for reading in readings {
            let used: UInt64
            let owner: String
            if let old = seen[reading.pid], old.start == reading.start {
                owner = old.key
                used = reading.energyNJ >= old.energyNJ ? reading.energyNJ - old.energyNJ : 0
            } else {
                owner = key(reading.pid)
                used = lastSweep.map { reading.start > $0 } == true ? reading.energyNJ : 0
            }
            next[reading.pid] = Seen(start: reading.start, energyNJ: reading.energyNJ, key: owner)
            if used > 0 { joules[owner, default: 0] += Double(used) / 1e9 }
        }
        return (next, joules)
    }

    /// Every process whose counter can be read: the user's own (the kernel measures root's too but
    /// keeps them from other users). About 12 ms of CPU for 500 processes.
    static func readAll() -> [ProcessEnergyReading] {
        var pids = [pid_t](repeating: 0, count: 4096)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        return pids.prefix(max(count, 0)).compactMap { pid in
            guard pid > 0 else { return nil }
            var info = rusage_info_v6()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            guard result == 0 else { return nil }
            return ProcessEnergyReading(pid: pid, start: info.ri_proc_start_abstime, energyNJ: info.ri_energy_nj)
        }
    }
}

/// Records which apps use the battery: every process's energy counter read at each percent the
/// battery drops and every five minutes between, while the Mac runs on battery, nothing on the
/// charger (no timer at all). Each drop goes to the apps by the energy they used since the drop
/// before, so a day's apps add up to the percent it used. All of it on a background queue of its
/// own; the ledger is handed to the main thread only while something shows it.
///
/// A process that ends between two sweeps loses its last few minutes, and one that starts and
/// ends between them is not seen; root's processes (WindowServer, the kernel) cannot be read.
nonisolated final class AppEnergyRecorder: @unchecked Sendable {
    static let interval: TimeInterval = 300

    /// Percentage points since Oct 13 2026 15:50; `app-energy.json` (joules, an afternoon's) before.
    static var defaultURL: URL? { DiagnosticsCenter.supportFolder?.appendingPathComponent("app-battery.json") }

    private let queue = DispatchQueue(label: "com.davidvarga.notchisland.app-energy", qos: .background)
    private let url: URL?
    private let now: @Sendable () -> Date
    private let read: @Sendable () -> [ProcessEnergyReading]
    private let resolve: @Sendable (pid_t) -> (key: String, app: AppEnergyApp)

    // Everything below on `queue` only.
    private var ledger = AppEnergyLedger()
    private var isLoaded = false
    private var onBattery = false
    private var seen: [pid_t: AppEnergySweep.Seen] = [:]
    private var lastSweep: UInt64?
    private var found: [String: AppEnergyApp] = [:]
    /// The battery's level at the last drop (or since unplugging), and each app's energy since.
    private var level: Int?
    private var pending: [String: Double] = [:]
    /// Something was counted since the last write.
    private var isDirty = false
    private var timer: (any DispatchSourceTimer)?
    private var watcher: (@MainActor @Sendable (AppEnergyLedger) -> Void)?

    init(url: URL? = AppEnergyRecorder.defaultURL, now: @escaping @Sendable () -> Date = Date.init,
         read: @escaping @Sendable () -> [ProcessEnergyReading] = AppEnergySweep.readAll,
         resolve: @escaping @Sendable (pid_t) -> (key: String, app: AppEnergyApp) = {
             AppAttribution.app(forPath: AppAttribution.path(of: AppAttribution.responsible(for: $0)) ?? AppAttribution.path(of: $0))
         }) {
        self.url = url
        self.now = now
        self.read = read
        self.resolve = resolve
    }

    /// Every real power reading (`PowerMonitor.onRealReading`): unplugging starts the sweeps from a
    /// baseline, each percent lost on battery is shared out, plugging in stops them.
    func power(onBattery value: Bool, level newLevel: Int) {
        queue.async { [self] in
            loadIfNeeded()
            if value != onBattery {
                if value {
                    onBattery = true
                    sweep(counting: false)
                    level = newLevel
                    pending.removeAll()
                    startTimer()
                } else {
                    // A part of a percent used since the last drop is not one Daily Usage counts.
                    onBattery = false
                    stopTimer()
                    seen.removeAll()
                    lastSweep = nil
                    level = nil
                    pending.removeAll()
                    save()
                }
                return
            }
            guard onBattery, let last = level, newLevel != last else { return }
            if newLevel < last {
                sweep(counting: true)
                let today = Calendar.autoupdatingCurrent.startOfDay(for: now())
                ledger.add(AppEnergyLedger.share(Double(last - newLevel), by: pending), apps: found.merging(
                    [AppAttribution.systemKey: AppAttribution.system]) { a, _ in a }, on: today)
                ledger.prune(before: today.addingTimeInterval(-AppEnergyLedger.retention))
                pending.removeAll()
                isDirty = true
                save()
                deliver()
            }
            level = newLevel
        }
    }

    /// Hands the ledger to `watcher` on the main thread now (after a sweep, if on battery and the
    /// last one is a minute old) and after every sweep until `unwatch()`.
    func watch(_ watcher: @escaping @MainActor @Sendable (AppEnergyLedger) -> Void) {
        queue.async { [self] in
            loadIfNeeded()
            self.watcher = watcher
            deliver()
        }
    }

    func unwatch() {
        queue.async { [self] in watcher = nil }
    }

    /// Writes what is counted, synchronously: the app is quitting.
    func stop() {
        queue.sync {
            stopTimer()
            save()
        }
    }

    /// Waits for what is queued (tests).
    func drain() { queue.sync {} }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .seconds(30))
        // Between drops: so a process that ends before the next one is counted up to here.
        timer.setEventHandler { [weak self] in self?.sweep(counting: true) }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func sweep(counting: Bool) {
        let resolve = self.resolve
        var found = self.found
        let readings = read()
        let result = AppEnergySweep.step(seen: seen, readings: readings, lastSweep: lastSweep) { pid in
            let owner = resolve(pid)
            found[owner.key] = owner.app
            return owner.key
        }
        seen = result.seen
        lastSweep = mach_absolute_time()
        if counting { pending.merge(result.joules, uniquingKeysWith: +) }
        // The apps still running are remembered between sweeps, and those that used energy since
        // the last drop (named at the next one, ended or not).
        let running = Set(result.seen.values.map(\.key))
        self.found = found.filter { running.contains($0.key) || pending[$0.key] != nil }
    }

    private func deliver() {
        guard let watcher else { return }
        let ledger = ledger
        DispatchQueue.main.async { MainActor.assumeIsolated { watcher(ledger) } }
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let url, let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(AppEnergyLedger.self, from: data) else { return }
        ledger = saved
    }

    private func save() {
        guard isDirty, let url, let data = try? JSONEncoder().encode(ledger) else { return }
        isDirty = false
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
