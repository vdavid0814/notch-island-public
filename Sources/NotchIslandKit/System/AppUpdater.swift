import AppKit
import Foundation

/// The newest version, from About: looked up on GitHub, its disk image downloaded into Downloads
/// and opened, so the user drags it onto Applications and replaces the old copy — without going
/// to GitHub. The download is marked as downloaded from the web, as a browser marks it, so macOS
/// checks it exactly as before (the app replaces nothing itself).
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
        case downloading(Release)
        /// Downloaded and opened: the user replaces the app, after quitting this one.
        case ready(Release, URL)
        case failed(String)
    }

    private(set) var state: State = .idle
    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    nonisolated static let assetName = "NotchIsland.dmg"

    var isBusy: Bool {
        switch state {
        case .checking, .downloading: true
        default: false
        }
    }

    func check() async {
        guard !isBusy else { return }
        state = .checking
        do {
            let release = try await Self.latestRelease()
            state = DiagnosticsVersions.isOlder(current, than: release.version) ? .available(release) : .upToDate(release.version)
        } catch {
            state = .failed(String(localized: "GitHub could not be reached. Try again later."))
        }
        Log.app.notice("update check: \(String(describing: self.state), privacy: .public)")
    }

    /// Downloads `release` into Downloads and opens it.
    func download(_ release: Release) async {
        guard !isBusy else { return }
        state = .downloading(release)
        DiagnosticsFlow.record("update \(release.version) downloading")
        do {
            let file = try await Self.fetch(release)
            NSWorkspace.shared.open(file)
            state = .ready(release, file)
            Log.app.notice("update \(release.version, privacy: .public) downloaded")
        } catch {
            state = .failed(String(localized: "The download failed. Try again later."))
            Log.app.error("update download failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: GitHub

    nonisolated enum UpdateError: Error { case status(Int), noDiskImage }

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

    /// Into Downloads as "NotchIsland <version>.dmg" (a number added if that name is taken), marked
    /// as a web download.
    @concurrent nonisolated static func fetch(_ release: Release) async throws -> URL {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (downloaded, response) = try await session.download(for: URLRequest(url: release.diskImage, timeoutInterval: 120))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.status(status) }
        let manager = FileManager.default
        let folder = manager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        var target = folder.appendingPathComponent("NotchIsland \(release.version).dmg")
        var index = 2
        while manager.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("NotchIsland \(release.version) (\(index)).dmg")
            index += 1
        }
        try manager.moveItem(at: downloaded, to: target)
        // As a browser marks what it downloads: macOS checks the app in it as before.
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineAgentNameKey as String: "NotchIsland",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineDataURLKey as String: release.diskImage,
        ]
        try? target.setResourceValues(values)
        return target
    }
}
