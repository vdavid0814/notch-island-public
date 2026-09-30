import Foundation

/// One entry of the battery history: 8 bytes on disk, so 8 days of a busy battery (~150 changes a
/// day plus the sleep and display markers) stay near 10 KB.
nonisolated struct BatteryRecord: Sendable, Equatable {
    nonisolated struct Flags: OptionSet, Sendable, Hashable {
        let rawValue: UInt8
        static let charging = Flags(rawValue: 1 << 0)
        static let pluggedIn = Flags(rawValue: 1 << 1)
        static let lowPower = Flags(rawValue: 1 << 2)
        /// Nothing is known between the record before this one and this one (the Mac slept, or the
        /// app was not running, for more than `BatteryHistory.gapThreshold`): a chart must not
        /// join the two.
        static let gapBefore = Flags(rawValue: 1 << 3)
    }

    nonisolated enum Kind: UInt8, Sendable {
        /// The level or the plug/charging state changed.
        case sample = 0
        case systemSleep = 1
        case systemWake = 2
        case displayOff = 3
        case displayOn = 4
        /// The first reading of a launch.
        case appStart = 5
        /// The app quit: the last sign of life before a relaunch.
        case appQuit = 6

        /// Its level is a reading taken at its time. A marker carries the last reading before it,
        /// which after a wake is the level from before the sleep.
        var carriesLevel: Bool { self == .sample || self == .appStart }
    }

    static let size = 8

    /// UTC seconds since 1970.
    var time: UInt32
    /// 0...100.
    var level: UInt8
    var flags: Flags
    var kind: Kind

    var date: Date { Date(timeIntervalSince1970: TimeInterval(time)) }
    var isCharging: Bool { flags.contains(.charging) }

    init(time: UInt32, level: UInt8, flags: Flags = [], kind: Kind = .sample) {
        self.time = time
        self.level = level
        self.flags = flags
        self.kind = kind
    }

    init(date: Date, state: PowerState, kind: Kind) {
        var flags: Flags = []
        if state.isCharging { flags.insert(.charging) }
        if state.isPluggedIn { flags.insert(.pluggedIn) }
        if state.isLowPowerMode { flags.insert(.lowPower) }
        self.init(time: UInt32(clamping: Int(date.timeIntervalSince1970)), level: UInt8(clamping: state.level),
                  flags: flags, kind: kind)
    }

    /// Little-endian time, level, flags, kind and one spare byte.
    var bytes: [UInt8] {
        [UInt8(truncatingIfNeeded: time), UInt8(truncatingIfNeeded: time >> 8),
         UInt8(truncatingIfNeeded: time >> 16), UInt8(truncatingIfNeeded: time >> 24),
         level, flags.rawValue, kind.rawValue, 0]
    }

    /// Nil for a kind this build does not know (written by a newer one).
    init?<Bytes: RandomAccessCollection>(bytes: Bytes) where Bytes.Element == UInt8, Bytes.Index == Int {
        guard bytes.count >= Self.size, let kind = Kind(rawValue: bytes[bytes.startIndex + 6]) else { return nil }
        let base = bytes.startIndex
        time = UInt32(bytes[base]) | UInt32(bytes[base + 1]) << 8 | UInt32(bytes[base + 2]) << 16 | UInt32(bytes[base + 3]) << 24
        level = bytes[base + 4]
        flags = Flags(rawValue: bytes[base + 5])
        self.kind = kind
    }
}

/// When the battery last stopped charging, and at what level (iPhone's "Last charged to 80%").
nonisolated struct BatteryLastCharge: Sendable, Equatable {
    var level: Int
    var date: Date
}

