import Darwin
import Foundation

/// Memory as the report tells it: what the heap really holds against what the allocator keeps of
/// freed memory, what was counted twice and corrected (`AliasTrim`), and whether the footprint at
/// rest keeps growing (a leak shows as a floor that rises hour after hour, not as one high reading).
nonisolated enum DiagnosticsMemory {
    /// The heap: bytes in live allocations, and what the allocator holds for them.
    static func heap() -> (inUse: UInt64, held: UInt64) {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return (UInt64(stats.size_in_use), UInt64(stats.size_allocated))
    }

    /// MB per hour the footprint's floor rises: the lowest reading of each hour (Settings closed,
    /// Siri gone, the island at rest somewhere in it), as a least-squares line through them. nil
    /// before three hours of readings: a launch's first hour rises as Settings is built ahead.
    static func growthPerHour(_ readings: [(date: Date, megabytes: Double)]) -> Double? {
        guard let first = readings.map(\.date).min() else { return nil }
        var floors: [Int: Double] = [:]
        for reading in readings {
            let hour = Int(reading.date.timeIntervalSince(first) / 3600)
            floors[hour] = min(floors[hour] ?? .infinity, reading.megabytes)
        }
        // The launch's own hour is left out (Settings built ahead, the first openings).
        let points = floors.filter { $0.key >= 1 }.sorted { $0.key < $1.key }.map { (x: Double($0.key), y: $0.value) }
        guard points.count >= 3 else { return nil }
        let meanX = points.map(\.x).reduce(0, +) / Double(points.count)
        let meanY = points.map(\.y).reduce(0, +) / Double(points.count)
        let covariance = points.reduce(0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        let variance = points.reduce(0) { $0 + ($1.x - meanX) * ($1.x - meanX) }
        return variance > 0 ? covariance / variance : nil
    }

    /// The report's lines on memory beyond the footprint itself.
    static func lines() -> [(String, String)] {
        let heap = heap()
        let corrections = AliasTrim.corrections.withLock { $0 }
        var lines: [(String, String)] = [
            ("Heap", "\(DiagnosticsFormat.bytes(heap.inUse)) in use, \(DiagnosticsFormat.bytes(heap.held)) held by the allocator"),
        ]
        lines.append(("Counted twice, corrected", corrections.places == 0 ? "nothing yet"
            : "\(DiagnosticsFormat.bytes(corrections.bytes)) in \(corrections.places) places (SwiftUI's graph table, pictures handed to the window server)"))
        return lines
    }

    /// Each kind of opening's cost, and the metrics set against the reference: the panel's
    /// openings together, Siri's, Settings'.
    static func openings(_ summaries: [OpeningMeter.Kind: OpeningMeter.Summary]) -> (lines: [(String, String)], metrics: [DiagnosticsMetric: Double]) {
        var lines: [(String, String)] = []
        for kind in OpeningMeter.Kind.allCases {
            lines.append((kind.title, summaries[kind]?.line ?? "none yet"))
        }
        var metrics: [DiagnosticsMetric: Double] = [:]
        // Judged once there are a few: one opening is the launch's own (everything cold).
        let panel = [summaries[.panelKept], summaries[.panelBuilt]].compactMap { $0 }
        let panelCount = panel.reduce(0) { $0 + $1.count }
        if panelCount >= 5 {
            metrics[.openingMJ] = panel.reduce(0) { $0 + $1.medianMJ * Double($1.count) } / Double(panelCount)
        }
        if let siri = summaries[.siri], siri.count >= 3 { metrics[.siriOpeningMJ] = siri.medianMJ }
        if let settings = summaries[.settings], settings.count >= 3 { metrics[.settingsOpeningMJ] = settings.medianMJ }
        if let search = summaries[.siriSearch], search.count >= 5 { metrics[.siriSearchMJ] = search.worstTenthMJ }
        return (lines, metrics)
    }
}
