import Foundation

/// What the user wrote in About's bug report or feature request form.
nonisolated struct DiagnosticsFeedback: Sendable, Codable, Equatable {
    nonisolated enum Kind: String, Sendable, Codable, CaseIterable, Identifiable {
        case bug, feature
        var id: String { rawValue }
    }

    /// How often a bug happens.
    nonisolated enum Frequency: String, Sendable, Codable, CaseIterable, Identifiable {
        case always, sometimes, once
        var id: String { rawValue }

        var title: String {
            switch self {
            case .always: "Every time"
            case .sometimes: "Sometimes"
            case .once: "Once"
            }
        }
    }

    var kind: Kind
    var title = ""
    /// Bug: what happened. Feature: what the user would like.
    var details = ""
    /// Bug only: what the user expected instead.
    var expected = ""
    /// Bug only: how to make it happen.
    var steps = ""
    var frequency: Frequency = .sometimes
    /// Feature only: why it would help.
    var why = ""

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A title and a description are required; everything else is optional.
    var isComplete: Bool { !Self.trimmed(title).isEmpty && !Self.trimmed(details).isEmpty }

    /// The form's text as Markdown, for the embed's description and for `feedback.txt`.
    var markdown: String {
        var parts: [String] = []
        func add(_ heading: String, _ text: String) {
            let text = Self.trimmed(text)
            guard !text.isEmpty else { return }
            parts.append("**\(heading)**\n\(text)")
        }
        switch kind {
        case .bug:
            add("What happened", details)
            add("Expected", expected)
            add("Steps to reproduce", steps)
        case .feature:
            add("The idea", details)
            add("Why it would help", why)
        }
        return parts.joined(separator: "\n\n")
    }
}

/// One delivery to the developer. Codable so a delivery that failed waits in the outbox until the
/// next attempt.
nonisolated struct DiagnosticsEnvelope: Sendable, Codable, Equatable {
    nonisolated enum Kind: String, Sendable, Codable {
        case report, bug, feature, crash
        /// Something measured well past the reference (energy, wakeups, memory…).
        case anomaly
    }

    nonisolated struct Fact: Sendable, Codable, Equatable {
        var name: String
        var value: String
    }

    nonisolated struct File: Sendable, Codable, Equatable {
        var name: String
        var text: String
    }

    var id = UUID()
    var created = Date()
    var kind: Kind
    /// Why an automatic report was sent.
    var reason: DiagnosticsReason?
    /// The name the user gave, or "Anonymous".
    var sender: String
    /// The install's anonymous id, so reports from one Mac can be told apart.
    var installID: String
    /// Version, macOS, Mac and the like: the embed's short fields.
    var facts: [Fact]
    /// What looks wrong at a glance (Accessibility off, apps missing from Spotlight, crashes…).
    var findings: [String]
    var feedback: DiagnosticsFeedback?
    var files: [File]
    /// The key numbers set against the reference, unusual ones marked.
    var comparison: [String]? = nil
    /// "v0.4.4 on Mac16,12", or nil without a reference.
    var reference: String? = nil
    /// Screenshots and recordings the user attached (bug reports), sent after the report itself.
    var media: [DiagnosticsMediaFile]? = nil

    /// Worth a line in the alerts channel.
    var isAlert: Bool { kind != .report || !findings.isEmpty }
}

/// Where each kind of delivery goes: Discord webhooks made by `Scripts/discord-setup.py`, written
/// into Info.plist (`NIDiagnosticsConfig`) by `Scripts/build.sh`.
nonisolated struct DiagnosticsDestinations: Sendable, Codable, Equatable {
    /// A forum: one post per install, every report of that Mac in it.
    var users: URL?
    /// Forums: one post per bug report / feature request.
    var bugs: URL?
    var features: URL?
    /// A text channel: one line per crash, anomaly, bug and request, linking to the details.
    var alerts: URL?
    /// A text channel for the developer's reference measurements.
    var baseline: URL?
    var guild: String?
    /// Forum tag ids ("new") applied to new posts.
    var bugTag: String?
    var featureTag: String?
    /// The single webhook of the first builds: everything goes there, as plain messages.
    var fallback: URL?

    var isConfigured: Bool { users != nil || fallback != nil }

    static let infoKey = "NIDiagnosticsConfig"
    static let legacyInfoKey = "NIDiagnosticsWebhookURL"

    static func from(info: [String: Any]?) -> DiagnosticsDestinations {
        if let json = info?[infoKey] as? String, let data = json.data(using: .utf8),
           let destinations = try? JSONDecoder().decode(DiagnosticsDestinations.self, from: data), destinations.isConfigured {
            return destinations
        }
        var destinations = DiagnosticsDestinations()
        if let text = info?[legacyInfoKey] as? String, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme == "https" {
            destinations.fallback = url
        }
        return destinations
    }

    /// A message link, when the server is known.
    func link(channel: String, message: String) -> URL? {
        guard let guild else { return nil }
        return URL(string: "https://discord.com/channels/\(guild)/\(channel)/\(message)")
    }
}