/// The history file: `Application Support/NotchIsland/battery-history.bin`, append-only records.
///
/// Plain file functions, called on `BatteryRecorder`'s I/O queue, never on the main thread.
nonisolated enum BatteryHistory {
    static let retention: TimeInterval = 8 * 86_400
    /// A sleep or a relaunch longer than this breaks the chart's line.
    static let gapThreshold: TimeInterval = 600
    /// Compaction rewrites the file only once its oldest record is this old, so a launch rewrites
    /// it at most about once a day and most launches only read 16 bytes.
    static let compactionAge: TimeInterval = 9 * 86_400

    static var defaultURL: URL? {
        DiagnosticsCenter.supportFolder?.appendingPathComponent("battery-history.bin")
    }

    /// Every whole record. A tail cut short (the app killed mid-write) is ignored.
    static func read(_ url: URL) -> [BatteryRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return decode(data)
    }

    static func decode(_ data: Data) -> [BatteryRecord] {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count - bytes.count % BatteryRecord.size, by: BatteryRecord.size).compactMap {
            BatteryRecord(bytes: bytes[$0 ..< $0 + BatteryRecord.size])
        }
    }

    /// The last whole record, read without loading the file.
    static func tail(_ url: URL) -> BatteryRecord? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= UInt64(BatteryRecord.size) else { return nil }
        let whole = size - size % UInt64(BatteryRecord.size)
        try? handle.seek(toOffset: whole - UInt64(BatteryRecord.size))
        guard let data = try? handle.read(upToCount: BatteryRecord.size) else { return nil }
        return BatteryRecord(bytes: [UInt8](data))
    }

    static func append(_ records: [BatteryRecord], to url: URL) {
        guard !records.isEmpty else { return }
        let data = Data(records.flatMap(\.bytes))
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
                return
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            Log.power.error("battery history write failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Run once at launch, before anything is appended: cuts a torn tail off (records appended
    /// after it would all be misaligned) and, once the oldest record is older than
    /// `compactionAge`, rewrites the file atomically with the last `retention` only.
    static func prepare(_ url: URL, now: Date) {
        guard let handle = try? FileHandle(forUpdating: url) else { return }
        guard let size = try? handle.seekToEnd() else { try? handle.close(); return }
        let whole = size - size % UInt64(BatteryRecord.size)
        if whole != size { try? handle.truncate(atOffset: whole) }
        try? handle.seek(toOffset: 0)
        let head = (try? handle.read(upToCount: BatteryRecord.size)).flatMap { BatteryRecord(bytes: [UInt8]($0)) }
        try? handle.close()
        guard let head, head.date < now.addingTimeInterval(-compactionAge) else { return }
        let kept = read(url).filter { $0.date >= now.addingTimeInterval(-retention) }
        do {
            try Data(kept.flatMap(\.bytes)).write(to: url, options: .atomic)
            Log.power.notice("battery history compacted to \(kept.count, privacy: .public) records")
        } catch {
            Log.power.error("battery history compaction failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The last charging → not charging edge among the readings.
    static func lastCharge(in records: [BatteryRecord]) -> BatteryLastCharge? {
        var after: BatteryRecord?
        for record in records.reversed() where record.kind.carriesLevel {
            if record.isCharging, let after, !after.isCharging {
                return BatteryLastCharge(level: Int(after.level), date: after.date)
            }
            after = record
        }
        return nil
    }
}

/// Writes the battery history as the Mac lives it: a reading whenever the level or the plug and
/// charging state change, and markers for sleep, wake and the displays going off and on.
///
/// It adds no wakeups of its own: readings arrive with `PowerMonitor`'s IOKit callbacks and markers
/// with `SystemActivity`'s notifications, and on the main thread a record is only appended to a
/// buffer. The buffer goes to disk on the I/O queue at 12 records, before the Mac sleeps, at quit,
/// or 30 minutes after the first record waiting, whichever comes first; the timer exists only while
/// records wait.
final class BatteryRecorder {
    static let flushCount = 12
    static let flushDelay: Duration = .seconds(1800)

    /// Every record, as it is appended (the history snapshot follows along once it is loaded).
    var onAppend: ((BatteryRecord) -> Void)?

    /// Records waiting for the next write.
    private(set) var pending: [BatteryRecord] = []

    /// File work, in order: preparing, writes and snapshot loads never overlap.
    let queue = DispatchQueue(label: "com.davidvarga.notchisland.battery", qos: .utility)
    private let url: URL?
    private let now: () -> Date
    /// The last reading, for the markers' flags.
    private var last: PowerState?
    /// Records made before the file's last record is known: the launch's gap depends on it.
    private var waiting: [BatteryRecord] = []
    private var isReady = false
    private var hasStarted = false
    /// The sleep marker's time until the Mac is seen awake again (its wake marker or a reading,
    /// whichever arrives first: IOKit's callback and the workspace notification race at a wake).
    private var sleptAt: Date?
    /// Set by a long sleep: the next reading is recorded even if nothing changed, flagged as a gap.
    private var gapNext = false
    private var flushTask: Task<Void, Never>?

    init(url: URL? = BatteryHistory.defaultURL, now: @escaping () -> Date = Date.init) {
        self.url = url
        self.now = now
    }

    /// Prepares the file and reads its last record, both on the I/O queue. Idempotent.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard let url else { return ready(tail: nil) }
        let date = now()
        queue.async {
            BatteryHistory.prepare(url, now: date)
            let tail = BatteryHistory.tail(url)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.ready(tail: tail) } }
        }
    }

    /// Records the quit, so a relaunch soon after a quiet run is no gap (a crash still is), and
    /// writes what waits, synchronously: the process is about to exit.
    func stop() {
        if !isReady { ready(tail: nil) }
        if let last { commit(BatteryRecord(date: now(), state: last, kind: .appQuit)) }
        flush()
        queue.sync {}
    }

    /// `PowerMonitor.onRealReading`: a real IOKit reading (never a demo state). Readings that only
    /// change the minutes remaining are not recorded.
    func powerReading(from old: PowerState, to new: PowerState) {
        guard new.hasBattery else { return }
        let isFirst = last == nil
        last = new
        let date = now()
        if isFirst { return append(BatteryRecord(date: date, state: new, kind: .appStart)) }
        // A reading long after the sleep marker but before the wake marker is the first after the
        // wake. One soon after the marker may still come before the Mac actually sleeps.
        if let sleptAt, date.timeIntervalSince(sleptAt) > BatteryHistory.gapThreshold {
            gapNext = true
            self.sleptAt = nil
        }
        let changed = new.level != old.level || new.isCharging != old.isCharging || new.isPluggedIn != old.isPluggedIn
        guard changed || gapNext else { return }
        var record = BatteryRecord(date: date, state: new, kind: .sample)
        if gapNext { record.flags.insert(.gapBefore) }
        gapNext = false
        append(record)
    }

    /// `SystemActivity.onEdge`.
    func activityEdge(_ edge: ActivitySignals.Edge) {
        let kind: BatteryRecord.Kind
        switch edge {
        case .systemWillSleep: kind = .systemSleep
        case .systemDidWake: kind = .systemWake
        case .screensDidSleep: kind = .displayOff
        case .screensDidWake: kind = .displayOn
        case .sessionDidResignActive, .sessionDidBecomeActive, .screenLocked, .screenUnlocked: return
        }
        guard let last else { return }
        let date = now()
        switch kind {
        case .systemSleep:
            sleptAt = date
        case .systemWake:
            if let sleptAt, date.timeIntervalSince(sleptAt) > BatteryHistory.gapThreshold { gapNext = true }
            sleptAt = nil
        default:
            break
        }
        append(BatteryRecord(date: date, state: last, kind: kind))
        // The Mac may not come back before the app is quit or the battery runs out.
        if kind == .systemSleep { flush() }
    }

    /// Loads the history the recorder has written, on the I/O queue after every write already
    /// queued, and completes on the main thread with it plus what waits for a write; `onAppend`
    /// delivers everything after, the records held until the file's last record is known too.
    func loadHistory(_ completion: @escaping @MainActor @Sendable ([BatteryRecord]) -> Void) {
        let unwritten = pending
        guard let url else { return completion(unwritten) }
        let cutoff = now().addingTimeInterval(-BatteryHistory.retention)
        queue.async {
            let written = BatteryHistory.read(url).filter { $0.date >= cutoff }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(written + unwritten) } }
        }
    }

    private func ready(tail: BatteryRecord?) {
        isReady = true
        var held = waiting
        waiting.removeAll()
        if let tail, let first = held.first, first.kind == .appStart,
           first.date.timeIntervalSince(tail.date) > BatteryHistory.gapThreshold {
            held[0].flags.insert(.gapBefore)
        }
        held.forEach(commit)
    }

    private func append(_ record: BatteryRecord) {
        guard isReady else { return waiting.append(record) }
        commit(record)
    }

    private func commit(_ record: BatteryRecord) {
        pending.append(record)
        onAppend?(record)
        if pending.count >= Self.flushCount {
            flush()
        } else if flushTask == nil {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: Self.flushDelay, tolerance: .seconds(300))
                guard !Task.isCancelled else { return }
                self?.flush()
            }
        }
    }

    private func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll()
        guard let url else { return }
        queue.async { BatteryHistory.append(batch, to: url) }
    }
}

