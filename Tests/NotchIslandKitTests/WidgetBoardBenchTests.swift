import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

/// The home board's cost as the panel pays it: the standard board with a song playing (no cover:
/// the player's icon stands in), hosted off screen in the island's live mode, built, laid out and drawn afresh (an opening of the panel), and
/// one update that changes nothing the widgets' styles draw (play ↔ pause). Prints the process's
/// instructions retired (steady whichever core runs it and whatever else the Mac is doing) and the
/// main thread's CPU milliseconds, the median of `rounds`. A benchmark, not a check: only with
/// NI_BENCH=1.
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["NI_BENCH"] == "1", "a benchmark: NI_BENCH=1"))
struct WidgetBoardBenchTests {
    static let rounds = 150

    @Test func homeBoardOpeningAndUpdate() {
        let model = AppModel()
        let song = NowPlayingItem(title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming", duration: 243,
                                  artworkData: nil, bundleIdentifier: "com.apple.Music")
        model.media.injectDemo(song, playing: true)
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard)
        let size = WidgetsSettingsPage.boardSize(layout)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)

        // NI_BENCH_WIDGET=i: the standard board's i-th widget alone.
        let board = ProcessInfo.processInfo.environment["NI_BENCH_WIDGET"].flatMap(Int.init)
            .map { WidgetBoard(widgets: [WidgetBoard.standard.widgets[$0]]) } ?? .standard
        func host() -> NSView {
            NSHostingView(rootView: WidgetBoardView(board: board, thumbnails: ThumbnailCache())
                .frame(width: size.width, height: size.height)
                .environment(model)
                .environment(\.colorScheme, .dark))
        }
        func drawn(_ view: NSView) {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
        }
        func instructions() -> UInt64 {
            var usage = rusage_info_v4()
            _ = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
            }
            return usage.ri_instructions
        }
        /// Millions of instructions and milliseconds of CPU.
        func cost(_ work: () -> Void) -> (Double, Double) {
            let (count, time) = (instructions(), clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID))
            work()
            return (Double(instructions() - count) / 1e6, Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - time) / 1e6)
        }

        // Warm: the first build pays for type metadata and fonts once.
        for _ in 0..<5 {
            let view = host()
            window.contentView = view
            view.frame = CGRect(origin: .zero, size: size)
            drawn(view)
        }
        var openings: [(Double, Double)] = []
        for _ in 0..<Self.rounds {
            openings.append(cost {
                let view = host()
                window.contentView = view
                view.frame = CGRect(origin: .zero, size: size)
                drawn(view)
            })
        }
        let view = window.contentView!
        var updates: [(Double, Double)] = []
        for round in 0..<Self.rounds {
            model.media.injectDemo(song, playing: round % 2 == 1)
            updates.append(cost {
                view.needsLayout = true
                drawn(view)
            })
        }
        window.contentView = nil
        func report(_ name: String, _ values: [(Double, Double)]) -> String {
            let (counts, times) = (values.map(\.0).sorted(), values.map(\.1).sorted())
            return "\(name) \(String(format: "%.2f", counts[counts.count / 2])) M instructions, \(String(format: "%.3f", times[times.count / 2])) ms"
        }
        print("BENCH home board: \(report("opening", openings)); \(report("play/pause update", updates))")
    }
}