/// Posts to Discord webhooks: one embed per message, coloured by kind, with the facts as fields and
/// the report, the log and crash reports as attached text files that Discord previews in place.
nonisolated enum DiagnosticsUploader {
    /// Discord's limits (embed title 256, description 4096, field 1024, 6000 in all, 10 files); the
    /// request is kept well under the 10 MB allowed without boosts.
    static let contentLimit = 2000
    static let titleLimit = 256
    static let descriptionLimit = 4096
    static let fieldLimit = 1024
    static let embedTotalLimit = 5800
    static let fileLimit = 10
    static let requestLimit = 9_000_000

    nonisolated enum Failure: Error, Equatable, CustomStringConvertible {
        case status(Int, String)
        case rateLimited(retryAfter: TimeInterval)

        var description: String {
            switch self {
            case .status(let code, let body): "the server answered \(code)\(body.isEmpty ? "" : ": " + body)"
            case .rateLimited(let after): "too many reports; try again in \(Int(after.rounded(.up))) s"
            }
        }

        /// The thread or channel is gone (deleted in Discord): "Unknown Channel", code 10003.
        var isUnknownChannel: Bool {
            if case .status(let code, let body) = self { return code == 404 || body.contains("10003") }
            return false
        }
    }

    /// The message Discord created: its id, and the channel (for a new forum post, the post's
    /// thread) it is in.
    nonisolated struct Posted: Sendable, Equatable {
        var id: String
        var channelID: String
    }

    static func post(_ payload: [String: Any], files: [DiagnosticsEnvelope.File] = [], to webhook: URL,
                     threadID: String? = nil, session: URLSession = .shared) async throws -> Posted {
        let boundary = "NotchIsland-" + UUID().uuidString
        var request = URLRequest(url: webhookURL(webhook, threadID: threadID))
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body(payload: payload, files: files, boundary: boundary)
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429 {
            let after = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["retry_after"] as? Double
            throw Failure.rateLimited(retryAfter: after ?? 5)
        }
        guard (200..<300).contains(code) else {
            throw Failure.status(code, String(decoding: data.prefix(300), as: UTF8.self))
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return Posted(id: json["id"] as? String ?? "", channelID: json["channel_id"] as? String ?? threadID ?? "")
    }

    /// `?wait=true`, so Discord answers only once the message is really posted (with its id), and
    /// `thread_id` to post into an existing forum post.
    static func webhookURL(_ url: URL, threadID: String? = nil) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "wait" }) { items.append(URLQueryItem(name: "wait", value: "true")) }
        if let threadID { items.append(URLQueryItem(name: "thread_id", value: threadID)) }
        components.queryItems = items
        return components.url ?? url
    }

    // MARK: The messages

    static func color(_ kind: DiagnosticsEnvelope.Kind) -> Int {
        switch kind {
        case .bug: 0xFF453A
        case .feature: 0x30D158
        case .report: 0x0A84FF
        case .crash: 0xFF9F0A
        case .anomaly: 0xBF5AF2
        }
    }

    static func icon(_ kind: DiagnosticsEnvelope.Kind) -> String {
        switch kind {
        case .bug: "🐞"
        case .feature: "💡"
        case .report: "📊"
        case .crash: "💥"
        case .anomaly: "⚡"
        }
    }

    private static func feedbackTitle(_ envelope: DiagnosticsEnvelope) -> String {
        envelope.feedback.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }

    static func title(_ envelope: DiagnosticsEnvelope) -> String {
        switch envelope.kind {
        case .bug: "🐞 Bug: \(feedbackTitle(envelope))"
        case .feature: "💡 Feature request: \(feedbackTitle(envelope))"
        case .crash: "💥 Crash report"
        case .anomaly: "⚡ Unusual behaviour"
        case .report: "📊 Diagnostics · \(envelope.reason?.title ?? "Report")"
        }
    }

    /// The plain line above the embed: what shows in a notification.
    static func content(_ envelope: DiagnosticsEnvelope) -> String {
        let what = switch envelope.kind {
        case .bug: "🐞 **New bug report**"
        case .feature: "💡 **New feature request**"
        case .crash: "💥 **NotchIsland crashed**"
        case .anomaly: "⚡ **Something unusual**"
        case .report: "📊 Diagnostics"
        }
        return clipped("\(what) from **\(envelope.sender)**", contentLimit)
    }

    /// The forum post of an install: "👤 Béla · 1a2b3c4d".
    static func userThreadName(sender: String, installID: String) -> String {
        clipped("👤 \(sender) · \(installID.prefix(8))", 100)
    }

    /// The forum post of a bug or request: its title and who sent it.
    static func feedbackThreadName(_ envelope: DiagnosticsEnvelope) -> String {
        clipped("\(icon(envelope.kind)) \(feedbackTitle(envelope)) — \(envelope.sender)", 100)
    }

    /// The whole delivery: the embed with every fact, the form's text, the diagnosis and the
    /// comparison, plus the files. Mentions are switched off, so "@everyone" in a message pings no one.
    static func payload(for envelope: DiagnosticsEnvelope) -> [String: Any] {
        var fields: [[String: Any]] = []
        func field(_ name: String, _ value: String, inline: Bool) {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, fields.count < 25 else { return }
            fields.append(["name": clipped(name, titleLimit), "value": clipped(value, fieldLimit), "inline": inline])
        }
        field("From", envelope.sender, inline: true)
        if envelope.kind == .bug, let feedback = envelope.feedback {
            field("How often", feedback.frequency.title, inline: true)
        }
        for fact in envelope.facts { field(fact.name, fact.value, inline: true) }
        field("🔎 Quick diagnosis",
              envelope.findings.isEmpty ? "✅ Nothing stands out" : envelope.findings.map { "⚠️ \($0)" }.joined(separator: "\n"),
              inline: false)
        if let comparison = envelope.comparison, !comparison.isEmpty {
            field("📈 Compared with the reference\(envelope.reference.map { " (\($0))" } ?? "")", comparison.joined(separator: "\n"), inline: false)
        }
        field("📎 Attached", envelope.files.map { "`\($0.name)`" }.joined(separator: " · "), inline: false)
        if let media = envelope.media, !media.isEmpty {
            field("🖼️ Screenshots and videos", media.map { "`\($0.name)`\($0.wasTrimmed ? " (cut to fit)" : "")" }
                .joined(separator: " · ") + "\n(in the messages below)", inline: false)
        }

        var embed: [String: Any] = [
            "title": clipped(title(envelope), titleLimit),
            "color": color(envelope.kind),
            "fields": fields,
            "footer": ["text": "Install \(envelope.installID.prefix(8)) · \(envelope.id.uuidString.prefix(8))"],
            "timestamp": envelope.created.formatted(.iso8601),
        ]
        if let feedback = envelope.feedback {
            // Everything in an embed counts towards 6000 characters; the form's text gives way.
            let used = fields.reduce(0) { $0 + (($1["name"] as? String)?.count ?? 0) + (($1["value"] as? String)?.count ?? 0) } + 400
            embed["description"] = clipped(feedback.markdown, max(200, min(descriptionLimit, embedTotalLimit - used)))
        }
        return [
            "content": content(envelope),
            "embeds": [embed],
            "allowed_mentions": ["parse": [String]()],
        ]
    }

    /// The short line in the alerts channel: what, who, the diagnosis, and a link to the details.
    static func alertPayload(for envelope: DiagnosticsEnvelope, link: URL?) -> [String: Any] {
        var lines: [String] = []
        if envelope.kind == .bug || envelope.kind == .feature {
            lines.append("**\(feedbackTitle(envelope))**")
        }
        lines += envelope.findings.prefix(8).map { "⚠️ \($0)" }
        let version = envelope.facts.first { $0.name == "Version" }?.value ?? "?"
        lines.append("`\(envelope.sender)` · v\(version)")
        if let link { lines.append("[→ Open the details](\(link.absoluteString))") }
        return [
            "embeds": [[
                "title": clipped("\(icon(envelope.kind)) \(alertTitle(envelope))", titleLimit),
                "description": clipped(lines.joined(separator: "\n"), descriptionLimit),
                "color": color(envelope.kind),
                "timestamp": envelope.created.formatted(.iso8601),
            ] as [String: Any]],
            "allowed_mentions": ["parse": [String]()],
        ]
    }

    private static func alertTitle(_ envelope: DiagnosticsEnvelope) -> String {
        switch envelope.kind {
        case .bug: "Bug report from \(envelope.sender)"
        case .feature: "Feature request from \(envelope.sender)"
        case .crash: "Crash at \(envelope.sender)"
        case .anomaly: "Unusual behaviour at \(envelope.sender)"
        case .report: "Report from \(envelope.sender) needs a look"
        }
    }

    /// In the user's own post: a pointer to their bug report or request in its forum.
    static func pointerPayload(for envelope: DiagnosticsEnvelope, link: URL?) -> [String: Any] {
        let what = envelope.kind == .bug ? "Filed a bug report" : "Sent a feature request"
        var text = "**\(feedbackTitle(envelope))**"
        if let link { text += "\n[→ Open it](\(link.absoluteString))" }
        return [
            "embeds": [["title": "\(icon(envelope.kind)) \(what)", "description": clipped(text, descriptionLimit),
                        "color": color(envelope.kind)] as [String: Any]],
            "allowed_mentions": ["parse": [String]()],
        ]
    }

    static func body(for envelope: DiagnosticsEnvelope, boundary: String) -> Data {
        body(payload: payload(for: envelope), files: envelope.files, boundary: boundary)
    }

    static func body(payload: [String: Any], files: [DiagnosticsEnvelope.File], boundary: String) -> Data {
        var body = Data()
        func part(_ headers: String, _ content: Data) {
            body.append(Data("--\(boundary)\r\n\(headers)\r\n\r\n".utf8))
            body.append(content)
            body.append(Data("\r\n".utf8))
        }
        let json = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
        part("Content-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json", json)

        var budget = requestLimit - body.count
        for (index, file) in fitted(files, budget: &budget).enumerated() {
            let name = file.name.replacingOccurrences(of: "\"", with: "")
            part("Content-Disposition: form-data; name=\"files[\(index)]\"; filename=\"\(name)\"\r\nContent-Type: text/plain; charset=utf-8",
                 Data(file.text.utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    /// At most `fileLimit` files; one that would pass the size budget is cut to what is left (the
    /// end of a log is kept, the start of anything else), and the rest are dropped.
    static func fitted(_ files: [DiagnosticsEnvelope.File], budget: inout Int) -> [DiagnosticsEnvelope.File] {
        var result: [DiagnosticsEnvelope.File] = []
        for var file in files.prefix(fileLimit) {
            let room = budget - 400
            guard room > 1000 else { break }
            if file.text.utf8.count > room {
                file.text = file.name.hasPrefix("log")
                    ? DiagnosticsFormat.tail(file.text, limit: room - 100)
                    : DiagnosticsFormat.head(file.text, limit: room - 100)
            }
            budget -= file.text.utf8.count + 400
            result.append(file)
        }
        return result
    }

    // MARK: Screenshots and videos

    /// One screenshot or video as a message of its own (each may be up to `DiagnosticsMedia.maxBytes`,
    /// so they do not share one request's 10 MB), into the report's thread.
    static func postMedia(_ file: DiagnosticsMediaFile, index: Int, of count: Int, to webhook: URL, threadID: String?,
                          session: URLSession = .shared) async throws {
        let data = try Data(contentsOf: file.url)
        let boundary = "NotchIsland-" + UUID().uuidString
        var request = URLRequest(url: webhookURL(webhook, threadID: threadID))
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.httpMethod = "POST"
        // An 8 MB video over a slow upload.
        request.timeoutInterval = 300
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let text = "\(file.isVideo ? "🎬" : "🖼️") \(index + 1)/\(count) · `\(file.name)`\(file.wasTrimmed ? " (cut to fit)" : "")"
        request.httpBody = mediaBody(payload: ["content": clipped(text, contentLimit), "allowed_mentions": ["parse": [String]()]],
                                     name: file.name, contentType: file.contentType, data: data, boundary: boundary)
        let (body, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429 {
            let after = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["retry_after"] as? Double
            throw Failure.rateLimited(retryAfter: after ?? 5)
        }
        guard (200..<300).contains(code) else { throw Failure.status(code, String(decoding: body.prefix(300), as: UTF8.self)) }
    }

    static func mediaBody(payload: [String: Any], name: String, contentType: String, data: Data, boundary: String) -> Data {
        var body = Data()
        let json = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n".utf8))
        body.append(json)
        let safe = name.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"\(safe)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    static func clipped(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}