// MARK: - Demo

nonisolated extension BatteryHistory {
    /// `demo/batteryhistory`: a made-up weekday from yesterday's midnight up to `now`, as the recorder
    /// would have written it (never written to the file). Each day: the displays off at 00:30, asleep
    /// 00:40–07:10, on battery to 38 % at 09:30, charged to 80 % by 10:40 and held there until noon,
    /// the displays off over lunch, down to 16 % by 17:00, charged to full by 18:30, unplugged at 19:00.
    static func demoRecords(now: Date, calendar: Calendar) -> [BatteryRecord] {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return [] }
        let sleep = 40...430
        /// Minutes into the day, the level there, and the power state from there to the next stop.
        let stops: [(minute: Int, level: Int, state: DemoPower)] = [
            (0, 71, .battery), (sleep.lowerBound - 1, 69, .battery), (sleep.upperBound + 1, 66, .battery),
            (570, 38, .charging), (640, 80, .held), (720, 80, .battery), (1020, 16, .charging), (1110, 100, .held),
            (1140, 100, .battery), (1440, 71, .battery),
        ]
        let markers: [(minute: Int, kind: BatteryRecord.Kind)] = [
            (30, .displayOff), (sleep.lowerBound, .systemSleep), (sleep.upperBound, .systemWake),
            (sleep.upperBound, .displayOn), (760, .displayOff), (800, .displayOn),
        ]
        var records: [BatteryRecord] = []
        for day in [yesterday, calendar.date(byAdding: .day, value: 1, to: yesterday) ?? now] {
            var pending = markers[...]
            func append(_ minute: Double, _ level: Int, _ flags: BatteryRecord.Flags, _ kind: BatteryRecord.Kind) {
                let date = day.addingTimeInterval(minute * 60)
                guard date <= now else { return }
                records.append(BatteryRecord(time: UInt32(date.timeIntervalSince1970), level: UInt8(level), flags: flags,
                                             kind: records.isEmpty ? .appStart : kind))
            }
            func add(_ minute: Double, level: Int, state: DemoPower, gap: Bool = false) {
                // The markers up to here first, in order.
                while let marker = pending.first, Double(marker.minute) <= minute {
                    pending.removeFirst()
                    append(Double(marker.minute), level, state.flags, marker.kind)
                }
                append(minute, level, gap ? state.flags.union(.gapBefore) : state.flags, .sample)
            }
            for (stop, next) in zip(stops, stops.dropFirst()) {
                add(Double(stop.minute), level: stop.level, state: stop.state, gap: stop.minute == sleep.upperBound + 1)
                // Asleep: nothing is read until the wake.
                guard stop.minute >= sleep.upperBound || next.minute <= sleep.lowerBound else { continue }
                // A reading each time the level moves on to the next whole percent.
                let span = next.level - stop.level
                for step in stride(from: 1, to: abs(span), by: 1) {
                    let minute = Double(stop.minute) + Double(next.minute - stop.minute) * Double(step) / Double(abs(span))
                    add(minute, level: stop.level + span.signum() * step, state: stop.state)
                }
            }
        }
        return records
    }

    private enum DemoPower {
        case battery, charging, held

        var flags: BatteryRecord.Flags {
            switch self {
            case .battery: []
            case .charging: [.charging, .pluggedIn]
            case .held: [.pluggedIn]
            }
        }
    }
}
