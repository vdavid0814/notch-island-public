import Darwin
import Foundation
import IOKit
import IOKit.ps

/// What a process has used since it started, as the kernel counts it (`proc_pid_rusage`): the same
/// counters Activity Monitor's Energy tab is built from.
nonisolated struct ProcessUsage: Sendable, Codable, Equatable {
    /// Energy in nanojoules (Apple silicon; zero where the kernel does not measure it).
    var energyNJ: UInt64 = 0
    /// CPU time in nanoseconds (user + system).
    var cpuNS: UInt64 = 0
    /// Interrupt and package-idle wakeups: what keeps the CPU from sleeping.
    var wakeups: UInt64 = 0
    var footprint: UInt64 = 0
    var peakFootprint: UInt64 = 0
    var diskWritten: UInt64 = 0

    static func + (a: ProcessUsage, b: ProcessUsage) -> ProcessUsage {
        ProcessUsage(energyNJ: a.energyNJ + b.energyNJ, cpuNS: a.cpuNS + b.cpuNS, wakeups: a.wakeups + b.wakeups,
                     footprint: a.footprint + b.footprint, peakFootprint: a.peakFootprint + b.peakFootprint,
                     diskWritten: a.diskWritten + b.diskWritten)
    }

    /// `ri_user_time` and `ri_system_time` are mach ticks on Apple silicon.
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(max(info.numer, 1)), UInt64(max(info.denom, 1)))
    }()

    static func read(_ pid: pid_t) -> ProcessUsage? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        guard result == 0 else { return nil }
        let ticks = info.ri_user_time + info.ri_system_time
        return ProcessUsage(
            energyNJ: info.ri_energy_nj,
            cpuNS: ticks * timebase.numer / timebase.denom,
            wakeups: info.ri_interrupt_wkups + info.ri_pkg_idle_wkups,
            footprint: info.ri_phys_footprint,
            peakFootprint: info.ri_lifetime_max_phys_footprint,
            diskWritten: info.ri_diskio_byteswritten
        )
    }

    /// The processes NotchIsland started (the MediaRemote adapter and its perl host).
    static func children(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 64)
        let count = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        // Grandchildren too: the adapter's perl script starts the stream process.
        let direct = Array(buffer.prefix(Int(count)))
        return direct + direct.flatMap { children(of: $0) }
    }
}

/// One reading of NotchIsland's counters and the power situation.
nonisolated struct EnergySample: Sendable, Codable, Equatable {
    var date: Date
    var own: ProcessUsage
    /// The helper processes together.
    var helpers: ProcessUsage
    var onBattery: Bool
    var batteryLevel: Int?
    /// The whole Mac's draw in milliwatts, from the battery gauge (nil on the charger or a desktop).
    var systemMW: Double?

    static func now(onBattery: Bool, batteryLevel: Int?) -> EnergySample {
        let pid = ProcessInfo.processInfo.processIdentifier
        let helpers = ProcessUsage.children(of: pid).compactMap(ProcessUsage.read).reduce(ProcessUsage(), +)
        return EnergySample(date: Date(), own: ProcessUsage.read(pid) ?? ProcessUsage(), helpers: helpers,
                            onBattery: onBattery, batteryLevel: batteryLevel,
                            systemMW: onBattery ? BatteryProbe.systemDrawMW() : nil)
    }
}

/// The use between two samples, as rates.
nonisolated struct EnergyInterval: Sendable, Equatable {
    var start: Date
    var end: Date
    var ownMW: Double
    var helpersMW: Double
    var cpuPercent: Double
    var wakeupsPerSecond: Double
    var onBattery: Bool
    var systemMW: Double?
    /// Battery percent lost per hour (on battery only).
    var drainPerHour: Double?
    var footprintMB: Double

    var seconds: TimeInterval { end.timeIntervalSince(start) }

    init?(from a: EnergySample, to b: EnergySample) {
        let seconds = b.date.timeIntervalSince(a.date)
        // A counter that went back is a restarted helper; its interval says nothing.
        guard seconds >= 1, b.own.energyNJ >= a.own.energyNJ, b.own.cpuNS >= a.own.cpuNS else { return nil }
        start = a.date
        end = b.date
        ownMW = Double(b.own.energyNJ - a.own.energyNJ) / 1e6 / seconds
        let helperEnergy = b.helpers.energyNJ >= a.helpers.energyNJ ? b.helpers.energyNJ - a.helpers.energyNJ : b.helpers.energyNJ
        helpersMW = Double(helperEnergy) / 1e6 / seconds
        cpuPercent = Double(b.own.cpuNS - a.own.cpuNS) / 1e9 / seconds * 100
        wakeupsPerSecond = Double(b.own.wakeups &- a.own.wakeups) / seconds
        // Mixed intervals (plugged in half way) count as on the charger.
        onBattery = a.onBattery && b.onBattery
        systemMW = onBattery ? b.systemMW : nil
        if onBattery, let first = a.batteryLevel, let last = b.batteryLevel {
            drainPerHour = Double(first - last) / seconds * 3600
        } else {
            drainPerHour = nil
        }
        footprintMB = Double(b.own.footprint) / 1_048_576
    }
}

