import AppKit
import Observation

/// The screens connected now, and a word when a monitor is plugged in (the notice that asks which
/// screen the island goes on, `BannerKind.displays`).
///
/// Pushed by the system only (screen-parameter changes, wake): no timer. A connection settles over
/// a few notifications — the screen comes, is resized, gets its menu bar — so the list is read again
/// a moment after the last one.
@Observable final class DisplayCenter {
    /// In menu-bar order (the first owns the menu bar).
    private(set) var screens: [ScreenCandidate] = []

    /// A monitor was connected while another screen was there already: the screens to choose from.
    @ObservationIgnored var onConnected: ((ScreenCandidate) -> Void)?

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private let settle = DelayedAction()
    /// Until then a monitor coming back is the Mac waking with it, not someone plugging it in.
    @ObservationIgnored private var quietUntil: ContinuousClock.Instant?

    /// How long the screens are let settle after a change before they are read.
    static let settleDelay: TimeInterval = 0.7
    /// After a wake, monitors come back by themselves for this long.
    static let wakeQuiet: Duration = .seconds(15)

    var isStarted: Bool { !observers.isEmpty }

    func start() {
        guard observers.isEmpty else { return }
        refresh(announces: false)
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.quietUntil = .now + Self.wakeQuiet }
            })
        }
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        settle.cancel()
    }

    private func screensChanged() {
        settle.schedule(after: Self.settleDelay) { [weak self] in self?.refresh(announces: true) }
    }

    /// Reads the screens again; with `announces`, a monitor that was not there before is told about.
    func refresh(announces: Bool) {
        // A monitor that was not there at the last reading (one there at launch is not news).
        let known = Set(screens.map(\.id.key))
        let next = ScreenLocator.candidates()
        if next != screens { screens = next }
        let fresh = IslandScreenPicker.connected(next, since: known)
        let isQuiet = quietUntil.map { ContinuousClock.now < $0 } ?? false
        guard announces, !isQuiet, next.count > 1, let monitor = fresh.first else { return }
        Log.window.notice("display connected: \(monitor.id.name, privacy: .public) (\(next.count, privacy: .public) screens)")
        onConnected?(monitor)
    }
}
