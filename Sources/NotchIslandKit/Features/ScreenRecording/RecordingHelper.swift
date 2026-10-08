import AppKit
import ScreenCaptureKit

/// The recording itself, in a process of its own: the app's executable started again as
/// `NotchIsland --record-screen <display> <movie path> <app pid>` (`ScreenRecorder`).
///
/// macOS keeps its Stop in the menu bar for as long as the process that recorded the screen runs
/// (`replayd` drops it only when that process's connection ends), so recorded from the app itself
/// it stayed there after the first recording until the app quit. The helper quits as soon as the
/// movie is written, and the Stop goes with it. It is the app's own executable, so Screen
/// Recording (asked for by the app) is its too.
///
/// It talks over its standard input and output, a line each: it writes `started`, then `saved`
/// once the movie is closed (or `stopped` when the system ended it, `error <why>` when it could not
/// start); `stop` on its input — or the input closing, the app gone — ends the recording.
public enum RecordingHelper {
    public static let flag = "--record-screen"

    /// Runs the helper when the process was started as one; returns otherwise.
    public static func runIfAsked() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.count >= index + 4,
              let display = UInt32(arguments[index + 1]), let app = Int32(arguments[index + 3]) else { return }
        let url = URL(fileURLWithPath: arguments[index + 2])
        MainActor.assumeIsolated {
            let session = HelperSession(display: display, url: url, app: app)
            session.start()
            RunLoop.main.run()
        }
        exit(0)
    }
}

@MainActor private final class HelperSession {
    let display: CGDirectDisplayID
    let url: URL
    let app: pid_t
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var watch: RecordingWatch?
    private var isStopping = false

    init(display: CGDirectDisplayID, url: URL, app: pid_t) {
        self.display = display
        self.url = url
        self.app = app
    }

    func start() {
        listen()
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let screen = content.displays.first(where: { $0.displayID == display }) ?? content.displays.first else {
                    Self.fail("no display")
                }
                // The island (and Settings) are the app's windows: left out of the movie.
                let own = content.applications.filter { $0.processID == app }
                let filter = SCContentFilter(display: screen, excludingApplications: own, exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                let scale = CGFloat(filter.pointPixelScale)
                configuration.width = Int((filter.contentRect.width * scale).rounded())
                configuration.height = Int((filter.contentRect.height * scale).rounded())
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: ScreenRecorder.frameRate)
                configuration.showsCursor = true
                configuration.queueDepth = 6
                let recording = SCRecordingOutputConfiguration()
                recording.outputURL = url
                recording.outputFileType = .mov
                recording.videoCodecType = .hevc
                let watch = RecordingWatch(stopped: { [weak self] in self?.stoppedBySystem() },
                                           finished: { Self.say("saved"); exit(0) })
                let output = SCRecordingOutput(configuration: recording, delegate: watch)
                let stream = SCStream(filter: filter, configuration: configuration, delegate: watch)
                try stream.addRecordingOutput(output)
                try await stream.startCapture()
                self.stream = stream
                self.output = output
                self.watch = watch
                Self.say("started")
                // Asked to stop while it was starting.
                if isStopping { stop() }
            } catch {
                Self.fail(error.localizedDescription)
            }
        }
    }

    /// `stop` on the input, or the input closing (the app quit or crashed): the recording ends.
    private func listen() {
        FileHandle.standardInput.readabilityHandler = { handle in
            let data = handle.availableData
            let text = String(decoding: data, as: UTF8.self)
            guard data.isEmpty || text.contains("stop") else { return }
            handle.readabilityHandler = nil
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    private func stop() {
        isStopping = true
        guard let stream else { return }
        self.stream = nil
        Task {
            try? await stream.stopCapture()
            // The movie is closed in `recordingOutputDidFinishRecording`; should that never come,
            // the helper does not linger.
            try? await Task.sleep(for: .seconds(10))
            exit(0)
        }
    }

    private func stoppedBySystem() {
        guard stream != nil else { return }
        stream = nil
        Self.say("stopped")
        Task {
            try? await Task.sleep(for: .seconds(10))
            exit(0)
        }
    }

    private static func fail(_ why: String) -> Never {
        say("error \(why.replacingOccurrences(of: "\n", with: " "))")
        exit(1)
    }

    nonisolated static func say(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
