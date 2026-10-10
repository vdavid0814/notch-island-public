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

/// The chip's temperature, read every two seconds while a widget shows it (Chip Temperature, Fan
/// Control); nothing is read otherwise.
@Observable final class ThermalMonitor {
    private(set) var chip: ChipReading?

    static let interval: TimeInterval = 2

    @ObservationIgnored private var observers = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isReading = false

    func startObserving() {
        observers += 1
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = Self.interval / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopObserving() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        guard !isReading else { return }
        isReading = true
        Task {
            // The first read walks the SMC's keys (`ChipSensors.coreKeys`): never on the main thread.
            let reading = await Task.detached(priority: .utility) { ChipSensors.read() }.value
            isReading = false
            // A whole degree's change redraws; tenths would redraw every sample for nothing.
            if let reading, let chip, abs(reading.average - chip.average) < 0.5, abs(reading.hottest - chip.hottest) < 0.5 { return }
            chip = reading
        }
    }
}
