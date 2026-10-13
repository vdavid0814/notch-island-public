import Foundation

/// How warm the chip runs: its cores' sensors, averaged, and the hottest of them.
nonisolated struct ChipReading: Sendable, Equatable {
    var average: Double
    var hottest: Double
}

/// The chip's temperature sensors, read from the SMC (`SMC`). Apple silicon names its cores'
/// sensors by a prefix — "Tp" the performance cores, "Te" the efficiency cores, "Tf" more of them on
/// some chips — and a code that differs from chip to chip, so the keys are found once by walking all
/// of the SMC's keys (about 2 500, a few milliseconds) and only those are read after.
nonisolated enum ChipSensors {
    private static let prefixes = ["Tp", "Te", "Tf"]

    /// The cores' keys this Mac has; empty where it has none (or no SMC).
    static let coreKeys: [String] = discover()

    /// The Mac has sensors to read: the gallery offers Chip Temperature.
    static var isAvailable: Bool { !coreKeys.isEmpty }

    /// "Apple M5".
    static let name: String = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "Apple silicon" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "Apple silicon" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }()

    /// "M5" of "Apple M5".
    static func shortName(_ name: String) -> String {
        name.hasPrefix("Apple ") ? String(name.dropFirst(6)) : name
    }

    /// The cores now. Touches the SMC: off the main thread.
    static func read() -> ChipReading? {
        guard let smc = SMC.shared else { return nil }
        let values = coreKeys.compactMap { smc.number($0) }.filter(isPlausible)
        guard let hottest = values.max() else { return nil }
        return ChipReading(average: values.reduce(0, +) / Double(values.count), hottest: hottest)
    }

    /// A sensor that reads something a working chip could be at (a sensor switched off reads 0, a
    /// few read nonsense).
    static func isPlausible(_ celsius: Double) -> Bool { (5...130).contains(celsius) }

    private static func discover() -> [String] {
        guard let smc = SMC.shared else { return [] }
        return (0..<smc.keyCount).compactMap { index -> String? in
            guard let key = smc.key(at: index), prefixes.contains(where: key.hasPrefix),
                  let value = smc.read(key), value.type == "flt ", let celsius = SMC.decode(value), isPlausible(celsius) else { return nil }
            return key
        }
    }
}

/// One reading of a series, at its time.
nonisolated struct SensorSample: Sendable, Equatable {
    var date: Date
    var value: Double
    /// The fans' speed only: how far their strokes had run by this reading (`FanRhythm`), so each
    /// stroke keeps its moment however the history is cut.
    var phase: Double = 0
}

/// The fans' speed as a rhythm (Fan Control's graph): a row of strokes, far apart while they turn
/// slowly, close together while they turn fast. A stroke is stamped at its moment and slides left
/// with time; the spacing never reshuffles, as it is counted from the readings themselves.
nonisolated enum FanRhythm {
    /// From one stroke to the next, a share of the graph's width: about a thirteenth at a crawl, a
    /// forty-fifth at the fans' fastest.
    static func share(_ fraction: Double) -> Double {
        (48 - 34 * min(max(fraction, 0), 1)) / 636
    }

    /// Readings further apart than this (the Mac asleep, the history not kept) are a gap: the line
    /// breaks there and no strokes are drawn across it.
    static let gap: TimeInterval = 45

    /// How far the strokes run in `seconds` at `rpm`: a graph `window` seconds wide draws one every
    /// `window` of it.
    static func advance(rpm: Double, maximum: Double, seconds: TimeInterval) -> Double {
        guard rpm > 0, seconds > 0, seconds <= gap else { return 0 }
        return seconds / share(rpm / max(maximum, 1))
    }

    /// The strokes' moments in a graph `window` seconds wide: wherever the run passes a whole
    /// `window`, oldest first.
    static func strokes(_ speeds: [SensorSample], window: TimeInterval, after start: Date) -> [Date] {
        guard window > 0 else { return [] }
        var strokes: [Date] = []
        for (before, after) in zip(speeds, speeds.dropFirst()) where after.date > start && after.phase > before.phase {
            var next = (before.phase / window).rounded(.down) + 1
            while next * window <= after.phase {
                let share = (next * window - before.phase) / (after.phase - before.phase)
                let date = before.date.addingTimeInterval(after.date.timeIntervalSince(before.date) * share)
                if date > start { strokes.append(date) }
                next += 1
            }
        }
        return strokes
    }
}

