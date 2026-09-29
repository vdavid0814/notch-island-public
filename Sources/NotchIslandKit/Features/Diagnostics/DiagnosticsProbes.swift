import AppKit
import ApplicationServices
import CoreServices
import Darwin
import Foundation

/// The readings that need no app state: the Mac, the bundle, the process, permissions that can be
/// asked about without a prompt, the Spotlight index Siri's app search stands on, the log and the
/// crash reports.
///
/// Everything here blocks (child processes, Spotlight queries, directory walks), so it runs only
/// inside `@concurrent` functions, never on the main actor.
nonisolated enum DiagnosticsProbes {
    // MARK: The Mac

    static func system() -> DiagnosticsReport.Section {
        let info = ProcessInfo.processInfo
        var section = DiagnosticsReport.Section("Mac")
        section.add("macOS", info.operatingSystemVersionString)
        section.add("Model", sysctlString("hw.model") ?? "—")
        section.add("Chip", sysctlString("machdep.cpu.brand_string") ?? "—")
        section.add("Cores", "\(info.processorCount) (\(info.activeProcessorCount) active)")
        section.add("Memory", DiagnosticsFormat.bytes(info.physicalMemory))
        section.add("Running under Rosetta", sysctlInt("sysctl.proc_translated") == 1)
        section.add("Uptime", DiagnosticsFormat.duration(info.systemUptime))
        section.add("Thermal state", String(describing: info.thermalState))
        section.add("Low Power Mode", info.isLowPowerModeEnabled)
        section.add("Locale", Locale.current.identifier)
        section.add("Languages", Locale.preferredLanguages.joined(separator: ", "))
        section.add("Time zone", TimeZone.current.identifier)
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            let free = values.volumeAvailableCapacityForImportantUsage.map { DiagnosticsFormat.bytes($0) } ?? "—"
            let total = values.volumeTotalCapacity.map { DiagnosticsFormat.bytes($0) } ?? "—"
            section.add("Disk free", "\(free) of \(total)")
        }
        section.add("Menu bar hidden in full screen", !UserDefaults.standard.bool(forKey: "AppleMenuBarVisibleInFullscreen"))
        section.add("Menu bar auto-hide", UserDefaults.standard.bool(forKey: "_HIHideMenuBar"))
        return section
    }

    // MARK: The app bundle and the process

    /// Where the running copy lives and how it is signed: "the same version behaves differently" is
    /// often a copy run from the disk image, a translocated copy, or an older copy found first.
    static func bundle(launchedAt: Date) -> DiagnosticsReport.Section {
        let bundle = Bundle.main
        let path = bundle.bundleURL.path
        var section = DiagnosticsReport.Section("App")
        section.add("Version", bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
        section.add("Build", bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—")
        section.add("Path", path)
        section.add("In /Applications", path.hasPrefix("/Applications/"))
        section.add("Run from a disk image", path.hasPrefix("/Volumes/"))
        section.add("Translocated", path.contains("/AppTranslocation/"))
        section.add("Quarantined", quarantine(path) ?? "no")
        section.add("Signature", signature())
        section.add("PID", ProcessInfo.processInfo.processIdentifier)
        section.add("Running for", DiagnosticsFormat.duration(Date().timeIntervalSince(launchedAt)))
        section.add("Launched", DiagnosticsFormat.date(launchedAt))
        let (footprint, peak) = memoryFootprint()
        section.add("Memory footprint", "\(footprint.map { DiagnosticsFormat.bytes($0) } ?? "—") (peak \(peak.map { DiagnosticsFormat.bytes($0) } ?? "—"))")
        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
            let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
            let alive = max(Date().timeIntervalSince(launchedAt), 1)
            section.add("CPU time", String(format: "%@ user, %@ system (%.2f%% average)",
                                           DiagnosticsFormat.duration(user), DiagnosticsFormat.duration(system),
                                           (user + system) / alive * 100))
        }
        return section
    }

    private static func quarantine(_ path: String) -> String? {
        let name = "com.apple.quarantine"
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard getxattr(path, name, &buffer, length, 0, 0) == length else { return "yes" }
        return "yes: " + String(decoding: buffer, as: UTF8.self)
    }

    /// Read from the kernel (`csops`), which checked the signature when the app launched and
    /// keeps checking its pages: Security's `SecCodeCopySelf` logged sqlite errors from the
    /// system's detached-signature database at every call (seen in reports, both Macs), and the
    /// static check hashed the whole bundle again. Once per launch: it does not change.
    private static let signatureOnce: String = checkSignature()

    private static func signature() -> String { signatureOnce }

    static func checkSignature() -> String {
        var flags: UInt32 = 0
        guard csops(getpid(), CodeSigning.status, &flags, MemoryLayout<UInt32>.size) == 0 else { return "unreadable" }
        guard flags & CodeSigning.signed != 0 || flags & CodeSigning.valid != 0 else { return "unsigned" }
        let identifier = CodeSigning.string(CodeSigning.identity) ?? Bundle.main.bundleIdentifier ?? "?"
        let team = CodeSigning.string(CodeSigning.teamID)
        let adHoc = flags & (CodeSigning.adHoc | CodeSigning.linkerSigned) != 0
        return "\(identifier), team \(team ?? "none")\(adHoc ? ", ad hoc" : ""), \(flags & CodeSigning.valid != 0 ? "valid" : "INVALID (flags 0x\(String(flags, radix: 16)))")"
    }

    /// The kernel's code-signing operations (`<sys/codesign.h>`, not in the SDK).
    private enum CodeSigning {
        static let status: UInt32 = 0
        static let identity: UInt32 = 11
        static let teamID: UInt32 = 14
        static let valid: UInt32 = 0x1
        static let adHoc: UInt32 = 0x2
        static let linkerSigned: UInt32 = 0x20000
        static let signed: UInt32 = 0x2000_0000

        /// A string the kernel hands back as a blob: 8 bytes of header (magic, big-endian length),
        /// then the C string.
        static func string(_ operation: UInt32) -> String? {
            var buffer = [UInt8](repeating: 0, count: 1024)
            let result = buffer.withUnsafeMutableBytes { csops(getpid(), operation, $0.baseAddress, $0.count) }
            guard result == 0 else { return nil }
            let length = Int(UInt32(bigEndian: buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }))
            guard length > 8, length <= buffer.count else { return nil }
            let text = String(decoding: buffer[8..<length].prefix { $0 != 0 }, as: UTF8.self)
            return text.isEmpty ? nil : text
        }
    }

    private static func memoryFootprint() -> (UInt64?, UInt64?) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (nil, nil) }
        return (info.phys_footprint, info.ledger_phys_footprint_peak > 0 ? UInt64(info.ledger_phys_footprint_peak) : nil)
    }

    // MARK: Permissions

    /// The permissions that can be read without showing a prompt.
    static func permissions() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Permissions")
        section.add("Accessibility", AXIsProcessTrusted())
        section.add("Input Monitoring (listen)", CGPreflightListenEventAccess())
        section.add("Post events", CGPreflightPostEventAccess())
        section.add("Screen Recording", CGPreflightScreenCaptureAccess())
        for (name, bundleID) in [("Music", "com.apple.Music"), ("Spotify", "com.spotify.client")] {
            section.add("Automation: \(name)", automation(bundleID))
        }
        return section
    }

    private static func automation(_ bundleID: String) -> String {
        // Asking about an app that is not running only logs `procNotFound` errors (every report,
        // both Macs); the answer is the same without asking.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            return "unknown (app not running)"
        }
        var target = AEAddressDesc()
        let status: OSStatus = bundleID.withCString { pointer in
            guard AECreateDesc(typeApplicationBundleID, pointer, strlen(pointer), &target) == noErr else { return OSStatus(-1) }
            defer { AEDisposeDesc(&target) }
            return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
        }
        switch status {
        case noErr: return "allowed"
        case OSStatus(errAEEventNotPermitted): return "DENIED"
        case OSStatus(errAEEventWouldRequireUserConsent): return "not asked yet"
        case OSStatus(procNotFound): return "unknown (app not running)"
        default: return "status \(status)"
        }
    }

    // MARK: Spotlight (Siri's app search)

    /// Siri's Applications and app hits come from the Spotlight index (`AssistantSearch`). An empty
    /// or partial index, or a volume with indexing off, shows here as apps on disk that Spotlight
    /// does not return.
    static func spotlight() async -> DiagnosticsReport {
        var report = DiagnosticsReport()
        var section = DiagnosticsReport.Section(spotlightTitle)
        for volume in ["/", "/System/Volumes/Data"] {
            section.add("mdutil -s \(volume)", run("/usr/bin/mdutil", ["-s", volume]) ?? "failed")
        }
        let predicate = #"kMDItemContentTypeTree == "com.apple.application-bundle""#
        section.add("mdfind -count (apps)", run("/usr/bin/mdfind", ["-count", predicate]) ?? "failed")

        var missing: [String] = []
        var onDiskTotal = 0
        for scope in AssistantSearch.appScopes {
            let started = Date()
            let indexed = Set(queryPaths(predicate, scope: scope).map(normalized))
            let took = Date().timeIntervalSince(started)
            let onDisk = appsOnDisk(in: scope)
            onDiskTotal += onDisk.count
            let absent = onDisk.filter { !indexed.contains(normalized($0)) }
            section.add("\(scope)", "on disk \(onDisk.count), in Spotlight \(indexed.count) (query \(DiagnosticsFormat.duration(took))), missing \(absent.count)")
            missing += absent.map { ($0 as NSString).abbreviatingWithTildeInPath }
        }
        section.add(missingKey, missing.count)
        if onDiskTotal > 0 {
            report.metrics[.spotlightMissingPercent] = Double(missing.count) / Double(onDiskTotal) * 100
        }
        if !missing.isEmpty {
            let shown = missing.prefix(60).joined(separator: "\n")
            section.add("Missing from Spotlight", missing.count > 60 ? shown + "\n… and \(missing.count - 60) more" : shown)
        }

        var started = Date()
        let all = await AssistantSearch.allApps()
        let galleryTook = Date().timeIntervalSince(started)
        report.metrics[.gallerySeconds] = galleryTook
        section.add(galleryKey, "\(all.count) apps in \(DiagnosticsFormat.duration(galleryTook))")
        section.add("allApps() first 10", all.prefix(10).map(\.name).joined(separator: ", "))
        var slowest: TimeInterval = 0
        for probe in ["saf", "fin", "set", "mus"] {
            started = Date()
            let hits = await AssistantSearch.apps(matching: probe, limit: 5)
            let took = Date().timeIntervalSince(started)
            slowest = max(slowest, took)
            section.add("apps(\"\(probe)\")", "\(hits.map(\.name).joined(separator: ", ")) (\(DiagnosticsFormat.duration(took)))")
        }
        report.metrics[.appSearchSeconds] = slowest
        section.add("Spotlight preferences", DiagnosticsFormat.head(run("/usr/bin/defaults", ["read", "com.apple.Spotlight"]) ?? "—", limit: 4000))
        report.sections = [section]
        return report
    }

    static let spotlightTitle = "Spotlight and Siri's app search"
    static let missingKey = "Apps missing from Spotlight"
    static let galleryKey = "allApps() (the gallery)"

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
    }

    /// The paths Spotlight returns for `predicate` under `scope`.
    private static func queryPaths(_ predicate: String, scope: String) -> [String] {
        guard let query = MDQueryCreate(kCFAllocatorDefault, predicate as CFString, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, [scope] as CFArray, 0)
        MDQuerySetMaxCount(query, 5000)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var paths: [String] = []
        for index in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            if let path = MDItemCopyAttribute(item, kMDItemPath) as? String { paths.append(path) }
        }
        return paths
    }

    /// The apps in `folder` and one folder deeper (Utilities, a vendor's folder), not inside apps.
    private static func appsOnDisk(in folder: String) -> [String] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: folder) else { return [] }
        var apps: [String] = []
        for name in names where !name.hasPrefix(".") {
            let path = folder + "/" + name
            if name.hasSuffix(".app") {
                apps.append(path)
            } else if let inner = try? manager.contentsOfDirectory(atPath: path) {
                apps += inner.filter { $0.hasSuffix(".app") }.map { path + "/" + $0 }
            }
        }
        return apps.sorted()
    }

    // MARK: Log and crash reports

    /// The app's own log for the last `hours` (earlier launches included, so what led up to a crash
    /// is there), plus errors and faults the frameworks logged in the process.
    static func log(hours: Int, limit: Int) -> DiagnosticsReport.Attachment {
        log(since: Date().addingTimeInterval(-Double(hours) * 3600), limit: limit)
    }

    /// From `start` on: reading the log costs ~0.5 s of CPU an hour of it (plus the log daemon's
    /// work, billed to the app), so an automatic report reads only what the one before did not.
    static func log(since start: Date, limit: Int) -> DiagnosticsReport.Attachment {
        let predicate = #"process == "NotchIsland" AND (subsystem == "\#(Log.subsystem)" OR messageType >= error)"#
        let output = run("/usr/bin/log", ["show", "--start", logDate(start), "--info", "--style", "compact", "--predicate", predicate],
                         timeout: 150, outputLimit: limit * 3, throttled: true) ?? "log show failed"
        return DiagnosticsReport.Attachment(name: "log.txt", text: DiagnosticsFormat.tail(output, limit: limit))
    }

    /// `log show --start`'s format, in local time.
    static func logDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// The user's reports, and the system's (hang and resource reports land there).
    static let diagnosticReportsFolders = [
        NSHomeDirectory() + "/Library/Logs/DiagnosticReports",
        "/Library/Logs/DiagnosticReports",
    ]

    /// NotchIsland's crash, hang and resource reports, newest first.
    private static func reportFiles() -> [(url: URL, date: Date)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        return diagnosticReportsFolders.flatMap { folder -> [(url: URL, date: Date)] in
            let files = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: keys)) ?? []
            return files
                .filter { $0.lastPathComponent.hasPrefix("NotchIsland") }
                .compactMap { url in
                    (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate).map { (url, $0) }
                }
        }
        .sorted { $0.date > $1.date }
    }

    /// Crash, hang and resource reports of NotchIsland written after `since`, newest first.
    static func crashReports(since: Date, limit: Int, perFile: Int) -> [DiagnosticsReport.Attachment] {
        reportFiles().filter { $0.date > since }.prefix(limit).compactMap { url, _ in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return DiagnosticsReport.Attachment(name: url.lastPathComponent, text: DiagnosticsFormat.head(text, limit: perFile))
        }
    }

    /// How many reports the system kept, and the newest ones.
    static func crashSummary() -> String {
        let files = reportFiles()
        guard !files.isEmpty else { return "none" }
        return "\(files.count): " + files.prefix(6).map { "\($0.url.lastPathComponent)" }.joined(separator: ", ")
    }

    static func crashCount(days: Double) -> Int {
        let since = Date().addingTimeInterval(-days * 86400)
        return reportFiles().count { $0.date > since }
    }

    static func crashCount(since: Date) -> Int {
        reportFiles().count { $0.date > since }
    }

    /// Errors and faults in a compact-style log ("2026-09-27 21:10:40.892 E  NotchIsland…").
    static func errorLines(in log: String) -> [Substring] {
        log.split(separator: "\n").filter { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count > 2 else { return false }
            return fields[2].hasPrefix("E") || fields[2].hasPrefix("F")
        }
    }

    /// Sound and displays as System Information lists them (short form).
    static func hardware() -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section("Hardware")
        for (title, type) in [("Audio", "SPAudioDataType"), ("Displays", "SPDisplaysDataType")] {
            let output = run("/usr/sbin/system_profiler", ["-detailLevel", "mini", type], timeout: 30, throttled: true) ?? "unavailable"
            section.add(title, DiagnosticsFormat.head(output, limit: 3000))
        }
        return section
    }

    // MARK: Helpers

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    /// Runs a tool and returns its trimmed standard output and error, or nil if it could not start.
    /// Killed after `timeout` seconds; reads at most `outputLimit` bytes.
    /// `throttled`: the tool runs `Throttle.on` of every `Throttle.period` and is paused the rest,
    /// so it never takes a whole core (40 % of one at most) — `log show` did for seconds, and Activity Monitor showed
    /// NotchIsland's Energy Impact near 100 while a report was collected.
    static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 8, outputLimit: Int = 1_000_000,
                    throttled: Bool = false) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        // On the efficiency cores: nobody waits on a report, and `log show` on the performance
        // cores was most of a report's ~20 J (4.8 J at background, measured).
        process.qualityOfService = .background
        do { try process.run() } catch { return nil }
        let pid = process.processIdentifier
        let throttle = throttled ? Throttle.start(pid) : nil
        let killer = DispatchWorkItem {
            guard process.isRunning else { return }
            throttle?.cancel()
            process.terminate()
            kill(pid, SIGCONT)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)
        var data = Data()
        let handle = pipe.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            // Keep the newest output; the end of a log matters most.
            data.append(chunk)
            if data.count > outputLimit { data.removeFirst(data.count - outputLimit) }
        }
        process.waitUntilExit()
        throttle?.cancel()
        killer.cancel()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pauses and resumes a child process (SIGSTOP / SIGCONT) so it gets `on` of every `period`.
    enum Throttle {
        /// Milliseconds: the tool runs `on` of every `period`.
        static let period = 500
        static let on = 200

        static func start(_ pid: pid_t) -> any DispatchSourceTimer {
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + .milliseconds(on), repeating: .milliseconds(period), leeway: .milliseconds(10))
            timer.setEventHandler {
                kill(pid, SIGSTOP)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(period - on)) { kill(pid, SIGCONT) }
            }
            // Never left paused: a cancel resumes it.
            timer.setCancelHandler { kill(pid, SIGCONT) }
            timer.resume()
            return timer
        }
    }
}

@_silgen_name("csops")
nonisolated private func csops(_ pid: pid_t, _ operation: UInt32, _ buffer: UnsafeMutableRawPointer?, _ size: Int) -> Int32
