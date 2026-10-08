import AppKit
import Observation
import ScreenCaptureKit

/// Records the screen the island is on to a movie, from the Screen Recording widget (or
/// `notchisland://record`): the whole display with the pointer, without the island itself, saved
/// where macOS's Screenshot app saves (the Desktop unless it was changed there), named as it names
/// its recordings.
///
/// Only with Screen Recording (asked for the first time). The stream runs only while recording, in
/// a process of its own (`RecordingHelper`), and ScreenCaptureKit writes the movie itself
/// (`SCRecordingOutput`): no frame passes through the app.
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

    /// The process recording (`RecordingHelper`), and its input (`stop`).
    @ObservationIgnored private var helper: Process?
    @ObservationIgnored private var helperInput: FileHandle?
    @ObservationIgnored private var generation = 0

    static let frameRate: Int32 = 60

    func toggle(display: CGDirectDisplayID?) {
        switch state {
        case .idle: start(display: display)
        case .starting: break
        case .recording: stop()
        }
    }

    /// Starts recording `display` (nil: the main one), in a process of its own (`RecordingHelper`:
    /// macOS's Stop in the menu bar goes when that process ends). Without Screen Recording, asks
    /// for it: the system's prompt the first time, System Settings after a no.
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
        guard let executable = Bundle.main.executableURL else { return }
        state = .starting
        generation += 1
        let generation = generation
        let url = Self.newMovieURL()
        let displayID = display ?? CGMainDisplayID()
        onStart?()
        let process = Process()
        process.executableURL = executable
        process.arguments = [RecordingHelper.flag, String(displayID), url.path, String(ProcessInfo.processInfo.processIdentifier)]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let line = String(line)
                Task { @MainActor [weak self] in self?.heard(line, url: url, display: displayID, generation: generation) }
            }
        }
        process.terminationHandler = { _ in
            Task { @MainActor [weak self] in self?.helperEnded(generation: generation) }
        }
        do {
            try process.run()
            helper = process
            helperInput = input.fileHandleForWriting
            Log.recording.notice("recording display \(displayID, privacy: .public) to \(url.lastPathComponent, privacy: .public)")
        } catch {
            Log.recording.error("could not start the helper: \(error.localizedDescription, privacy: .public)")
            state = .idle
        }
    }

    /// Ends the recording: the helper closes the movie a moment later and quits.
    func stop() {
        guard state != .idle else { return }
        state = .idle
        if let helperInput {
            helperInput.write(Data("stop\n".utf8))
            try? helperInput.close()
            self.helperInput = nil
        } else {
            // A demo recording: nothing was captured.
            generation += 1
        }
        onStop?()
    }

    /// A recording that is only shown (`demo/recording`): the island's indicator and card, without
    /// a helper or a permission.
    func demo(_ on: Bool) {
        guard helper == nil else { return }
        if on {
            state = .recording(since: Date.now.addingTimeInterval(-83))
        } else if state != .idle {
            stop()
        }
    }

    /// A line from the helper.
    private func heard(_ line: String, url: URL, display: CGDirectDisplayID, generation: Int) {
        switch line {
        case "started":
            guard generation == self.generation, state == .starting else { return }
            state = .recording(since: .now)
        case "saved":
            Log.recording.notice("saved \(url.lastPathComponent, privacy: .public)")
            lastMovie = url
            onSaved?(url, display)
        case "stopped":
            // macOS ended it (its own Stop in the menu bar, the display gone).
            guard generation == self.generation, state != .idle else { return }
            Log.recording.notice("the system stopped the recording")
            state = .idle
            onStop?()
        default:
            if line.hasPrefix("error") { Log.recording.error("could not start: \(line, privacy: .public)") }
        }
    }

    /// The helper quit (the movie written, or it failed): a recording still shown as going ends.
    private func helperEnded(generation: Int) {
        guard generation == self.generation else { return }
        helper = nil
        helperInput = nil
        if state != .idle {
            state = .idle
            onStop?()
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
        // For checking a recording without leaving it on the user's Desktop.
        if let folder = ProcessInfo.processInfo.environment["NI_RECORDING_DIR"], !folder.isEmpty {
            return URL(fileURLWithPath: folder, isDirectory: true)
        }
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