/// The chip's temperature, read every second while a widget shows it (Chip Temperature, Fan
/// Control); nothing is read otherwise. Fan Control's graph keeps the last ten minutes of it and of
/// the fans' speed: every reading while shown, and — once Fan Control is on a board — one every
/// fifteen seconds while not (`keepHistory`), so the graph has a past when the panel opens.
@Observable final class ThermalMonitor {
    private(set) var chip: ChipReading?
    /// The cores' average over the last ten minutes, oldest first.
    private(set) var temperatures: [SensorSample] = []
    /// The fans' average speed over the last ten minutes, oldest first, with their strokes' run.
    private(set) var speeds: [SensorSample] = []

    /// While shown: every second, so a minute's graph has sixty readings.
    static let interval: TimeInterval = 1
    static let historyInterval: TimeInterval = 15
    /// How far back the history reaches: the longest a graph is set to show (`WidgetConfig.secondsRange`).
    nonisolated static let window: TimeInterval = 600

    @ObservationIgnored private var observers = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var historyTimer: Timer?
    @ObservationIgnored private var isReading = false

    func startObserving() {
        observers += 1
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = Self.interval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopObserving() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    /// Keeps the graphs' past from now on: a reading of the chip and the fans every fifteen seconds
    /// (skipped while a widget reads them more often).
    func keepHistory() {
        guard historyTimer == nil else { return }
        let timer = Timer(timeInterval: Self.historyInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleHistory() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        historyTimer = timer
        sampleHistory()
    }

    /// The fans' average speed, as Fan Control read it, and their fastest (for the strokes' run).
    func record(speed rpm: Double, maximum: Double) {
        let now = Date.now
        let phase = speeds.last.map { $0.phase + FanRhythm.advance(rpm: $0.value, maximum: maximum, seconds: now.timeIntervalSince($0.date)) } ?? 0
        Self.append(SensorSample(date: now, value: rpm, phase: phase), to: &speeds)
    }

    private func sampleHistory() {
        guard timer == nil, !isReading else { return }
        isReading = true
        Task {
            let (chip, fans) = await Task.detached(priority: .utility) { (ChipSensors.read(), FanSensors.read()) }.value
            isReading = false
            if let chip { Self.append(SensorSample(date: .now, value: chip.average), to: &temperatures) }
            if !fans.isEmpty { record(speed: fans.map(\.rpm).reduce(0, +) / Double(fans.count), maximum: fans.map(\.maximum).max() ?? 1) }
        }
    }

    private func sample() {
        guard !isReading else { return }
        isReading = true
        Task {
            // The first read walks the SMC's keys (`ChipSensors.coreKeys`): never on the main thread.
            let reading = await Task.detached(priority: .utility) { ChipSensors.read() }.value
            isReading = false
            if let reading { Self.append(SensorSample(date: .now, value: reading.average), to: &temperatures) }
            // A whole degree's change redraws; tenths would redraw every sample for nothing.
            if let reading, let chip, abs(reading.average - chip.average) < 0.5, abs(reading.hottest - chip.hottest) < 0.5 { return }
            chip = reading
        }
    }

    /// At most one sample a second (a timer's a little early still counts); older than the window,
    /// dropped.
    private static func append(_ sample: SensorSample, to series: inout [SensorSample]) {
        if let last = series.last, sample.date.timeIntervalSince(last.date) < 0.6 { return }
        let cut = sample.date.addingTimeInterval(-window - 5)
        if let first = series.first, first.date < cut { series.removeAll { $0.date < cut } }
        series.append(sample)
    }
}
