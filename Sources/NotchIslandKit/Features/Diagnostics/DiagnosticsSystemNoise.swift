import Foundation

/// What macOS logs at error level in every app for its own reasons: each kind looked into (the
/// logs of both testers' Macs, v0.4.9–v0.4.10), harmless, and outside what NotchIsland does.
/// Reports keep them, apart from the errors and explained, so they are not read as failures and
/// do not hide the real ones. (NotchIsland's own former errors — timed-out connections, Apple
/// Events to players not running, the signature database — were fixed instead, not listed here.)
nonisolated enum DiagnosticsSystemNoise {
    struct Kind: Sendable {
        let id: String
        let title: String
        /// What the message is and why nothing failed.
        let meaning: String
        /// Any of these in a log line.
        let patterns: [String]
    }

    static let kinds: [Kind] = [
        Kind(id: "coreaudio-plugin", title: "CoreAudio plug-in lookup",
             meaning: "CoreAudio looks for an audio plug-in that is not installed the first time the app uses sound (the level keys, the music bars). Every app that plays or measures sound logs it.",
             patterns: ["AddInstanceForFactory: No factory registered"]),
        Kind(id: "connection-closing", title: "Network connection closing",
             meaning: "The network stack reads the details of a connection that is already closing (HTTP/3 to Discord, after a report was delivered). The request itself succeeded.",
             patterns: ["on unconnected nw_connection"]),
        Kind(id: "reset-after-close", title: "Server goodbye after closing",
             meaning: "A server's reset packet arriving after the connection had already been closed.",
             patterns: ["state=CLOSED rcv_nxt="]),
        Kind(id: "menu-bar-scene", title: "Menu bar icon redrawn",
             meaning: "The menu bar icon's window is rebuilt when Spaces or full-screen apps change, and the system asks to close a version that is already gone.",
             patterns: ["No matching scene to invalidate", "BSBlockSentinel:FBSWorkspaceScenesClient"]),
        Kind(id: "task-port", title: "Another process not answerable",
             meaning: "A system framework asks about another process (the Dock, Control Center) and is not allowed to look; it asks the same in every app.",
             patterns: ["Unable to obtain a task name port right"]),
        Kind(id: "text-cursor", title: "Text cursor helper closed",
             meaning: "The system's text-cursor helper for a text field (Siri's field) was closed with the field; its own message says \"benign unless unexpected\".",
             patterns: ["ViewBridge to RemoteViewService Terminated", "com.apple.ViewBridge.error Code=18"]),
        Kind(id: "spotlight-restart", title: "Spotlight service restarted",
             meaning: "Spotlight's service restarted while a search was open; the search restarted by itself. Many of these together would point at Spotlight itself having trouble.",
             patterns: ["XPC_ERROR_CONNECTION_INVALID", "Preparing to restart query"]),
        Kind(id: "input-analytics", title: "Typing analytics reconnected",
             meaning: "The system's typing-analytics service reconnected.",
             patterns: ["IAXPCClient] Interrupted"]),
        Kind(id: "writing-tools", title: "Writing Tools looking for actions",
             meaning: "The system's Writing Tools look for an action this app does not offer.",
             patterns: ["WritingToolsCanPerformIntent"]),
        Kind(id: "drawing-step", title: "Drawing step skipped",
             meaning: "AppKit skips a drawing step that was already done.",
             patterns: ["Ignoring request to entangle context after pre-commit", "Entangling fence requested after pre-commit",
                        "cannot add handler to 2 from 2 - dropping"]),
        Kind(id: "offline", title: "Network unavailable",
             meaning: "The Mac was offline for a moment; a report waiting to go stays in the outbox and goes later.",
             patterns: ["received failure notification", "failed to connect", "The Internet connection appears to be offline",
                        "encountered error(1:50)"]),
        // Seen in the reports of v0.8.1 (both testers' Macs), looked into October 9.
        Kind(id: "asset-catalog", title: "No asset catalog",
             meaning: "AppKit looks for an asset catalog in the app (for an accent colour) at launch and when windows open; NotchIsland draws everything in code and ships none. Nothing is missing on screen.",
             patterns: ["unable to find a bundle 'NSBundle"]),
        Kind(id: "contacts-accounts", title: "Contacts' account list",
             meaning: "Opening the contacts (Spotlight's People) also asks for the Mac's internet accounts and contact notes, which only Apple's own apps may read. The names, numbers and addresses are read all the same.",
             patterns: ["Store registration failed", "com.apple.accounts Code=7", "Attempted to register account monitor",
                        "Attempt to read notes by an unentitled app", "Update event received, but store registration failed"]),
        Kind(id: "daemon-reconnect", title: "A system service reconnected",
             meaning: "Calendar's, the Dock's or Shortcuts' service restarted (after sleep, an update) and the app's connection to it was made again.",
             patterns: ["[com.apple.eventkit:EventKit] Connection interrupted", "Dock connection error: Connection interrupted",
                        "Client connection to VCVoiceShortcut XPC server interrupted"]),
        Kind(id: "drag-messages", title: "Drag messages crossing",
             meaning: "During a drag to the shelf, the system's drag service sends its next message before the last one was answered.",
             patterns: ["Reentrant message: kDragIPC"]),
        Kind(id: "mach-port-gone", title: "Key listener taken down",
             meaning: "A keyboard listener (the volume keys, ⌘Space) was stopped while the system still had an event for it.",
             patterns: ["__CFRunLoopModeFindSourceForMachPort returned NULL"]),
        Kind(id: "power-log", title: "Power log not open to apps",
             meaning: "A media framework tries to note its energy use in the system's power log, which apps may not write to.",
             patterns: ["PPSClientDonation isRegisteredSubsystem"]),
    ]

    static let title = "System messages (not errors)"

    static func kind(of line: Substring) -> Kind? {
        kinds.first { kind in kind.patterns.contains { line.contains($0) } }
    }

    /// The section: each kind seen, how often, what it means, one example.
    static func section(_ lines: [Substring]) -> DiagnosticsReport.Section {
        var section = DiagnosticsReport.Section(title)
        var seen: [String: (count: Int, example: Substring)] = [:]
        for line in lines {
            guard let kind = kind(of: line) else { continue }
            let entry = seen[kind.id]
            seen[kind.id] = ((entry?.count ?? 0) + 1, entry?.example ?? line)
        }
        let total = seen.values.reduce(0) { $0 + $1.count }
        section.add("What these are", total == 0 ? "none in this log"
            : "\(total) messages macOS logs at error level in every app. Each kind below is known and harmless: nothing NotchIsland did failed. Kept for completeness, not counted as errors.")
        for kind in kinds {
            guard let entry = seen[kind.id] else { continue }
            section.add("\(entry.count)× \(kind.title)", "\(kind.meaning)\nexample: \(entry.example.suffix(180))")
        }
        return section
    }
}
