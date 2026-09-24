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

    /// Gaps between the re-reads that follow a notification (so: at 0 s, 0.5 s and 2 s). The trust
    /// flag lands asynchronously: TCC posts first and the process's cached answer catches up a moment
    /// later. Three bounded re-reads cover that without polling.
    nonisolated static let recheckGaps: [Duration] = [.zero, .milliseconds(500), .milliseconds(1500)]

    /// `x-apple.systempreferences` deep link to Privacy & Security ▸ Accessibility.
    nonisolated static let accessibilitySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    @ObservationIgnored private var relay: DistributedNotificationRelay?
    @ObservationIgnored private var recheckTask: Task<Void, Never>?
    @ObservationIgnored private var hasPrompted = false

    init() {}

    func start() {
        guard relay == nil else { return }
        refresh()
        relay = DistributedNotificationRelay(name: Notification.Name("com.apple.accessibility.api")) { [weak self] in
            self?.scheduleRechecks()
        }
    }

    func stop() {
        relay?.invalidate()
        relay = nil
        recheckTask?.cancel()
        recheckTask = nil
    }

    /// Re-reads the trust flag now (Settings calls this when it appears).
    func refresh() {
        let trusted = AXIsProcessTrusted()
        guard trusted != accessibilityTrusted else { return }
        accessibilityTrusted = trusted
        Log.system.notice("accessibility trusted: \(trusted, privacy: .public)")
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
