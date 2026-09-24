import Foundation
import SwiftUI

/// Runs `notchisland://demo/…`: injects fake state so every island presentation can be shown and
/// screenshotted on demand, and takes all of it back out on `demo/reset`.
///
/// It remembers exactly what it injected (shelf items it added, the countdown it started, whether
/// fake level readings are in place) so a reset restores the real state without touching anything
/// the user did in between.
@MainActor final class DemoDirector {
    /// How long the fake drag of `demo/drop` stays "in flight".
    static let dropDuration: Duration = .seconds(4)
    /// `demo/timerdone` starts a countdown this short and lets it finish for real.
    static let timerDuration: TimeInterval = 3

    /// Read-only system images: they exist on every Mac and, unlike `~/Desktop`, reading them
    /// triggers no privacy prompt.
    private static let picturesDirectory = URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true)

    private var dropTask: Task<Void, Never>?
    private var isDropActive = false
    private var demoCountdown: CountdownState?
    private var demoShelfIDs: Set<ShelfItem.ID> = []
    private var injectedLevels = false

    func run(_ command: DemoCommand, model: AppModel) {
        switch command {
        case .media:
            model.media.injectDemo(Self.demoTrack(), playing: true)
        case .charging:
            model.power.injectDemo(.demo(level: 76, charging: true, minutes: 72), event: .connected)
        case .unplug:
            model.power.injectDemo(.demo(level: 76, charging: false, minutes: 312), event: .disconnected)
        case .low:
            model.power.injectDemo(.demo(level: 9, charging: false, minutes: 38), event: .low(threshold: 10))
        case .volume(let value):
            injectedLevels = true
            model.levels.injectDemo(.volume, value: value)
        case .brightness(let value):
            injectedLevels = true
            model.levels.injectDemo(.brightness, value: value)
        case .timerDone:
            model.timers.start(duration: Self.timerDuration)
            demoCountdown = model.timers.countdown
        case .drop:
            beginDrop(model)
        case .shelf:
            addShelfSamples(model)
        case .reset:
            reset(model)
        case .hover(let inside):
            model.controller.simulatePointer(inside: inside)
        case .state:
            model.logIslandState()
        case .airPods:
            model.airPodsConnected(.demo)
        case .siriApps:
            model.controller.openAssistant()
            model.assistant.open(.applications)
        case .timerUnit:
            NotificationCenter.default.post(name: .demoNextTimerUnit, object: nil)
        case .surface(let style):
            withAnimation(.spring(duration: 0.25)) { model.preferences.glassStyle = style }
        }
    }

    /// Called when the app stops: nothing may fire into a stopped model.
    func cancel() {
        dropTask?.cancel()
        dropTask = nil
    }

    private func beginDrop(_ model: AppModel) {
        dropTask?.cancel()
        if !isDropActive {
            isDropActive = true
            model.controller.externalDragBegan()
        }
        dropTask = Task { [weak self, weak model] in
            do { try await Task.sleep(for: Self.dropDuration) } catch { return }
            guard let self, let model else { return }
            self.endDrop(model)
        }
    }

    private func endDrop(_ model: AppModel) {
        dropTask = nil
        guard isDropActive else { return }
        isDropActive = false
        model.controller.externalDragEnded()
    }

    private func addShelfSamples(_ model: AppModel) {
        let before = Set(model.shelf.items.map(\.id))
        model.shelf.add(Self.sampleFiles())
        // Only items that were not on the shelf already belong to the demo (add() de-duplicates).
        demoShelfIDs.formUnion(model.shelf.items.map(\.id).filter { !before.contains($0) })
        model.controller.expand(page: .shelf, pinned: false, userInitiated: true)
    }

    private func reset(_ model: AppModel) {
        dropTask?.cancel()
        endDrop(model)
        model.media.injectDemo(nil, playing: false)
        model.power.injectDemo(nil, event: nil)
        if injectedLevels {
            injectedLevels = false
            // Silent and in place: restarting the level services here used to report the first
            // real reading as an external change, i.e. a volume banner out of a reset.
            model.levels.endDemo()
        }
        if let demoCountdown, model.timers.countdown == demoCountdown {
            model.timers.cancel()
        }
        demoCountdown = nil
        if case .finished = model.timers.countdown {
            model.timers.acknowledge()
        }
        for id in demoShelfIDs {
            model.shelf.remove(id)
        }
        demoShelfIDs.removeAll()
        model.banners.dismiss()
        model.controller.collapse()
    }

    /// A made-up track whose artwork is one of the square desktop-picture thumbnails (356 px HEIC,
    /// ~30 KB — the size real album art arrives in).
    private static func demoTrack() -> NowPlayingItem {
        let thumbnails = picturesDirectory.appending(path: ".thumbnails", directoryHint: .isDirectory)
        let artwork = images(in: thumbnails).first.flatMap { try? Data(contentsOf: $0) }
        return NowPlayingItem(
            title: "Island Lights",
            artist: "The Notches",
            album: "Liquid Glass",
            duration: 214,
            artworkData: artwork,
            bundleIdentifier: "com.apple.Music"
        )
    }

    private static func sampleFiles() -> [URL] {
        Array(images(in: picturesDirectory).prefix(4))
    }

    private static func images(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "heic" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

private extension PowerState {
    static func demo(level: Int, charging: Bool, minutes: Int) -> PowerState {
        PowerState(
            hasBattery: true,
            level: level,
            isCharging: charging,
            isPluggedIn: charging,
            isCharged: false,
            minutesRemaining: minutes,
            isLowPowerMode: false
        )
    }
}

extension Notification.Name {
    /// `demo/timerunit`: the timer widget switches its ruler's unit, as a tap on the marker does.
    static let demoNextTimerUnit = Notification.Name("com.davidvarga.notchisland.demo.nextTimerUnit")
}
