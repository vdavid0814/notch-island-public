import Foundation
import Observation

/// The battery history as far as it is loaded, and a version that changes with every record.
nonisolated struct BatteryHistorySnapshot: Sendable, Equatable {
    var records: [BatteryRecord] = []
    var version = 0
}

/// What the battery page and widgets read: the details, the history and the chart shapes.
///
/// Records are written from launch on (`BatteryRecorder`). Everything else happens only while
/// someone holds a lease, like `AudioSpectrumTap`: the details are read when the first `.details`
/// lease arrives, unless nothing has changed since the last read (the battery page shown again),
/// and again after a power change (at most every 30 s), never on a timer; the
/// history is loaded from disk once, by the first `.history` lease, and then kept current from
/// memory (it is about 10 KB, and a page opening again should not read the file again).
@Observable final class BatteryCenter {
    nonisolated enum Lease: Sendable {
        case details, history
        /// The details, read again every `powerInterval` while held: the watts flowing change
        /// without any power event (the Power widget, only while it is shown).
        case power
    }

    /// Nil until a `.details` lease has been served, and on a desktop Mac.
    private(set) var details: BatteryDetails?
    /// Nil until a `.history` lease has loaded it.
    private(set) var history: BatteryHistorySnapshot?
    /// Known once the history is loaded.
    private(set) var lastCharge: BatteryLastCharge?
    /// The day picked on Daily Usage (its midnight): the chart and Screen Activity show it too.
    /// Nil: today.
    var selectedDay: Date?
    @ObservationIgnored private var usageCache: (version: Int, today: Date, days: [BatteryUsageDay])?

    static let detailsInterval: TimeInterval = 30
    static let powerInterval: TimeInterval = 5
    @ObservationIgnored private var powerHolders = 0
    @ObservationIgnored private var powerTask: Task<Void, Never>?

    @ObservationIgnored let recorder: BatteryRecorder
    @ObservationIgnored private let detailsSource: @Sendable (PowerState) -> BatteryDetails?
    @ObservationIgnored private weak var power: PowerMonitor?
    /// `demo/batteryhistory` owns the history and the details: real ones wait until it ends.
    @ObservationIgnored private var isDemo = false
    @ObservationIgnored private var detailHolders = 0
    @ObservationIgnored private var detailsReadAt: Date?
    /// A power change came since the last read (or none was made): the next lease reads again.
    @ObservationIgnored private var detailsAreStale = true
    @ObservationIgnored private var detailsTask: Task<Void, Never>?
    @ObservationIgnored private var isLoadingHistory = false
    /// Records appended while the history loads, added after it.
    @ObservationIgnored private var arrivedWhileLoading: [BatteryRecord] = []

    private var charts: [ChartKey: ChartEntry] = [:]
    @ObservationIgnored private var building: Set<ChartKey> = []

    /// - Parameter detailsSource: the details' read; tests count them. Defaults to IOKit's.
    init(recorder: BatteryRecorder = BatteryRecorder(),
         detailsSource: @escaping @Sendable (PowerState) -> BatteryDetails? = BatteryDetails.read) {
        self.recorder = recorder
        self.detailsSource = detailsSource
    }

    /// Hooks the recorder to the power readings and the sleep, wake and display edges. Call before
    /// `power.start()`, so the launch's first reading is recorded.
    func start(power: PowerMonitor, activity: SystemActivity) {
        self.power = power
        power.onRealReading = { [weak self] old, new in
            self?.recorder.powerReading(from: old, to: new)
            self?.powerChanged()
        }
        activity.onEdge = { [weak self] edge in self?.recorder.activityEdge(edge) }
        recorder.onAppend = { [weak self] record in self?.appended(record) }
        recorder.start()
    }

    /// Writes what the recorder holds before the app exits.
    func stop() {
        detailsTask?.cancel()
        detailsTask = nil
        powerTask?.cancel()
        powerTask = nil
        recorder.stop()
    }

