import AppKit
import Observation
import ScreenCaptureKit

/// Records the screen the island is on to a movie, from the Screen Recording widget (or
/// `notchisland://record`): the whole display with the pointer, without the island itself, saved
/// where macOS's Screenshot app saves (the Desktop unless it was changed there), named as it names
/// its recordings.
///
/// Only with Screen Recording (asked for the first time). The stream runs only while recording, and
/// ScreenCaptureKit writes the movie itself (`SCRecordingOutput`): no frame passes through the app.
/// While it records, the island shows it round the notch (`RecordingCompact`), and the pointer over
/// the notch brings up the time and Stop (`RecordingCard`).
@Observable final class ScreenRecorder {
    nonisolated enum State: Equatable, Sendable {
        case idle
        /// Asked to start: the stream is being set up.
        case starting
        case recording(since: Date)
    }

    private(set) var state: State = .idle

    var isRecording: Bool {
        if case .recording = state { true } else { false }
    }

    /// When the recording began, while it lasts.
    var startedAt: Date? {
        if case .recording(let since) = state { since } else { nil }
    }

    /// The last movie written.
    private(set) var lastMovie: URL?

    /// A recording ended, by Stop or by the system.
    @ObservationIgnored var onStop: (() -> Void)?
    /// A recording began (the last one's thumbnail goes).
    @ObservationIgnored var onStart: (() -> Void)?
    /// The movie is written and closed, recorded on that display (its thumbnail comes up there).
    @ObservationIgnored var onSaved: ((URL, CGDirectDisplayID) -> Void)?

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var watch: RecordingWatch?
    @ObservationIgnored private var output: SCRecordingOutput?
    @ObservationIgnored private var generation = 0

    static let frameRate: Int32 = 60

    func toggle(display: CGDirectDisplayID?) {
        switch state {
        case .idle: start(display: display)
        case .starting: break
        case .recording: stop()
        }
    }

    /// Starts recording `display` (nil: the main one). Without Screen Recording, asks for it: the
    /// system's prompt the first time, System Settings after a no.
    func start(display: CGDirectDisplayID?) {
        guard state == .idle else { return }
        guard CGPreflightScreenCaptureAccess() else {
            Log.recording.notice("no Screen Recording permission: asking")
            if !CGRequestScreenCaptureAccess(),
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        state = .starting
        generation += 1
        let generation = generation
        let url = Self.newMovieURL()
        let displayID = display ?? CGMainDisplayID()
        onStart?()
        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let screen = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                    throw RecordingError.noDisplay
                }
                // The island (and Settings) are the app's own windows: left out of the movie.
                let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: screen, excludingApplications: own, exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                let scale = CGFloat(filter.pointPixelScale)
                configuration.width = Int((filter.contentRect.width * scale).rounded())
                configuration.height = Int((filter.contentRect.height * scale).rounded())
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: Self.frameRate)
                configuration.showsCursor = true
                configuration.queueDepth = 6
                let recording = SCRecordingOutputConfiguration()
                recording.outputURL = url
                recording.outputFileType = .mov
                recording.videoCodecType = .hevc
                let watch = RecordingWatch(
                    stopped: { [weak self] in self?.stoppedBySystem(generation: generation) },
                    finished: { [weak self] in self?.finished(url, display: displayID, generation: generation) })
                let output = SCRecordingOutput(configuration: recording, delegate: watch)
                let stream = SCStream(filter: filter, configuration: configuration, delegate: watch)
                try stream.addRecordingOutput(output)
                try await stream.startCapture()
                guard let self, self.generation == generation, self.state == .starting else {
                    try? await stream.stopCapture()
                    return
                }
                self.stream = stream
                self.watch = watch
                self.output = output
                self.state = .recording(since: .now)
                Log.recording.notice("recording display \(displayID, privacy: .public) to \(url.lastPathComponent, privacy: .public)")
            } catch {
                Log.recording.error("could not start: \(error.localizedDescription, privacy: .public)")
                guard let self, self.generation == generation else { return }
                self.state = .idle
            }
        }
    }

    /// Ends the recording: the movie is finished and closed on disk a moment later.
    func stop() {
        guard state != .idle else { return }
        let stream = stream
        self.stream = nil
        state = .idle
        if let stream {
            Task { try? await stream.stopCapture() }
        } else {
            // Starting (or a demo recording): nothing was captured yet.
            generation += 1
        }
        onStop?()
    }

    /// A recording that is only shown (`demo/recording`): the island's indicator and card, without
    /// a stream or a permission.
    func demo(_ on: Bool) {
        guard stream == nil else { return }
        if on {
            state = .recording(since: Date.now.addingTimeInterval(-83))
        } else if state != .idle {
            stop()
        }
    }

    /// macOS ended the stream (its own Stop in the menu bar, the display gone).
    private func stoppedBySystem(generation: Int) {
        guard generation == self.generation, stream != nil else { return }
        Log.recording.notice("the system stopped the recording")
        stream = nil
        state = .idle
        onStop?()
    }

    private func finished(_ url: URL, display: CGDirectDisplayID, generation: Int) {
        Log.recording.notice("saved \(url.lastPathComponent, privacy: .public)")
        lastMovie = url
        onSaved?(url, display)
        if generation == self.generation {
            watch = nil
            output = nil
        }
    }

    // MARK: Where

    /// Where the Screenshot app saves (`com.apple.screencapture` `location`), else the Desktop, named
    /// as it names a recording ("Screen Recording 2026-10-08 at 21.58.03.mov").
    nonisolated static func newMovieURL(now: Date = .now) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Screen Recording \(formatter.string(from: now)).mov"
        return saveDirectory().appendingPathComponent(name)
    }

    nonisolated static func saveDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let path = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }

    nonisolated enum RecordingError: Error {
        case noDisplay
    }
}

/// Hears the stream end without being asked to, and the movie being finished.
nonisolated final class RecordingWatch: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
    private let stopped: @MainActor @Sendable () -> Void
    private let finished: @MainActor @Sendable () -> Void

    init(stopped: @escaping @MainActor @Sendable () -> Void, finished: @escaping @MainActor @Sendable () -> Void) {
        self.stopped = stopped
        self.finished = finished
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let stopped = stopped
        Task { @MainActor in stopped() }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let finished = finished
        Task { @MainActor in finished() }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Log.recording.error("the movie failed: \(error.localizedDescription, privacy: .public)")
    }
}
