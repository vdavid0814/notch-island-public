import Foundation

/// A diagnostics report: titled sections of key–value lines, plus the long texts (logs, crash
/// reports) that travel as files of their own.
///
/// Plain strings throughout, so a new reading is one line where it is taken and the developer reads
/// the report as text.
nonisolated struct DiagnosticsReport: Sendable, Equatable {
    nonisolated struct Entry: Sendable, Equatable {
        var key: String
        var value: String
    }

    nonisolated struct Section: Sendable, Equatable {
        var title: String
        var entries: [Entry] = []

        init(_ title: String, _ entries: [Entry] = []) {
            self.title = title
            self.entries = entries
        }

        mutating func add(_ key: String, _ value: String) {
            entries.append(Entry(key: key, value: value))
        }

        mutating func add(_ key: String, _ value: some CustomStringConvertible) {
            add(key, value.description)
        }

        mutating func add(_ key: String, _ value: (some CustomStringConvertible)?) {
            add(key, value.map(\.description) ?? "—")
        }
    }

    /// A file sent next to the report (`log.txt`, a crash report).
    nonisolated struct Attachment: Sendable, Equatable {
        var name: String
        var text: String
    }

    var sections: [Section] = []
    var attachments: [Attachment] = []
    /// The numbers compared with the reference (`DiagnosticsBaseline`).
    var metrics: [DiagnosticsMetric: Double] = [:]

    /// The report as the developer reads it.
    var text: String {
        var lines: [String] = []
        for section in sections {
            lines.append("== \(section.title) ==")
            let width = min(section.entries.map(\.key.count).max() ?? 0, 34)
            for entry in section.entries {
                let key = entry.key.padding(toLength: max(width, entry.key.count), withPad: " ", startingAt: 0)
                // Continuation lines line up under the value.
                let value = entry.value.replacingOccurrences(
                    of: "\n", with: "\n" + String(repeating: " ", count: max(width, entry.key.count) + 3))
                lines.append("\(key) : \(value)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// The value of `key` in the section titled `title`.
    func value(_ key: String, in title: String) -> String? {
        sections.first { $0.title == title }?.entries.first { $0.key == key }?.value
    }
}

/// Why a report was sent (the first word of its message, so the developer can filter).
nonisolated enum DiagnosticsReason: String, Sendable, Codable {
    /// The user just turned diagnostics on.
    case enabled
    /// NotchIsland started.
    case launch
    /// The regular report while it runs.
    case periodic
    /// Send Report Now.
    case manual
    /// The user wrote a message.
    case message
    /// A crash report newer than the last report was found.
    case crash
    /// A 10-minute sample was well past the reference twice in a row.
    case anomaly

    var title: String {
        switch self {
        case .enabled: "Diagnostics turned on"
        case .launch: "Launch"
        case .periodic: "Periodic"
        case .manual: "Sent by hand"
        case .message: "Message"
        case .crash: "Crash"
        case .anomaly: "Unusual behaviour detected"
        }
    }
}

/// Byte formatting and capping shared by the collectors.
nonisolated enum DiagnosticsFormat {
    static func bytes(_ count: some BinaryInteger) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .memory)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "—" }
        if seconds < 1 { return String(format: "%.0f ms", seconds * 1000) }
        if seconds < 120 { return String(format: "%.1f s", seconds) }
        let minutes = Int(seconds / 60)
        if minutes < 120 { return "\(minutes) min" }
        return String(format: "%.1f h", seconds / 3600)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted))
    }

    static func rect(_ rect: CGRect) -> String {
        String(format: "(%.0f, %.0f) %.0f×%.0f", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }

    static func size(_ size: CGSize) -> String {
        String(format: "%.0f×%.0f", size.width, size.height)
    }

    /// The last `limit` bytes of `text`, cut at a line start, with a note of what was dropped: the
    /// end of a log is what explains a bug.
    static func tail(_ text: String, limit: Int) -> String {
        let utf8 = text.utf8
        guard utf8.count > limit else { return text }
        var start = utf8.index(utf8.endIndex, offsetBy: -limit)
        if let newline = utf8[start...].firstIndex(of: UInt8(ascii: "\n")) {
            start = utf8.index(after: newline)
        }
        let dropped = utf8.distance(from: utf8.startIndex, to: start)
        return "[… \(bytes(dropped)) earlier cut …]\n" + String(decoding: utf8[start...], as: UTF8.self)
    }

    /// The first `limit` bytes of `text` (a crash report's header and crashing thread come first).
    static func head(_ text: String, limit: Int) -> String {
        let utf8 = text.utf8
        guard utf8.count > limit else { return text }
        let end = utf8.index(utf8.startIndex, offsetBy: limit)
        return String(decoding: utf8[..<end], as: UTF8.self) + "\n[… \(bytes(utf8.count - limit)) more cut …]"
    }
}
