import Foundation
import IOKit

/// How busy the graphics processor is, as Activity Monitor's GPU History: the accelerator's own
/// "Device Utilization %" in its performance statistics (IOKit, no permission asked). The
/// accelerator is found once; each reading is one property read of it.
nonisolated enum GPUStats {
    /// 0…1, or nil where the Mac's accelerator says nothing.
    static func utilization() -> Double? {
        guard let service = accelerator.service,
              let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                  .takeRetainedValue() as? [String: Any] else { return nil }
        return utilization(in: property)
    }

    /// The share in a performance statistics dictionary: the device's own, else the renderer's.
    static func utilization(in statistics: [String: Any]) -> Double? {
        for key in ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %"] {
            if let percent = (statistics[key] as? NSNumber)?.doubleValue, percent.isFinite {
                return min(max(percent / 100, 0), 1)
            }
        }
        return nil
    }

    /// The first accelerator with statistics (Apple silicon has one).
    private static let accelerator = Accelerator()

    private final class Accelerator: @unchecked Sendable {
        let service: io_registry_entry_t?

        init() {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
                service = nil
                return
            }
            defer { IOObjectRelease(iterator) }
            var found: io_registry_entry_t?
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                if found == nil,
                   IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() != nil {
                    found = entry
                } else {
                    IOObjectRelease(entry)
                }
            }
            service = found
        }
    }
}
