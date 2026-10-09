import AppKit
import ApplicationServices

/// Accessibility trust, observed live.
///
/// Replacing the system volume/brightness HUD needs an event tap, and an event tap needs the app to
/// be trusted for Accessibility. Nothing pushes "you are now trusted" to the app directly, so the
/// centre listens for the system-wide `com.apple.accessibility.api` distributed notification (posted
/// whenever the Accessibility list changes) and re-reads `AXIsProcessTrusted()`.
@Observable final class PermissionCenter {
    private(set) var accessibilityTrusted = false
    /// Input Monitoring (`ListenEvent`): on macOS 27 a keyboard event tap (⌘Space) is refused
    /// without it, even with Accessibility allowed (seen in reports).
    private(set) var inputMonitoringAllowed = false
    /// Accessibility or Input Monitoring changed: refused key taps are tried again.
    @ObservationIgnored var onChange: (() -> Void)?
    /// The key taps (⌘Space, volume/brightness keys) stay off: a Reset of Accessibility or Input
    /// Monitoring is under way. A filtering tap left in place as its permission goes stalls every
    /// key and click on the Mac (Reset froze it until a restart, v0.8.1; the log showed the media
    /// key tap timing out 10 s after the reset). Let go once the permission is back, after it was
    /// seen gone.
    private(set) var keyTapsHeld = false
    /// Called as the hold starts, before the permission is touched: the taps go at once.
    @ObservationIgnored var onHoldKeyTaps: (() -> Void)?
    @ObservationIgnored private var heldFor: PermissionKind?
    @ObservationIgnored private var heldSawRevoked = false
    @ObservationIgnored private var holdTimeout: Task<Void, Never>?
    /// Long enough for macOS to tell that the entry is gone; still allowed then, it never went.
    nonisolated static let holdLimit: Duration = .seconds(30)
    /// The tap threads take their taps down on their own run loops: a moment for that.
    nonisolated static let tapTeardown: Duration = .milliseconds(250)

    /// Gaps between the re-reads that follow a notification (so: at 0 s, 0.5 s and 2 s). The trust
    /// flag lands asynchronously: TCC posts first and the process's cached answer catches up a moment
    /// later. Three bounded re-reads cover that without polling.
    nonisolated static let recheckGaps: [Duration] = [.zero, .milliseconds(500), .milliseconds(1500)]

    /// `x-apple.systempreferences` deep link to Privacy & Security ▸ Accessibility.
    nonisolated static let accessibilitySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    @ObservationIgnored private var relay: DistributedNotificationRelay?
    @ObservationIgnored private var recheckTask: Task<Void, Never>?
    @ObservationIgnored private var activation: (any NSObjectProtocol)?
    @ObservationIgnored private var hasPrompted = false

    init() {}

