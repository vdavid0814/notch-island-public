import AppKit
import SwiftUI

/// Content of the menu bar extra (native `.menu` style, so it renders as a real `NSMenu`).
struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model

    /// Minutes offered under Start Timer.
    nonisolated static let timerPresets = [1, 5, 10, 15, 25, 45]

    var body: some View {
        Button("Open Island", systemImage: "capsule.tophalf.filled") {
            model.perform(.open(nil))
        }
        // Renders as a checkmark item; the pin is otherwise only reachable inside the island.
        Toggle("Keep Island Open", systemImage: "pin", isOn: pinned)

        Divider()

        Menu("Start Timer", systemImage: "timer") {
            ForEach(Self.timerPresets, id: \.self) { minutes in
                Button(Self.timerTitle(minutes: minutes)) {
                    model.perform(.startTimer(minutes: Double(minutes)))
                }
            }
        }
        if model.timers.isCountdownActive {
            Button("Cancel Timer", systemImage: "xmark.circle") {
                model.perform(.cancelTimer)
            }
        }
        Button("Stopwatch", systemImage: "stopwatch") {
            model.perform(.startStopwatch)
        }

        // Only with something to control: transport items for an empty player would do nothing.
        if model.preferences.showNowPlaying, model.media.item != nil {
            Menu("Now Playing", systemImage: "music.note") {
                Button(
                    model.media.isPlaying ? "Pause" : "Play",
                    systemImage: model.media.isPlaying ? "pause.fill" : "play.fill"
                ) {
                    model.perform(.media(.togglePlayPause))
                }
                Button("Next", systemImage: "forward.fill") {
                    model.perform(.media(.next))
                }
                Button("Previous", systemImage: "backward.fill") {
                    model.perform(.media(.previous))
                }
            }
        }

        Divider()

        Button("Customize Island…", systemImage: "square.grid.3x2") {
            model.perform(.customize)
        }

        Button("Settings…", systemImage: "gearshape") {
            model.perform(.showSettings)
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit NotchIsland") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Routed through the island controller, which owns the pin policy, instead of writing
    /// `island.isPinned` directly.
    private var pinned: Binding<Bool> {
        Binding(
            get: { model.island.isPinned },
            set: { newValue in
                if newValue != model.island.isPinned { model.perform(.togglePin) }
            }
        )
    }

    /// "1 minute", "5 minutes" — Foundation's unit formatter handles plural rules for every locale.
    nonisolated static func timerTitle(minutes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(minutes * 60).formatted(
            Duration.UnitsFormatStyle(allowedUnits: [.minutes], width: .wide).locale(locale)
        )
    }
}
