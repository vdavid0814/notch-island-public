import Foundation
import MetricKit

/// A crash or hang as macOS recorded it (a crash reporter `.ips`, a MetricKit diagnostic), in the
/// shape Sentry symbolicates: threads of frames as instruction addresses inside binaries known by
/// their UUID, load address and size. With the build's dSYM uploaded, Sentry turns NotchIsland's
/// frames into functions and lines, as for a crash its own handler caught, so the energy-saving
/// diagnostics need no crash handler running (`Telemetry`). Pure: text or report in, model out.
nonisolated struct NativeCrash: Sendable, Equatable {
    nonisolated struct Frame: Sendable, Equatable {
        var instructionAddress: UInt64
        var imageUUID: String
        /// What the system's report names it (a system library's symbol; NotchIsland's come from
        /// the dSYM).
        var symbol: String?
    }

    nonisolated struct Thread: Sendable, Equatable {
        var id: Int
        var name: String?
        var crashed: Bool
        /// Innermost first, as the reports list them.
        var frames: [Frame]
    }

    nonisolated struct Image: Sendable, Equatable {
        var uuid: String
        var address: UInt64
        var size: UInt64
        var name: String
        /// The binary's path, the home folder written as "~" (it carries the user's name).
        var path: String
    }

    nonisolated enum Kind: String, Sendable { case crash, hang, cpu, diskWrites, launch }

    var kind: Kind
    /// "EXC_BREAKPOINT", "App Hang"…
    var type: String
    /// "SIGTRAP · Trace/BPT trap: 5", "Main thread hung 2.40 s"…
    var value: String
    var date: Date?
    var appVersion: String?
    var appBuild: String?
    var threads: [Thread]
    var images: [Image]
    /// Where it came from ("macOS crash report", "MetricKit").
    var source: String

    /// Only the binaries a frame is in (Sentry needs those; a crash report lists hundreds).
    var usedImages: [Image] {
        let used = Set(threads.flatMap { $0.frames.map(\.imageUUID) })
        return images.filter { used.contains($0.uuid) }
    }

    // MARK: Crash reporter (.ips)

    /// A crash reporter report: one JSON line of header, then the report as JSON.
    static func ips(_ text: String, home: String = NSHomeDirectory()) -> NativeCrash? {
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let header = try? JSONSerialization.jsonObject(with: Data(parts[0].utf8)) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any],
              let rawThreads = body["threads"] as? [[String: Any]],
              let rawImages = body["usedImages"] as? [[String: Any]] else { return nil }
        let images: [Image] = rawImages.compactMap { image in
            guard let uuid = image["uuid"] as? String, let base = number(image["base"]) else { return nil }
            let path = (image["path"] as? String).map { tilde($0, home: home) } ?? ""
            return Image(uuid: uuid.lowercased(), address: base, size: number(image["size"]) ?? 0,
                         name: image["name"] as? String ?? (path as NSString).lastPathComponent, path: path)
        }
        guard !images.isEmpty else { return nil }
        let faulting = body["faultingThread"] as? Int
        let threads: [Thread] = rawThreads.enumerated().map { index, thread in
            let frames: [Frame] = (thread["frames"] as? [[String: Any]] ?? []).compactMap { frame in
                guard let index = frame["imageIndex"] as? Int, images.indices.contains(index),
                      let offset = number(frame["imageOffset"]) else { return nil }
                let image = images[index]
                return Frame(instructionAddress: image.address + offset, imageUUID: image.uuid, symbol: frame["symbol"] as? String)
            }
            return Thread(id: index, name: (thread["name"] as? String) ?? (thread["queue"] as? String),
                          crashed: (thread["triggered"] as? Bool) ?? (index == faulting), frames: frames)
        }
        let exception = body["exception"] as? [String: Any]
        let termination = body["termination"] as? [String: Any]
        let type = exception?["type"] as? String ?? "Crash"
        let value = [exception?["signal"] as? String, termination?["indicator"] as? String,
                     (body["asi"] as? [String: [String]])?.values.flatMap { $0 }.first]
            .compactMap { $0 }.joined(separator: " · ")
        return NativeCrash(kind: .crash, type: type, value: value.isEmpty ? type : value,
                           date: date(header["timestamp"] as? String), appVersion: header["app_version"] as? String,
                           appBuild: header["build_version"] as? String, threads: threads, images: images,
                           source: "macOS crash report")
    }

    // MARK: MetricKit

    /// A MetricKit diagnostic: the heaviest path through each thread's sampled stacks.
    static func metricKit(_ report: DiagnosticReport, home: String = NSHomeDirectory()) -> NativeCrash? {
        guard let tree = DiagnosticsSystemReports.tree(report.result) else { return nil }
        var images: [String: Image] = [:]
        var threads: [Thread] = []
        for (index, thread) in tree.callStackThreads.enumerated() {
            var frames: [Frame] = []
            var level = thread.rootFrames
            // Down the most-sampled branch. A stack recorded per thread (a crash) starts at the
            // innermost frame, its sub-frames its callers; sampled stacks (hangs, CPU) start at
            // the thread's entry, their sub-frames what it called.
            while let frame = level.max(by: { ($0.sampleCount ?? 0) < ($1.sampleCount ?? 0) }) {
                if let uuid = frame.binaryUUID, let address = frame.address, let offset = frame.offsetIntoBinaryTextSegment,
                   address >= offset {
                    let key = uuid.uuidString.lowercased()
                    let name = frame.binaryName(from: tree) ?? tree.binaryInfo[uuid]?.name ?? "?"
                    if images[key] == nil {
                        images[key] = Image(uuid: key, address: address - offset, size: 0, name: name, path: name)
                    }
                    frames.append(Frame(instructionAddress: address, imageUUID: key, symbol: nil))
                }
                level = frame.subFrames
            }
            threads.append(Thread(id: index, name: nil, crashed: thread.threadAttributed ?? (index == 0),
                                  frames: tree.callStackPerThread ? frames : frames.reversed()))
        }
        guard threads.contains(where: { !$0.frames.isEmpty }) else { return nil }
        // MetricKit gives no sizes: each image runs to the furthest address seen in it.
        for (key, image) in images {
            let furthest = threads.flatMap(\.frames).filter { $0.imageUUID == key }.map(\.instructionAddress).max() ?? image.address
            images[key]?.size = furthest - image.address + 4
        }
        let (kind, type): (Kind, String) = switch report.result {
        case .crash(let crash): (.crash, crash.exceptionType.map { "Mach exception \($0)" } ?? "Crash")
        case .hang: (.hang, "App Hang")
        case .cpuException: (.cpu, "CPU Exception")
        case .diskWriteException: (.diskWrites, "Disk Writes Exception")
        case .appLaunch: (.launch, "Slow Launch")
        @unknown default: (.crash, "System Diagnostic")
        }
        return NativeCrash(kind: kind, type: type, value: DiagnosticsSystemReports.headline(report),
                           date: report.timeRange.end, appVersion: report.environment.applicationVersion,
                           appBuild: report.environment.applicationBuildVersion, threads: threads,
                           images: images.values.sorted { $0.address < $1.address }, source: "MetricKit")
    }

    // MARK: Helpers

    private static func number(_ value: Any?) -> UInt64? {
        switch value {
        case let number as NSNumber: number.uint64Value
        case let text as String: text.hasPrefix("0x") ? UInt64(text.dropFirst(2), radix: 16) : UInt64(text)
        default: nil
        }
    }

    static func tilde(_ path: String, home: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// "2026-10-03 02:21:48.00 +0200"
    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        return formatter.date(from: text)
    }
}
