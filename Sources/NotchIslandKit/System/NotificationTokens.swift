import Foundation

/// Owns block-based `NotificationCenter` observers so that every observer that is added is also
/// removed (the legacy app leaked several tokens and could register duplicates on restart).
///
/// Handlers run on the main actor. The observer block itself is registered with `queue: nil`, so it
/// runs synchronously on the posting thread and only enqueues the main-actor hop: `NSWorkspace`
/// posts on the main thread, so its sleep/wake events keep their order (same-priority main-actor
/// jobs run FIFO), and the `ProcessInfo` notifications that arrive on arbitrary threads are only
/// ever used as a cue to re-read current state, where order does not matter.
final class NotificationTokens {
    private var tokens: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    var isEmpty: Bool { tokens.isEmpty }

    func observe(
        _ name: Notification.Name,
        on center: NotificationCenter,
        _ handler: @escaping @MainActor @Sendable () -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: nil) { _ in
            Task { @MainActor in handler() }
        }
        tokens.append((center, token))
    }

    func removeAll() {
        for entry in tokens {
            entry.center.removeObserver(entry.token)
        }
        tokens.removeAll()
    }
}

/// Observes one distributed notification with `.deliverImmediately`.
///
/// AppKit suspends distributed-notification delivery while the app is inactive, and an accessory
/// app behind a non-activating panel is practically never active, so the default (`.coalesce`)
/// would hold the notification until the user happens to open Settings. The suspension behaviour
/// can only be chosen on the selector-based API, hence this small `NSObject` relay.
final class DistributedNotificationRelay: NSObject {
    private let name: Notification.Name
    private let handler: () -> Void

    init(name: Notification.Name, handler: @escaping () -> Void) {
        self.name = name
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(received(_:)),
            name: name,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    func invalidate() {
        DistributedNotificationCenter.default().removeObserver(self, name: name, object: nil)
    }

    @objc private func received(_ notification: Notification) {
        handler()
    }
}
