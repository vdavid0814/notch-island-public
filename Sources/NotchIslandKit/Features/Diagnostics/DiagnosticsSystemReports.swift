import Foundation
import MetricKit

/// What macOS itself caught about the app (MetricKit): main-thread hangs, CPU and disk-write
/// exceptions, crashes and slow launches, each with the call stacks the system sampled. The system
/// collects them at no cost to the app and hands them over as they come (up to a day late); each
/// is kept on disk until a report has carried it, and a new one sends a report of its own.
nonisolated enum DiagnosticsSystemReports {
    /// Attachments with this prefix are the system's reports, not crash reports (`.ips`).
    static let prefix = "system-"
    /// Reports kept for a report, and how much of each is attached.
    static let keptLimit = 20
    static let attachedLimit = 4
    static let perFile = 200_000

    static var folder: URL? {
        DiagnosticsCenter.supportFolder?.appendingPathComponent("SystemDiagnostics", isDirectory: true)
    }

    /// Waits for the system's reports for as long as the app runs (nothing runs until one comes):
    /// each is saved, then `arrived` gets its one-line summary on the main actor.
    static func watch(arrived: @escaping @MainActor @Sendable (String) -> Void) -> Task<Void, Never> {
        Task.detached(priority: .background) {
            let manager = MetricManager()
            for await report in manager.diagnosticReports {
                guard let folder else { continue }
                guard save(report, in: folder) != nil else { continue }
                let line = headline(report)
                await arrived(line)
            }
            withExtendedLifetime(manager) {}
        }
    }

    // MARK: Storing

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @discardableResult
    static func save(_ report: DiagnosticReport, in folder: URL) -> URL? {
        guard let data = try? encoder.encode(report) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = report.timeRange.end.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .dateSeparator(.omitted).timeSeparator(.omitted).dateTimeSeparator(.standard))
        let url = folder.appendingPathComponent("\(prefix)\(stamp)-\(kind(report.result))-\(UUID().uuidString.prefix(4)).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        prune(folder)
        return url
    }

    /// The reports not yet carried by a report, oldest first.
    static func pending(in folder: URL? = folder) -> [URL] {
        guard let folder else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A report carried these: they go.
    static func markSent(_ names: [String], in folder: URL? = folder) {
        guard let folder else { return }
        for name in names where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Only the newest `keptLimit` stay (a report that never goes out must not fill the disk).
    private static func prune(_ folder: URL) {
        let files = pending(in: folder)
        for file in files.dropLast(keptLimit) { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: Reading

    static func kind(_ result: DiagnosticResult) -> String {
        switch result {
        case .crash: "crash"
        case .hang: "hang"
        case .cpuException: "cpu"
        case .diskWriteException: "diskwrite"
        case .appLaunch: "launch"
        @unknown default: "other"
        }
    }

    static func headline(_ report: DiagnosticReport) -> String {
        let when = DiagnosticsFormat.date(report.timeRange.end)
        let version = "v\(report.environment.applicationVersion) (\(report.environment.applicationBuildVersion))"
        return switch report.result {
        case .hang(let hang):
            String(format: "Main thread hung %.2f s, %@, %@", hang.hangDuration.converted(to: .seconds).value, version, when)
        case .crash(let crash):
            "Crash: signal \(crash.signal.map(String.init) ?? "?"), exception \(crash.exceptionType.map(String.init) ?? "?")"
                + (crash.terminationReason.map { ", \($0.rawValue)" } ?? "")
                + (crash.exceptionReason.map { ", \($0.className): \($0.composedMessage)" } ?? "") + ", \(version), \(when)"
        case .cpuException(let cpu):
            String(format: "CPU exception: %.1f s of CPU in %.1f s, %@, %@", cpu.totalCPUTime.converted(to: .seconds).value,
                   cpu.totalSampledTime.converted(to: .seconds).value, version, when)
        case .diskWriteException(let disk):
            "Disk writes exception: \(disk.totalBytesWritten.converted(to: .megabytes).value.formatted(.number.precision(.fractionLength(1)))) MB, \(version), \(when)"
        case .appLaunch(let launch):
            String(format: "Slow launch: %.2f s, %@, %@", launch.launchDuration.converted(to: .seconds).value, version, when)
        @unknown default:
            "A system report, \(version), \(when)"
        }
    }

    static func tree(_ result: DiagnosticResult) -> CallStackTree? {
        switch result {
        case .crash(let crash): crash.callStackTree
        case .hang(let hang): hang.callStackTree
        case .cpuException(let cpu): cpu.callStackTree
        case .diskWriteException(let disk): disk.callStackTree
        case .appLaunch(let launch): launch.callStackTree
        @unknown default: nil
        }
    }

    /// The heaviest path through the attributed thread's stacks (the most samples at each step),
    /// as binary + offset: NotchIsland's own offsets symbolicate against the build (`atos`).
    static func heaviestPath(_ tree: CallStackTree, limit: Int = 16) -> [String] {
        let thread = tree.callStackThreads.first { $0.threadAttributed == true } ?? tree.callStackThreads.first
        var frames = thread?.rootFrames ?? []
        var lines: [String] = []
        while let frame = frames.max(by: { ($0.sampleCount ?? 0) < ($1.sampleCount ?? 0) }), lines.count < limit {
            let binary = frame.binaryName(from: tree) ?? "?"
            let offset = frame.offsetIntoBinaryTextSegment.map { "+0x" + String($0, radix: 16) } ?? ""
            lines.append("\(binary) \(offset)\(frame.sampleCount.map { " (\($0) samples)" } ?? "")")
            frames = frame.subFrames
        }
        return lines
    }

    /// The report's section and attachments: every waiting report summed up, the newest attached.
    static func collect() -> (section: DiagnosticsReport.Section, attachments: [DiagnosticsReport.Attachment], count: [String: Int]) {
        var section = DiagnosticsReport.Section(title)
        let files = pending()
        var counts: [String: Int] = [:]
        var attachments: [DiagnosticsReport.Attachment] = []
        section.add("Waiting", files.isEmpty ? "none (macOS reported no hang, crash or CPU/disk exception)" : "\(files.count)")
        for file in files {
            guard let data = try? Data(contentsOf: file) else { continue }
            guard let report = try? decoder.decode(DiagnosticReport.self, from: data) else {
                section.add(file.lastPathComponent, "unreadable")
                continue
            }
            counts[kind(report.result), default: 0] += 1
            var lines = [headline(report)]
            if let tree = tree(report.result) { lines += heaviestPath(tree).map { "  " + $0 } }
            section.add(file.lastPathComponent, lines.joined(separator: "\n"))
        }
        if !counts.isEmpty {
            section.entries.insert(.init(key: kindsKey, value: counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
                .joined(separator: ", ")), at: 1)
        }
        for file in files.suffix(attachedLimit) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            attachments.append(.init(name: file.lastPathComponent, text: String(text.prefix(perFile))))
        }
        return (section, attachments, counts)
    }

    static let title = "System diagnostics (MetricKit)"
    static let kindsKey = "Kinds"
}

extension DiagnosticsReport.Attachment {
    /// A crash, hang or resource report from the crash reporter (not the log, not MetricKit's).
    nonisolated var isCrashReport: Bool { name != "log.txt" && !name.hasPrefix(DiagnosticsSystemReports.prefix) }
}
