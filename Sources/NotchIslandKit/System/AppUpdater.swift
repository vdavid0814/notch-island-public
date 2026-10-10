import AppKit
import Foundation
import Security

/// The newest version, from About: looked up on GitHub, downloaded, checked and installed in place
/// of this copy, then reopened — no disk image to open, nothing to drag, no Finder window.
///
/// Why in place: macOS keeps a permission (Accessibility, Input Monitoring, …) for an app it
/// recognises by its bundle identifier and its signature's designated requirement. The new copy
/// lands at the same path and must satisfy this copy's own requirement, so every switch the user
/// flipped stays on. A download signed by anyone else is not installed silently: About says the
/// permissions would have to be allowed again and asks.
@MainActor @Observable final class AppUpdater {
    nonisolated struct Release: Equatable, Sendable {
        var version: String
        var diskImage: URL
        var notes: String
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(Release)
        /// `progress` 0…1, nil while the size is not known yet.
        case downloading(Release, progress: Double?)
        case installing(Release, step: String)
        /// Verified but signed differently from this copy: installing would cost the permissions.
        case differentSigner(Release, staged: URL)
        /// Installed: NotchIsland reopens in a moment.
        case relaunching(Release)
        /// Could not install in place (a read-only location): the disk image is open in Finder.
        case manual(Release, URL)
        case failed(String)
    }

    private(set) var state: State = .idle
    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    /// The version this launch was updated from, once, for About's "Updated" line.
    private(set) var updatedFrom: String?

    nonisolated static let assetName = "NotchIsland.dmg"
    nonisolated static let updatedFromKey = "ni.update.from"
    /// The version whose notice the user closed (✕): not shown again; a newer one is.
    nonisolated static let dismissedKey = "ni2.update.dismissed"
    /// The first look for a new version after launch, and then how often.
    static let firstCheckDelay: Duration = .seconds(60)
    /// Five times a day: one small request to GitHub each time.
    static let checkInterval: Duration = .seconds(24 * 3600 / 5)

