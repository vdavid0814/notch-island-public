import os

/// Unified-logging categories under one subsystem, so `Scripts/logs.sh` can stream the whole app
/// and filter by category.
///
/// `nonisolated` because C callbacks, CoreAudio queues and child-process pipes log from their own
/// threads; `Logger` is `Sendable`, so no hop to the main actor is needed just to log.
nonisolated enum Log {
    static let subsystem = "com.davidvarga.notchisland"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let island = Logger(subsystem: subsystem, category: "island")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let power = Logger(subsystem: subsystem, category: "power")
    static let levels = Logger(subsystem: subsystem, category: "levels")
    static let shelf = Logger(subsystem: subsystem, category: "shelf")
    static let timers = Logger(subsystem: subsystem, category: "timers")
    static let recording = Logger(subsystem: subsystem, category: "recording")
    /// Fan Control: the fan helper, its install, and what it set.
    static let fans = Logger(subsystem: subsystem, category: "fans")
    /// Window Anchor: what was held, put back and let go.
    static let anchor = Logger(subsystem: subsystem, category: "anchor")
    /// Permissions, sleep/wake, power and thermal state, launch at login.
    static let system = Logger(subsystem: subsystem, category: "system")
}