    func acquire(_ lease: Lease) {
        switch lease {
        case .details:
            detailHolders += 1
            if detailHolders == 1, detailsAreStale { readDetails() }
        case .history:
            if history == nil { loadHistory() }
        case .power:
            acquire(.details)
            powerHolders += 1
            guard powerTask == nil else { return }
            powerTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Self.powerInterval), tolerance: .seconds(1))
                    guard !Task.isCancelled, let self, self.powerHolders > 0 else { return }
                    self.readDetails()
                }
            }
        }
    }

    func release(_ lease: Lease) {
        switch lease {
        case .details:
            detailHolders = max(detailHolders - 1, 0)
            if detailHolders == 0 {
                detailsTask?.cancel()
                detailsTask = nil
            }
        case .history:
            break   // The history stays loaded (see the type's comment).
        case .power:
            powerHolders = max(powerHolders - 1, 0)
            if powerHolders == 0 {
                powerTask?.cancel()
                powerTask = nil
            }
            release(.details)
        }
    }

    /// Demo / screenshot hook: shows `records` and `details` as the history and the details until
    /// `injectDemo(nil)`, which loads the real ones again. Nothing of it reaches the file, and the
    /// recorder goes on writing the real readings meanwhile.
    func injectDemo(_ demo: (records: [BatteryRecord], details: BatteryDetails)?) {
        guard let demo else {
            guard isDemo else { return }
            isDemo = false
            history = nil
            lastCharge = nil
            details = nil
            detailsAreStale = true
            charts.removeAll()
            loadHistory()
            if detailHolders > 0 { readDetails() }
            return
        }
        isDemo = true
        history = BatteryHistorySnapshot(records: demo.records, version: (history?.version ?? 0) + 1)
        lastCharge = BatteryHistory.lastCharge(in: demo.records)
        details = demo.details
    }

    // MARK: Details

    private func powerChanged() {
        detailsAreStale = true
        guard detailHolders > 0 else { return }
        let wait = detailsReadAt.map { Self.detailsInterval - Date().timeIntervalSince($0) } ?? 0
        guard wait > 0 else { return readDetails() }
        guard detailsTask == nil else { return }
        detailsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.detailsTask = nil
            self.readDetails()
        }
    }

    private func readDetails() {
        detailsReadAt = Date()
        detailsAreStale = false
        let state = power?.state ?? .unknown
        let source = detailsSource
        Task.detached(priority: .utility) { [weak self] in
            let next = source(state)
            await self?.receive(next)
        }
    }

    private func receive(_ next: BatteryDetails?) {
        // Dropped when nobody waits for it any more (or a demo shows its own): read again next time.
        guard detailHolders > 0, !isDemo else { return detailsAreStale = true }
        if next != details { details = next }
    }

    // MARK: History

    private func loadHistory() {
        guard !isLoadingHistory else { return }
        isLoadingHistory = true
        recorder.loadHistory { [weak self] records in
            guard let self else { return }
            self.isLoadingHistory = false
            let all = records + self.arrivedWhileLoading
            self.arrivedWhileLoading.removeAll()
            guard !self.isDemo else { return }
            self.history = BatteryHistorySnapshot(records: all, version: 1)
            self.lastCharge = BatteryHistory.lastCharge(in: all)
        }
    }

    private func appended(_ record: BatteryRecord) {
        if isLoadingHistory { return arrivedWhileLoading.append(record) }
        guard !isDemo, var snapshot = history else { return }
        snapshot.records.append(record)
        snapshot.version += 1
        history = snapshot
        if record.kind.carriesLevel {
            let charge = BatteryHistory.lastCharge(in: snapshot.records)
            if charge != lastCharge { lastCharge = charge }
        }
    }

    // MARK: Chart

    /// The last eight days' use, oldest first, for this history (built when it changes or the day
    /// turns). Needs a `.history` lease; empty before the history is loaded.
    func usageDays(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> [BatteryUsageDay] {
        guard let history else { return [] }
        let today = calendar.startOfDay(for: now)
        // The current day's screen time grows with the clock: kept for a minute at most.
        if let cache = usageCache, cache.version == history.version, cache.today == today,
           now.timeIntervalSince(cachedAt) < 60 {
            return cache.days
        }
        let days = BatteryUsage.days(records: history.records, now: now, calendar: calendar)
        usageCache = (history.version, today, days)
        cachedAt = now
        return days
    }

    @ObservationIgnored private var cachedAt = Date.distantPast

    /// The picked day, if it is one of the eight still in the history; nil for today.
    func pickedDay(calendar: Calendar = .autoupdatingCurrent, now: Date = Date()) -> Date? {
        guard let selectedDay else { return nil }
        let today = calendar.startOfDay(for: now)
        guard selectedDay < today, selectedDay >= today.addingTimeInterval(-BatteryHistory.retention) else { return nil }
        return selectedDay
    }

    private nonisolated struct ChartKey: Hashable, Sendable {
        var range: BatteryChartRange
        var day: Date?
        var style: BatteryChartStyle
        var width: Double
        var height: Double
    }

    private nonisolated struct ChartEntry: Sendable {
        var version: Int
        /// The range's bucket `now` fell in: a new one slides the window.
        var bucket: Int
        var geometry: BatteryChartGeometry
    }

    /// The chart's shapes for this history version, size, range and style; read from a view's
    /// body. A missing or stale one is built off the main thread and published when ready,
    /// meanwhile the previous one (or nil) is returned. Needs a `.history` lease.
    /// `day`: a past day's midnight to show instead of the range (Daily Usage's pick).
    func chartGeometry(range: BatteryChartRange, style: BatteryChartStyle, size: CGSize, day: Date? = nil) -> BatteryChartGeometry? {
        let key = ChartKey(range: range, day: day, style: style, width: size.width, height: size.height)
        let entry = charts[key]
        guard let history, size.width > 0, size.height > 0 else { return entry?.geometry }
        let now = Date()
        let bucket = Int(now.timeIntervalSinceReferenceDate / range.bucketSeconds)
        if entry?.version != history.version || entry?.bucket != bucket, !building.contains(key) {
            building.insert(key)
            let calendar = Calendar.autoupdatingCurrent
            Task.detached(priority: .userInitiated) { [weak self] in
                let interval = day.map { calendar.dateInterval(of: .day, for: $0) ?? DateInterval(start: $0, duration: 86_400) }
                let model = BatteryChartModel(records: history.records, range: day == nil ? range : .today, now: now,
                                              calendar: calendar, interval: interval)
                let geometry = BatteryChartGeometry(model: model, style: style, size: size)
                await self?.store(ChartEntry(version: history.version, bucket: bucket, geometry: geometry), for: key)
            }
        }
        return entry?.geometry
    }

    private func store(_ entry: ChartEntry, for key: ChartKey) {
        building.remove(key)
        // Shapes of an older history are only kept while their own replacement is on its way; a
        // build that finishes after the history moved on must not evict newer ones.
        let current = history?.version ?? entry.version
        charts = charts.filter { $0.value.version == current || building.contains($0.key) }
        charts[key] = entry
    }
}
