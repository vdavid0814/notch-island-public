import Darwin
import Foundation

/// How busy the Mac is, for work nobody waits on: nothing is moved to background quality of service
/// while the Mac is busy or short of memory (`MainThrift.canLower`, `Thrifty.runInBackground`).
/// Under heavy load a main thread lowered to background got almost no time, so one 0.1 s step of
/// it took seconds, and the island — on the same thread — stuttered meanwhile (reported by a user
/// right after an update, October 13; their Mac had 151 MB of its 16 GB free). The load average is
/// a minute's: what it has not caught up with, `ThriftWatch` catches as it happens.
nonisolated enum SystemLoad {
    /// The one-minute load average as a share of the cores, above which the Mac counts as busy.
    /// Nearly all of them: at 0.6 a system daemon at work on two efficiency cores (photo analysis
    /// on the charger, 200 % for hours) with the usual apps beside it already counted, and nothing
    /// was lowered all evening on a Mac with cores to spare. What a lower load still starves,
    /// `ThriftWatch` lifts within a tenth of a second.
    static let busyShare = 0.9

    /// Busy: the load average past `busyShare` of the cores, or macOS short of memory (its
    /// warning or critical level).
    static var isBusy: Bool { isLoaded || isShortOfMemory }

    static var isLoaded: Bool {
        var loads = [Double](repeating: 0, count: 1)
        guard getloadavg(&loads, 1) == 1 else { return false }
        return loads[0] > Double(ProcessInfo.processInfo.activeProcessorCount) * busyShare
    }

    /// macOS's memory pressure level: 1 normal, 2 warning, 4 critical.
    static var isShortOfMemory: Bool {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return false }
        return level >= 2
    }
}
