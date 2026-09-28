import AppKit

/// The sleep/lock edges that decide whether anything of ours should exist on screen.
///
/// Pure so the suspension rule is testable. The flags are kept independently rather than as one
/// "asleep" bool because the edges interleave: the display can sleep, then the system, and a
/// maintenance (dark) wake brings the system back while the screens stay dark and locked.
nonisolated struct ActivitySignals: Sendable, Equatable {
    nonisolated enum Edge: Sendable, CaseIterable {
        case screensDidSleep, screensDidWake
        case sessionDidResignActive, sessionDidBecomeActive
        case systemWillSleep, systemDidWake
        case screenLocked, screenUnlocked
    }

    var screensAsleep = false
    var sessionInactive = false
    var systemSleeping = false
    /// The lock screen is up. It draws above the island's window level, so the island would only
    /// keep media sources and a key interceptor busy behind it (and hide the system HUD from the
    /// user at the lock screen).
    var screenLocked = false

    var isSuspended: Bool { screensAsleep || sessionInactive || systemSleeping || screenLocked }

    mutating func apply(_ edge: Edge) {
        switch edge {
        case .screensDidSleep: screensAsleep = true
        case .screensDidWake: screensAsleep = false
        case .sessionDidResignActive: sessionInactive = true
        case .sessionDidBecomeActive: sessionInactive = false
        case .systemWillSleep: systemSleeping = true
        case .systemDidWake: systemSleeping = false
        case .screenLocked: screenLocked = true
        case .screenUnlocked: screenLocked = false
        }
    }
}

/// System conditions the app adapts to: suspension (order the island out, pause media sources),
/// Low Power Mode, thermal pressure and Reduce Motion. Everything is pushed by notifications.
@Observable final class SystemActivity {
    /// Screens asleep, session switched away (fast user switching), screen locked, or system going
    /// to sleep.
    private(set) var isSuspended = false
    private(set) var isLowPowerMode: Bool
    /// `ProcessInfo.thermalState` is `.serious` or worse: the system is already shedding work.
    private(set) var isThermallyConstrained: Bool
    /// Mirrors `NSWorkspace.accessibilityDisplayShouldReduceMotion`, updated on change.
    private(set) var reduceMotion: Bool

    var prefersReducedWork: Bool { isLowPowerMode || isThermallyConstrained }

    /// Why it is (or is not) suspended, for diagnostics.
    var diagnosticsSignals: String { String(describing: signals) }

    @ObservationIgnored private var signals = ActivitySignals()
    @ObservationIgnored private let tokens = NotificationTokens()
    @ObservationIgnored private var lockRelays: [DistributedNotificationRelay] = []

    /// Reads the current values (plain queries, no observation) so views see correct flags even
    /// before `start()`.
    init() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        isThermallyConstrained = Self.isConstrained(ProcessInfo.processInfo.thermalState)
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func start() {
        guard tokens.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let edges: [(Notification.Name, ActivitySignals.Edge)] = [
            (NSWorkspace.screensDidSleepNotification, .screensDidSleep),
            (NSWorkspace.screensDidWakeNotification, .screensDidWake),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionDidResignActive),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionDidBecomeActive),
            (NSWorkspace.willSleepNotification, .systemWillSleep),
            (NSWorkspace.didWakeNotification, .systemDidWake),
        ]
        for (name, edge) in edges {
            tokens.observe(name, on: workspace) { [weak self] in self?.receive(edge) }
        }
        tokens.observe(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, on: workspace) { [weak self] in
            self?.readDisplayOptions()
        }
        tokens.observe(.NSProcessInfoPowerStateDidChange, on: .default) { [weak self] in
            self?.readPowerState()
        }
        tokens.observe(ProcessInfo.thermalStateDidChangeNotification, on: .default) { [weak self] in
            self?.readPowerState()
        }
        // Lock/unlock has no NSWorkspace notification; these distributed names are what loginwindow
        // posts (long-standing, used by Apple's own agents). The relay delivers them immediately
        // even though an accessory app is practically never active.
        lockRelays = [
            DistributedNotificationRelay(name: Notification.Name("com.apple.screenIsLocked")) { [weak self] in
                self?.receive(.screenLocked)
            },
            DistributedNotificationRelay(name: Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
                self?.receive(.screenUnlocked)
            },
        ]
        if Self.isScreenLockedNow() { receive(.screenLocked) }
        readPowerState()
        readDisplayOptions()
    }

    func stop() {
        tokens.removeAll()
        lockRelays.forEach { $0.invalidate() }
        lockRelays.removeAll()
        // A stopped monitor must not leave the app believing it is suspended forever.
        signals = ActivitySignals()
        if isSuspended { isSuspended = false }
    }

    private func receive(_ edge: ActivitySignals.Edge) {
        signals.apply(edge)
        let suspended = signals.isSuspended
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        Log.system.notice("suspended: \(suspended, privacy: .public) after \(String(describing: edge), privacy: .public)")
    }

    private func readPowerState() {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let constrained = Self.isConstrained(ProcessInfo.processInfo.thermalState)
        if lowPower != isLowPowerMode {
            isLowPowerMode = lowPower
            Log.system.notice("low power mode: \(lowPower, privacy: .public)")
        }
        if constrained != isThermallyConstrained {
            isThermallyConstrained = constrained
            Log.system.notice("thermally constrained: \(constrained, privacy: .public)")
        }
    }

    private func readDisplayOptions() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduce != reduceMotion { reduceMotion = reduce }
    }

    /// Seeds the lock flag at start (the app can be relaunched while the screen is locked, e.g. by
    /// launchd after a crash). `CGSSessionScreenIsLocked` is only present in the session dictionary
    /// while the lock screen is up.
    private static func isScreenLockedNow() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    nonisolated static func isConstrained(_ state: ProcessInfo.ThermalState) -> Bool {
        switch state {
        case .serious, .critical: true
        case .nominal, .fair: false
        @unknown default: true
        }
    }
}