/// Averages over a run of intervals.
nonisolated struct EnergySummary: Sendable, Equatable {
    var seconds: TimeInterval = 0
    var ownMW: Double = 0
    var helpersMW: Double = 0
    var cpuPercent: Double = 0
    var wakeupsPerSecond: Double = 0
    var systemMW: Double?
    var drainPerHour: Double?

    /// Time-weighted, so a short interval counts for what it lasted.
    init?(_ intervals: [EnergyInterval]) {
        let total = intervals.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return nil }
        seconds = total
        func mean(_ value: (EnergyInterval) -> Double) -> Double {
            intervals.reduce(0) { $0 + value($1) * $1.seconds } / total
        }
        ownMW = mean(\.ownMW)
        helpersMW = mean(\.helpersMW)
        cpuPercent = mean(\.cpuPercent)
        wakeupsPerSecond = mean(\.wakeupsPerSecond)
        let withSystem = intervals.filter { $0.systemMW != nil }
        let systemSeconds = withSystem.reduce(0) { $0 + $1.seconds }
        if systemSeconds > 0 {
            systemMW = withSystem.reduce(0) { $0 + ($1.systemMW ?? 0) * $1.seconds } / systemSeconds
        }
        let withDrain = intervals.filter { $0.drainPerHour != nil }
        let drainSeconds = withDrain.reduce(0) { $0 + $1.seconds }
        if drainSeconds > 0 {
            drainPerHour = withDrain.reduce(0) { $0 + ($1.drainPerHour ?? 0) * $1.seconds } / drainSeconds
        }
    }

    var line: String {
        var text = String(format: "%.1f mW (helpers %.1f mW), CPU %.2f%%, %.1f wakeups/s over %@",
                          ownMW, helpersMW, cpuPercent, wakeupsPerSecond, DiagnosticsFormat.duration(seconds))
        if let systemMW {
            text += String(format: "; whole Mac %.2f W (NotchIsland %.1f%% of it)", systemMW / 1000, (ownMW + helpersMW) / systemMW * 100)
        }
        if let drainPerHour { text += String(format: "; battery −%.1f%%/h", drainPerHour) }
        return text
    }
}

/// Keeps a sample every `interval` while diagnostics are on: a counter read, a few microseconds of
/// work, far apart. The last `capacity` samples (12 hours) are kept in memory.
final class EnergyMeter {
    static let interval: Duration = .seconds(600)
    static let capacity = 73

    private(set) var samples: [EnergySample] = []
    /// The sample the process started with (all counters zero at launch).
    let launch: EnergySample
    /// Called after each new sample (the live check against the reference).
    var onSample: ((EnergyInterval) -> Void)?

    private var task: Task<Void, Never>?
    private let powerState: () -> PowerState

    init(launchedAt: Date, powerState: @escaping () -> PowerState) {
        self.powerState = powerState
        launch = EnergySample(date: launchedAt, own: ProcessUsage(), helpers: ProcessUsage(), onBattery: false)
    }

    var isRunning: Bool { task != nil }

    func start() {
        guard task == nil else { return }
        take()
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: Self.interval, tolerance: .seconds(60)) } catch { return }
                self?.take()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    @discardableResult
    func take() -> EnergySample {
        let power = powerState()
        let sample = EnergySample.now(onBattery: power.hasBattery && !power.isPluggedIn,
                                      batteryLevel: power.hasBattery ? power.level : nil)
        if let last = samples.last, let interval = EnergyInterval(from: last, to: sample) {
            samples.append(sample)
            onSample?(interval)
        } else {
            samples.append(sample)
        }
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
        return sample
    }

    var intervals: [EnergyInterval] {
        zip(samples, samples.dropFirst()).compactMap { EnergyInterval(from: $0, to: $1) }
    }
}