    /// A notice in the notch that a new version is out (`UpdateCompact`): from the first check that
    /// finds one until it is installed or closed. While it installs, it stays to show how far.
    var notice: Release? {
        guard let offered, offered.version != dismissedVersion else { return nil }
        return offered
    }
    /// The newest version a check found: it stays offered through later checks that fail (no
    /// network) or are under way, and through an install that failed; until ✕, an installed copy
    /// or a check finding none newer.
    private(set) var offered: Release?
    private(set) var dismissedVersion: String? = UserDefaults.standard.string(forKey: AppUpdater.dismissedKey)
    /// A demo's made-up release (`notchisland://demo/update`): Update does not install it.
    private(set) var isDemo = false
    @ObservationIgnored private var checks: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        if let from = defaults.string(forKey: Self.updatedFromKey) {
            defaults.removeObject(forKey: Self.updatedFromKey)
            if from != current { updatedFrom = from }
        }
    }

    /// Looks for a new version a minute after launch, then five times a day, at background priority
    /// (one small request to GitHub; nothing runs in between).
    func startAutomaticChecks() {
        guard checks == nil else { return }
        checks = Task(priority: .background) { [weak self] in
            var delay = Self.firstCheckDelay
            while !Task.isCancelled {
                do { try await Task.sleep(for: delay, tolerance: delay / 10) } catch { return }
                guard let self else { return }
                // A check already showing its result, or an install under way, is left alone.
                if case .idle = self.state { await self.check() }
                else if case .upToDate = self.state { await self.check() }
                else if case .failed = self.state { await self.check() }
                delay = Self.checkInterval
            }
        }
    }

    /// The notice's ✕: this version is not offered in the notch again (About still has it).
    func dismissNotice() {
        guard let version = notice?.version else { return }
        dismissedVersion = version
        if !isDemo { UserDefaults.standard.set(version, forKey: Self.dismissedKey) }
        if isDemo { endDemo() }
        Log.app.notice("update notice \(version, privacy: .public) closed")
    }

    /// The notice's Update: installs it (a demo's release only logs).
    func installFromNotice() {
        guard let release = notice, !isBusy else { return }
        guard !isDemo else {
            Log.app.notice("demo update: Update pressed")
            return
        }
        Task { await install(release) }
    }

    /// `notchisland://demo/update`: a made-up newer release, to see the notice.
    func injectDemo(_ on: Bool) {
        if on {
            isDemo = true
            dismissedVersion = nil
            let release = Release(version: "9.9.9", diskImage: URL(string: "https://example.invalid/NotchIsland.dmg")!, notes: "")
            state = .available(release)
            offered = release
        } else {
            endDemo()
        }
    }

    private func endDemo() {
        guard isDemo else { return }
        isDemo = false
        dismissedVersion = UserDefaults.standard.string(forKey: Self.dismissedKey)
        state = .idle
        offered = nil
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing, .relaunching: true
        default: false
        }
    }

    func check() async {
        guard !isBusy else { return }
        state = .checking
        do {
            let release = try await Self.latestRelease()
            let isNewer = DiagnosticsVersions.isOlder(current, than: release.version)
            state = isNewer ? .available(release) : .upToDate(release.version)
            if !isDemo { offered = isNewer ? release : nil }
        } catch {
            state = .failed(String(localized: "GitHub could not be reached. Try again later."))
        }
        Log.app.notice("update check: \(String(describing: self.state), privacy: .public)")
    }

    /// Downloads `release`, checks it, puts it in place of this copy and reopens NotchIsland.
    func install(_ release: Release) async {
        guard !isBusy else { return }
        state = .downloading(release, progress: nil)
        DiagnosticsFlow.record("update \(release.version) downloading")
        do {
            let image = try await Self.fetch(release) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .downloading(let shown, _) = self.state, shown == release else { return }
                    self.state = .downloading(release, progress: fraction)
                }
            }
            state = .installing(release, step: String(localized: "Checking the download…"))
            let staged = try await Self.stage(image: image)
            try? FileManager.default.removeItem(at: image)
            switch await Self.verifyInBackground(staged, version: release.version) {
            case .sameSigner:
                try await replace(with: staged, release: release)
            case .otherSigner:
                Log.app.notice("update \(release.version, privacy: .public): signed differently from this copy")
                state = .differentSigner(release, staged: staged)
            case .invalid(let reason):
                try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
                throw UpdateError.invalid(reason)
            }
        } catch UpdateError.invalid(let reason) {
            state = .failed(String(localized: "The download did not pass the check (\(reason)). Nothing was changed."))
            Log.app.error("update rejected: \(reason, privacy: .public)")
        } catch {
            state = .failed(String(localized: "The update could not be installed. Nothing was changed; try again later."))
            Log.app.error("update failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The user accepted a copy signed differently: installed anyway (the permissions are asked
    /// again on its first launch).
    func installAnyway() async {
        guard case .differentSigner(let release, let staged) = state else { return }
        do {
            try await replace(with: staged, release: release)
        } catch {
            state = .failed(String(localized: "The update could not be installed. Nothing was changed; try again later."))
            Log.app.error("update failed: \(String(describing: error), privacy: .public)")
        }
    }

    func cancel() {
        if case .differentSigner(_, let staged) = state {
            try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
        }
        state = .idle
        Task { await check() }
    }

    // MARK: Installing

    private func replace(with staged: URL, release: Release) async throws {
        state = .installing(release, step: String(localized: "Installing…"))
        let target = Self.installLocation()
        let manager = FileManager.default
        do {
            if manager.fileExists(atPath: target.path) {
                // Atomic on one volume: the old copy is swapped out in one step, never half-written.
                _ = try manager.replaceItemAt(target, withItemAt: staged, backupItemName: nil, options: [])
            } else {
                try manager.moveItem(at: staged, to: target)
            }
        } catch {
            // A location this user cannot write to (an admin's /Applications): the old way.
            Log.app.error("update in place failed: \(String(describing: error), privacy: .public)")
            let image = try await Self.fetch(release) { _ in }
            NSWorkspace.shared.open(image)
            state = .manual(release, image)
            return
        }
        try? manager.removeItem(at: staged.deletingLastPathComponent())
        UserDefaults.standard.set(current, forKey: Self.updatedFromKey)
        Log.app.notice("update \(release.version, privacy: .public) installed at \(target.path, privacy: .public)")
        DiagnosticsFlow.record("update \(release.version) installed")
        state = .relaunching(release)
        Self.reopenAfterExit(target)
        try? await Task.sleep(for: .milliseconds(600))
        NSApp.terminate(nil)
    }

    /// Where the new copy goes: in place of this one, unless this one runs from somewhere that
    /// cannot be replaced (a disk image, App Translocation's read-only copy), then Applications.
    nonisolated static func installLocation(bundle: URL = Bundle.main.bundleURL) -> URL {
        let path = bundle.path
        let temporary = path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
        let writable = FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
        if !temporary, writable { return bundle }
        return URL(fileURLWithPath: "/Applications/NotchIsland.app")
    }

    /// A shell that waits for this process to end, then opens the new copy. It outlives the app.
    private static func reopenAfterExit(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
                             "reopen", String(ProcessInfo.processInfo.processIdentifier), app.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: Checking

    nonisolated enum Verdict: Equatable { case sameSigner, otherSigner, invalid(String) }

    /// `verify` off the main thread: checking every sealed file of a whole app takes a while, and
    /// on the main thread macOS flagged it ("should not be called on the main thread as it may lead
    /// to UI unresponsiveness", in the reports' logs at each update).
    @concurrent nonisolated static func verifyInBackground(_ app: URL, version: String) async -> Verdict {
        verify(app, version: version)
    }

    /// The staged copy is NotchIsland, newer, intact (every file sealed by its signature) and,
    /// for `.sameSigner`, satisfies this copy's own designated requirement: the one macOS keys the
    /// permissions on.
    nonisolated static func verify(_ app: URL, version: String) -> Verdict {
        guard let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else { return .invalid("not NotchIsland") }
        let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let staged = info["CFBundleShortVersionString"] as? String ?? "0"
        guard !DiagnosticsVersions.isOlder(staged, than: installed) else { return .invalid("older than this copy") }
        guard let staticCode = staticCode(app) else { return .invalid("unreadable signature") }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess else { return .invalid("broken signature") }
        guard let own = ownRequirement() else { return .otherSigner }
        return SecStaticCodeCheckValidity(staticCode, flags, own) == errSecSuccess ? .sameSigner : .otherSigner
    }

    private nonisolated static func staticCode(_ url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        return SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess ? code : nil
    }

    /// This copy's designated requirement, read from its bundle on disk (an ad-hoc copy has one
    /// that only it satisfies, so every download counts as signed differently).
    private nonisolated static func ownRequirement() -> SecRequirement? {
        guard let code = staticCode(Bundle.main.bundleURL) else { return nil }
        var requirement: SecRequirement?
        return SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess ? requirement : nil
    }

    // MARK: Disk image

    /// Mounts the disk image out of sight, copies the app beside the one it replaces (same volume,
    /// so the swap is a rename) and unmounts it.
    @concurrent nonisolated static func stage(image: URL) async throws -> URL {
        let manager = FileManager.default
        let mount = manager.temporaryDirectory.appendingPathComponent("NotchIsland-update-\(UUID().uuidString)")
        try manager.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: mount) }
        try run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let source = mount.appendingPathComponent("NotchIsland.app")
        guard manager.fileExists(atPath: source.path) else { throw UpdateError.invalid("no NotchIsland.app in the disk image") }
        let folder = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                     appropriateFor: installLocation().deletingLastPathComponent(), create: true)
        let staged = folder.appendingPathComponent("NotchIsland.app")
        // ditto keeps the signature's extended attributes and symlinks exactly.
        try run("/usr/bin/ditto", [source.path, staged.path])
        return staged
    }

    @discardableResult
    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.tool(tool, process.terminationStatus) }
        return process.terminationStatus
    }

    // MARK: GitHub

    nonisolated enum UpdateError: Error { case status(Int), noDiskImage, invalid(String), tool(String, Int32) }

    @concurrent nonisolated static func latestRelease() async throws -> Release {
        var request = URLRequest(url: DiagnosticsBaseline.latestReleaseURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchIsland", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await DiagnosticsNetwork.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { throw UpdateError.status(status) }
        return try release(from: json, tag: tag)
    }

    nonisolated static func release(from json: [String: Any], tag: String) throws -> Release {
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let link = assets.first(where: { $0["name"] as? String == assetName })?["browser_download_url"] as? String,
              let url = URL(string: link) else { throw UpdateError.noDiskImage }
        return Release(version: DiagnosticsVersions.normalized(tag), diskImage: url, notes: json["body"] as? String ?? "")
    }

    /// Into Caches as "NotchIsland <version>.dmg", reporting the fraction downloaded.
    @concurrent nonisolated static func fetch(_ release: Release, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let tracker = DownloadProgress(progress)
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (downloaded, response) = try await session.download(for: URLRequest(url: release.diskImage, timeoutInterval: 120),
                                                                delegate: tracker)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.status(status) }
        let manager = FileManager.default
        let folder = try manager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "NotchIsland", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("NotchIsland \(release.version).dmg")
        try? manager.removeItem(at: target)
        try manager.moveItem(at: downloaded, to: target)
        return target
    }
}

/// Reports a download's progress (the async `download(for:delegate:)` calls it per chunk).
nonisolated private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let report: @Sendable (Double) -> Void

    init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        report(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
