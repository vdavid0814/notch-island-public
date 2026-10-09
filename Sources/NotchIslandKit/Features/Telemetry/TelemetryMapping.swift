import Foundation

/// A Mixpanel property's value: what JSON carries, kept `Sendable` and `Codable` for the queue.
nonisolated enum TelemetryValue: Sendable, Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

/// What the diagnostics already found, turned into what Sentry and Mixpanel take. Pure: the report
/// and its verdict in, events out (`TelemetryMappingTests`).
nonisolated enum TelemetryMapping {
    // MARK: Privacy

    /// A step of the user's flow without what was typed: Siri's queries become their length
    /// (`siri: "‹6›" in root → 1 apps`). The report the user previews keeps them; a third party
    /// does not get them.
    static func redacted(_ step: String) -> String {
        var result = ""
        var quoted: String?
        for character in step {
            if character == "\"" {
                if let text = quoted {
                    result += "\"‹\(text.count)›\""
                    quoted = nil
                } else {
                    quoted = ""
                }
            } else if quoted != nil {
                quoted!.append(character)
            } else {
                result.append(character)
            }
        }
        // An unclosed quote: what followed it is left out too.
        if let text = quoted { result += "\"‹\(text.count)›" }
        return result
    }

    // MARK: Sentry

    /// One likely cause (`DiagnosticsVerdict.Check`) as a Sentry issue: grouped by its stable id
    /// across reports and Macs, so Sentry counts the Macs and the times it was seen.
    nonisolated struct Cause: Sendable, Equatable {
        var id: String
        var isIssue: Bool
        var feature: String
        var message: String
        var cause: String
        var action: String
        var confidence: String

        var fingerprint: [String] { ["notchisland-cause", id] }
    }

    static func causes(_ verdict: DiagnosticsVerdict?) -> [Cause] {
        (verdict?.problems ?? []).map { check in
            Cause(id: check.id, isIssue: check.severity == .issue, feature: check.feature,
                  message: "[\(check.feature)] \(redacted(check.title))", cause: redacted(check.cause),
                  action: check.action, confidence: check.confidence.rawValue)
        }
    }

    /// One of NotchIsland's own error lines in the log (`Errors by source`), grouped by its
    /// category and wording with the numbers taken out.
    nonisolated struct OwnError: Sendable, Equatable {
        var category: String
        var count: Int
        var message: String

        var fingerprint: [String] { ["notchisland-log", category, TelemetryMapping.template(message)] }
    }

    static let ownSubsystem = "com.davidvarga.notchisland:"

    static func ownErrors(_ report: DiagnosticsReport) -> [OwnError] {
        guard let section = report.sections.first(where: { $0.title == "Errors by source" }) else { return [] }
        return section.entries.compactMap { entry -> OwnError? in
            // "4× [com.davidvarga.notchisland:levels]" : "2026-… E  NotchIsland[…] [com…:levels] media key tap could not be created"
            guard let open = entry.key.range(of: "[" + ownSubsystem), let close = entry.key.range(of: "]", range: open.upperBound..<entry.key.endIndex),
                  let count = Int(entry.key.prefix { $0.isNumber }) else { return nil }
            let category = String(entry.key[open.upperBound..<close.lowerBound])
            let marker = "[" + ownSubsystem + category + "] "
            let message = entry.value.range(of: marker).map { String(entry.value[$0.upperBound...]) } ?? entry.value
            return OwnError(category: category, count: count, message: redacted(message.trimmingCharacters(in: .whitespaces)))
        }
    }

    /// A message with its numbers, paths' variable parts and quoted names taken out, so the same
    /// error groups as one ("pid 407", "at 979,832").
    static func template(_ message: String) -> String {
        var result = ""
        var lastWasNumber = false
        for character in message {
            if character.isNumber {
                if !lastWasNumber { result += "N" }
                lastWasNumber = true
            } else {
                result.append(character)
                lastWasNumber = false
            }
        }
        return String(result.prefix(200))
    }

    /// The reasons whose report travels whole (report.txt, report.json, log.txt) as a Sentry event:
    /// asked for, or something happened. The hourly and launch reports bring only their numbers
    /// (Mixpanel) and new causes; a full log every hour was the old reports' bulk.
    static func sendsWholeReport(_ reason: DiagnosticsReason?) -> Bool {
        guard let reason else { return true }
        switch reason {
        case .manual, .message, .crash, .anomaly, .problem: return true
        case .enabled, .launch, .periodic, .update: return false
        }
    }

    // MARK: Mixpanel

    /// A feature's line in `Feature health`, in one word.
    static func featureState(_ line: String) -> String {
        if line.hasPrefix("✅") { return "running" }
        if line.hasPrefix("⚠︎") { return "broken" }
        if line.hasPrefix("paused") { return "paused" }
        return "off"
    }

    /// "Volume/brightness keys" → "volume_brightness_keys".
    static func slug(_ text: String) -> String {
        var result = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber, character.isASCII {
                result.append(character)
            } else if !result.isEmpty, result.last != "_" {
                result.append("_")
            }
        }
        while result.hasSuffix("_") { result.removeLast() }
        return result
    }

    /// The hourly (and launch, crash…) health numbers: what the report measured, each feature's
    /// state and the verdict's counts. Nothing typed, no names, no paths.
    static func snapshot(_ report: DiagnosticsReport, verdict: DiagnosticsVerdict?, reason: DiagnosticsReason?,
                         light: Bool) -> [String: TelemetryValue] {
        var properties: [String: TelemetryValue] = [
            "reason": .string(reason?.rawValue ?? "feedback"),
            "light": .bool(light),
        ]
        for (metric, value) in report.metrics where value.isFinite {
            properties["metric_" + slug(metric.rawValue)] = .number((value * 100).rounded() / 100)
        }
        for entry in report.sections.first(where: { $0.title == "Feature health" })?.entries ?? [] {
            properties["feature_" + slug(entry.key)] = .string(featureState(entry.value))
        }
        if let verdict {
            properties["issues"] = .number(Double(verdict.issues))
            properties["warnings"] = .number(Double(verdict.warnings))
            properties["healthy"] = .number(Double(verdict.healthy))
            if let top = verdict.mostLikely { properties["top_cause"] = .string(top.id) }
        }
        for fact in DiagnosticsFindings.facts(report) where ["macOS", "Mac", "Chip", "Runs from"].contains(fact.name) {
            // A path outside Applications carries the user's name (/Users/…): only that it is elsewhere.
            let value = fact.value.hasPrefix("/") && fact.value != "/Applications" ? "elsewhere" : fact.value
            properties[slug(fact.name)] = .string(value)
        }
        return properties
    }
}