/// The battery as its gauge reports it (`AppleSmartBattery` in the I/O Registry).
nonisolated enum BatteryProbe {
    static func properties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return dictionary
    }

    /// The gauge's amperage is a signed 64-bit value stored unsigned.
    static func signed(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return Int(truncatingIfNeeded: number.int64Value) }
        return nil
    }

    /// The whole Mac's draw from the battery, in milliwatts; nil while charging or without a battery.
    static func systemDrawMW(_ properties: [String: Any]? = properties()) -> Double? {
        guard let properties,
              let volts = signed(properties["Voltage"]), let amps = signed(properties["InstantAmperage"] ?? properties["Amperage"]),
              amps < 0 else { return nil }
        return Double(volts) * Double(-amps) / 1000
    }

    static func section() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Battery")
        guard let properties = properties() else {
            section.add("Battery", "none (desktop Mac)")
            return section
        }
        let data = properties["BatteryData"] as? [String: Any] ?? [:]
        let design = signed(data["DesignCapacity"] ?? properties["DesignCapacity"])
        let full = signed(data["FullChargeCapacity"] ?? properties["AppleRawMaxCapacity"])
        section.add("Charge", "\(signed(properties["CurrentCapacity"]).map { "\($0)%" } ?? "—")")
        section.add("Charging / external power", "\(properties["IsCharging"] as? Bool ?? false) / \(properties["ExternalConnected"] as? Bool ?? false)")
        section.add("Cycle count", signed(properties["CycleCount"]))
        if let design, let full, design > 0 {
            section.add("Health", String(format: "%d of %d mAh (%.0f%%)", full, design, Double(full) / Double(design) * 100))
        }
        if let temperature = signed(properties["Temperature"] ?? properties["VirtualTemperature"]) {
            section.add("Temperature", String(format: "%.1f °C", Double(temperature) / 100))
        }
        section.add("Voltage", signed(properties["Voltage"]).map { String(format: "%.2f V", Double($0) / 1000) })
        section.add("Current", signed(properties["InstantAmperage"] ?? properties["Amperage"]).map { "\($0) mA" })
        section.add("Whole Mac's draw now", systemDrawMW(properties).map { String(format: "%.2f W", $0 / 1000) } ?? "— (on the charger)")
        let remaining = IOPSGetTimeRemainingEstimate()
        section.add("Time remaining estimate", remaining > 0 ? DiagnosticsFormat.duration(remaining) : "unknown / on the charger")
        if let telemetry = properties["PowerTelemetryData"] as? [String: Any], let load = signed(telemetry["SystemLoad"]) {
            section.add("System load (telemetry)", "\(load) mW")
        }
        section.add("Permanent failure", signed(properties["PermanentFailureStatus"]).map { $0 == 0 ? "no" : "YES (\($0))" })
        return section
    }

    /// The processes using the most energy right now (`top`, two samples a second apart: the first
    /// has no rates), and power assertions NotchIsland holds.
    static func topUsers() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Top energy users")
        let output = DiagnosticsProbes.run("/usr/bin/top", ["-l", "2", "-s", "1", "-o", "power", "-n", "12", "-stats", "pid,command,cpu,power,idlew,mem"],
                                           timeout: 10) ?? ""
        // The second sample is the block after the last header line.
        let lines = output.components(separatedBy: "\n")
        if let header = lines.lastIndex(where: { $0.hasPrefix("PID") }) {
            section.add("top (power)", lines[header...].prefix(13).joined(separator: "\n"))
        } else {
            section.add("top (power)", "unavailable")
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let assertions = (DiagnosticsProbes.run("/usr/bin/pmset", ["-g", "assertions"]) ?? "")
            .components(separatedBy: "\n")
            .filter { $0.contains("pid \(pid)(") || $0.contains("NotchIsland") }
        section.add("NotchIsland's power assertions", assertions.isEmpty ? "none" : assertions.joined(separator: "\n"))
        return section
    }
}
