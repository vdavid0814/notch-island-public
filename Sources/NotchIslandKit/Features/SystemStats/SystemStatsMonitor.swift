import Darwin
import Foundation

/// Processor, graphics and memory load for the System and Memory widgets, and — for System's
/// graph — the last ten minutes of each.
///
/// Energy: nothing runs unless a System widget is on screen (`startObserving` / `stopObserving`
/// count them); then one Mach call each every two seconds (every second while a graph is shown, as
/// Fan Control's is), with a generous timer tolerance so the wake-ups coalesce with the system's.
/// The graphics processor is read only while a widget shows it. Once a graph has been shown, one
/// reading every fifteen seconds keeps its past while nothing is on screen (`keepHistory`).
@Observable final class SystemStatsMonitor {
    /// 0…1 of all cores since the previous sample.
    private(set) var cpu: Double = 0
    /// 0…1 of the graphics processor's time (nil until read, or where the Mac does not say).
    private(set) var gpu: Double?
    /// 0…1 of physical memory in use (app, wired and compressed pages, as Activity Monitor's
    /// "Memory Used").
    private(set) var memory: Double = 0
    /// The same in bytes (nil until read), for the Memory widget; changes of under 8 MB are left out.
    private(set) var memoryBytes: UInt64?
    let physicalMemory = ProcessInfo.processInfo.physicalMemory

    /// Each load (0…1) over the last ten minutes, oldest first: what System's graph draws.
    private(set) var cpuHistory: [SensorSample] = []
    private(set) var gpuHistory: [SensorSample] = []
    private(set) var memoryHistory: [SensorSample] = []

    static let interval: TimeInterval = 2
    /// While a graph is shown: every second, so a minute's graph has sixty readings.
    static let graphInterval: TimeInterval = 1
    static let historyInterval: TimeInterval = 15
    /// How far back the history reaches: the longest a graph is set to show (`WidgetConfig.secondsRange`).
    nonisolated static let window: TimeInterval = 600

    /// What a widget on screen needs besides the processor and memory.
    struct Needs: OptionSet, Hashable, Sendable {
        let rawValue: Int
        /// The graphics processor's load.
        static let gpu = Needs(rawValue: 1)
        /// A reading every second, kept in the history.
        static let graph = Needs(rawValue: 2)
    }

    @ObservationIgnored private var observers = 0
    @ObservationIgnored private var gpuObservers = 0
    @ObservationIgnored private var graphObservers = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var historyTimer: Timer?
    /// The history keeps the graphics processor's load too (a graph showing it was on screen).
    @ObservationIgnored private var historyNeedsGPU = false
    @ObservationIgnored private var previousTicks: (busy: UInt64, total: UInt64)?

    func startObserving(_ needs: Needs = []) {
        observers += 1
        if needs.contains(.gpu) { gpuObservers += 1 }
        if needs.contains(.graph) { graphObservers += 1 }
        schedule()
    }

    func stopObserving(_ needs: Needs = []) {
        observers = max(0, observers - 1)
        if needs.contains(.gpu) { gpuObservers = max(0, gpuObservers - 1) }
        if needs.contains(.graph) { graphObservers = max(0, graphObservers - 1) }
        guard observers == 0 else {
            schedule()
            return
        }
        timer?.invalidate()
        timer = nil
        previousTicks = nil
    }

    /// Keeps the graph's past from now on: a reading of each load every fifteen seconds (skipped
    /// while a widget reads them more often); the graphics processor's too where `gpu`.
    func keepHistory(gpu: Bool) {
        if gpu { historyNeedsGPU = true }
        guard historyTimer == nil else { return }
        let timer = Timer(timeInterval: Self.historyInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.timer == nil else { return }
                self.sample(history: true, gpu: self.historyNeedsGPU)
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        historyTimer = timer
    }

    /// The timer at the pace the widgets on screen need; a first reading at once.
    private func schedule() {
        let interval = graphObservers > 0 ? Self.graphInterval : Self.interval
        if let timer, timer.timeInterval == interval { return }
        let isFirst = timer == nil
        timer?.invalidate()
        if isFirst { sampleNow() }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleNow() }
        }
        timer.tolerance = interval / (graphObservers > 0 ? 4 : 2)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sampleNow() {
        sample(history: graphObservers > 0 || historyTimer != nil, gpu: gpuObservers > 0 || (historyTimer != nil && historyNeedsGPU))
    }

    private func sample(history: Bool, gpu readsGPU: Bool) {
        let now = Date.now
        if let ticks = Self.cpuTicks() {
            if let previous = previousTicks, ticks.total > previous.total {
                let value = min(max(Double(ticks.busy - previous.busy) / Double(ticks.total - previous.total), 0), 1)
                if abs(value - cpu) > 0.005 { cpu = value }
                if history { SensorSample.append(SensorSample(date: now, value: value), to: &cpuHistory, window: Self.window) }
            }
            previousTicks = ticks
        }
        if readsGPU, let value = GPUStats.utilization() {
            if gpu.map({ abs(value - $0) > 0.005 }) ?? true { gpu = value }
            if history { SensorSample.append(SensorSample(date: now, value: value), to: &gpuHistory, window: Self.window) }
        }
        if let bytes = Self.memoryUsedBytes() {
            if memoryBytes.map({ max($0, bytes) - min($0, bytes) >= Self.memoryStep }) ?? true { memoryBytes = bytes }
            if physicalMemory > 0 {
                let used = min(max(Double(bytes) / Double(physicalMemory), 0), 1)
                if abs(used - memory) > 0.005 { memory = used }
                if history { SensorSample.append(SensorSample(date: now, value: used), to: &memoryHistory, window: Self.window) }
            }
        }
    }

    /// Busy and total ticks over all cores (user + system + nice are busy; idle is not).
    nonisolated static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        return (busy, busy + idle)
    }

    static let memoryStep: UInt64 = 8 << 20

    /// Memory in use, as Activity Monitor's "Memory Used".
    nonisolated static func memoryUsedBytes() -> UInt64? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        // App memory (internal − purgeable) + wired + compressed.
        let resident = UInt64(info.internal_page_count), purgeable = UInt64(info.purgeable_count)
        let app = resident > purgeable ? resident - purgeable : 0
        return (app + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * UInt64(pageSize)
    }
}