    func start() {
        guard relay == nil else { return }
        refresh()
        relay = DistributedNotificationRelay(name: Notification.Name("com.apple.accessibility.api")) { [weak self] in
            self?.scheduleRechecks()
        }
        // Input Monitoring posts nothing when it is switched on: while either is still missing,
        // it is read again whenever another app comes forward (back from System Settings), instead
        // of polling.
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.accessibilityTrusted || !self.inputMonitoringAllowed else { return }
                self.refresh()
            }
        }
    }

    func stop() {
        relay?.invalidate()
        relay = nil
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        recheckTask?.cancel()
        recheckTask = nil
    }

    /// Re-reads the trust flag now (Settings calls this when it appears).
    func refresh() {
        let trusted = AXIsProcessTrusted()
        let listens = CGPreflightListenEventAccess()
        if let heldFor {
            if !(heldFor == .accessibility ? trusted : listens) {
                heldSawRevoked = true
            } else if heldSawRevoked {
                releaseKeyTaps("\(heldFor.tccService) allowed again")
            }
        }
        guard trusted != accessibilityTrusted || listens != inputMonitoringAllowed else { return }
        if trusted != accessibilityTrusted {
            accessibilityTrusted = trusted
            Log.system.notice("accessibility trusted: \(trusted, privacy: .public)")
        }
        if listens != inputMonitoringAllowed {
            inputMonitoringAllowed = listens
            Log.system.notice("input monitoring allowed: \(listens, privacy: .public)")
        }
        onChange?()
    }

    @ObservationIgnored private var hasRequestedListening = false

    /// Input Monitoring: macOS's own prompt the first time in a launch (it also puts NotchIsland in
    /// the list, switched off), the pane after that.
    func requestInputMonitoring() {
        refresh()
        guard !inputMonitoringAllowed else { return }
        if !hasRequestedListening {
            hasRequestedListening = true
            if CGRequestListenEventAccess() { refresh(); return }
        }
        PermissionKind.inputMonitoring.openSettings()
    }

    /// macOS's Input Monitoring prompt, once per launch, when ⌘Space was refused for want of it.
    /// Never opens System Settings by itself.
    func promptInputMonitoringOnce() {
        refresh()
        guard !inputMonitoringAllowed, !hasRequestedListening else { return }
        hasRequestedListening = true
        _ = CGRequestListenEventAccess()
        Log.system.notice("input monitoring prompt shown")
    }

    /// Forgets what macOS stored for NotchIsland under `kind` (`tccutil reset`), so an entry left
    /// by an older copy, switched on but not matching this one, is gone; then asks again.
    func reset(_ kind: PermissionKind) async {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let service = kind.tccService
        let holdsTaps = kind == .accessibility || kind == .inputMonitoring
        if holdsTaps {
            holdKeyTaps(for: kind)
            try? await Task.sleep(for: Self.tapTeardown)
        }
        let status = await Task.detached { () -> Int32 in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, bundleID]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return -1 }
            process.waitUntilExit()
            return process.terminationStatus
        }.value
        Log.system.notice("permission reset \(service, privacy: .public): \(status, privacy: .public)")
        if holdsTaps, status != 0 { releaseKeyTaps("reset failed") }
        hasPrompted = false
        hasRequestedListening = false
        refresh()
        switch kind {
        case .accessibility: requestAccessibility()
        case .inputMonitoring: requestInputMonitoring()
        default: kind.openSettings()
        }
    }

    /// Shows the system "allow Accessibility" prompt, at most once per launch: a dialog that returns
    /// every time a switch moves is its own bug. Later requests are served by the Settings button.
    func requestAccessibility() {
        refresh()
        guard !accessibilityTrusted, !hasPrompted else { return }
        hasPrompted = true
        // The string value of `kAXTrustedCheckOptionPrompt`; the imported global is a mutable C var,
        // which Swift 6 rejects as not concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        // Assign only on change: observers (the feature loop, Settings) wake on every write.
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        Log.system.notice("accessibility prompt shown")
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(Self.accessibilitySettingsURL)
    }

    /// The Settings button. The first time in a launch it shows the system prompt rather than the
    /// pane: prompting is what adds the app to the Accessibility list, so the user finds a switch to
    /// flip instead of having to add the app with "+". After that it opens the pane directly.
    func promptOrOpenAccessibilitySettings() {
        refresh()
        if !hasPrompted && !accessibilityTrusted {
            requestAccessibility()
        } else {
            openAccessibilitySettings()
        }
    }

    private func holdKeyTaps(for kind: PermissionKind) {
        heldFor = kind
        heldSawRevoked = false
        if !keyTapsHeld { keyTapsHeld = true }
        onHoldKeyTaps?()
        Log.system.notice("key taps held for the \(kind.tccService, privacy: .public) reset")
        holdTimeout?.cancel()
        holdTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.holdLimit)
            guard let self, !Task.isCancelled, let held = self.heldFor else { return }
            // Never seen gone: the reset changed nothing, the permission is still there.
            if held == .accessibility ? AXIsProcessTrusted() : CGPreflightListenEventAccess() {
                self.releaseKeyTaps("still allowed after \(Self.holdLimit)")
            }
        }
    }

    private func releaseKeyTaps(_ reason: String) {
        guard keyTapsHeld else { return }
        heldFor = nil
        heldSawRevoked = false
        holdTimeout?.cancel()
        holdTimeout = nil
        keyTapsHeld = false
        Log.system.notice("key taps let go: \(reason, privacy: .public)")
    }

    private func scheduleRechecks() {
        recheckTask?.cancel()
        recheckTask = Task { [weak self] in
            for gap in Self.recheckGaps {
                if gap > .zero {
                    do { try await Task.sleep(for: gap) } catch { return }
                }
                self?.refresh()
            }
        }
    }
}
