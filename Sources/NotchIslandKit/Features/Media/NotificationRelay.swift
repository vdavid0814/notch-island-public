import AppKit

/// Selector-based notification observers owned by one object, removed together.
///
/// Selector-based because distributed observers need `suspensionBehavior: .deliverImmediately`, which
/// the block API cannot set: NSApplication suspends distributed delivery while the app is inactive, and
/// an LSUIElement app behind a non-activating panel is essentially never active. Both centres used here
/// deliver on the main thread, where this main-actor object lives.
final class NotificationRelay: NSObject {
    private var handlers: [Notification.Name: (Notification) -> Void] = [:]
    private var registrations: [(center: NotificationCenter, name: Notification.Name)] = []

    func observeDistributed(_ name: Notification.Name, handler: @escaping (Notification) -> Void) {
        let center = DistributedNotificationCenter.default()
        handlers[name] = handler
        center.addObserver(self, selector: #selector(deliver(_:)), name: name, object: nil,
                           suspensionBehavior: .deliverImmediately)
        registrations.append((center, name))
    }

    func observe(_ name: Notification.Name, in center: NotificationCenter, handler: @escaping (Notification) -> Void) {
        handlers[name] = handler
        center.addObserver(self, selector: #selector(deliver(_:)), name: name, object: nil)
        registrations.append((center, name))
    }

    func removeAll() {
        for registration in registrations {
            registration.center.removeObserver(self, name: registration.name, object: nil)
        }
        registrations.removeAll()
        handlers.removeAll()
    }

    @objc private func deliver(_ notification: Notification) {
        handlers[notification.name]?(notification)
    }
}
