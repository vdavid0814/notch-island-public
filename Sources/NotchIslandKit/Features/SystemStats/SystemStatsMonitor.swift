import Darwin
import Foundation

/// Processor and memory load for the System widget.
///
/// Energy: nothing runs unless a System widget is on screen (`startObserving` / `stopObserving`
/// count them); then one Mach call each every two seconds, with a generous timer tolerance so the
/// wake-ups coalesce with the system's.
@Observable final class SystemStatsMonitor {
    /// 0…1 of all cores since the previous sample.
    private(set) var cpu: Double = 0
    /// 0…1 of physical memory in use (app, wired and compressed pages, as Activity Monitor's
    /// "Memory Used").
    private(set) var memory: Double = 0

    static let interval: TimeInterval = 2

    @ObservationIgnored private var observers = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var previousTicks: (busy: UInt64, total: UInt64)?

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
        previousTicks = nil
    }

    private func sample() {
        if let ticks = Self.cpuTicks() {
            if let previous = previousTicks, ticks.total > previous.total {
                let value = Double(ticks.busy - previous.busy) / Double(ticks.total - previous.total)
                if abs(value - cpu) > 0.005 { cpu = min(max(value, 0), 1) }
            }
            previousTicks = ticks
        }
        if let used = Self.memoryUsed(), abs(used - memory) > 0.005 { memory = used }
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

    nonisolated static func memoryUsed() -> Double? {
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
        let app = UInt64(info.internal_page_count) - UInt64(info.purgeable_count)
        let used = (app + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * UInt64(pageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }
        return min(max(Double(used) / Double(total), 0), 1)
    }
}
