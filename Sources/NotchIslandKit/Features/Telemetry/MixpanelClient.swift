import Foundation
import Synchronization

/// Mixpanel without its SDK: events wait in a file and go in batches when the diagnostics cycle
/// sends (at launch and hourly), so nothing here keeps a timer or wakes the app. Ingestion only
/// (`/track` with the project token, `ip=0`: Mixpanel stores no location). An event older than
/// `maxAge` is dropped (`/track` refuses those; `/import` would need the project's secret).
nonisolated final class MixpanelClient: Sendable {
    nonisolated struct Event: Sendable, Codable, Equatable {
        var name: String
        var properties: [String: TelemetryValue]
        var time: Date
        var insertID: String
    }

    static let batchLimit = 50
    static let queueLimit = 500
    static let maxAge: TimeInterval = 4 * 86400

    let token: String
    let host: String
    let distinctID: String
    /// Sent with every event (version, build, macOS, environment).
    let common: [String: TelemetryValue]
    private let file: URL?
    private let session: URLSession
    private let queue = Mutex<[Event]>([])
    private let sending = Mutex(false)

    init(token: String, host: String, distinctID: String, common: [String: TelemetryValue], file: URL?,
         session: URLSession = .shared) {
        self.token = token
        self.host = host
        self.distinctID = distinctID
        self.common = common
        self.file = file
        self.session = session
        if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Event].self, from: data) {
            queue.withLock { $0 = saved }
        }
    }

    var pending: Int { queue.withLock { $0.count } }

    /// Queued (and kept on disk) until the next `flush`.
    func track(_ name: String, _ properties: [String: TelemetryValue] = [:], at time: Date = Date()) {
        let event = Event(name: name, properties: properties, time: time, insertID: UUID().uuidString.lowercased())
        let saved = queue.withLock { events -> [Event] in
            events.append(event)
            if events.count > Self.queueLimit { events.removeFirst(events.count - Self.queueLimit) }
            return events
        }
        save(saved)
    }

    /// Sends what waits, in batches; what fails stays for the next time. True when all went.
    @discardableResult
    func flush(now: Date = Date()) async -> Bool {
        guard sending.withLock({ busy in defer { busy = true }; return !busy }) else { return false }
        defer { sending.withLock { $0 = false } }
        let waiting = queue.withLock { events -> [Event] in
            events.removeAll { now.timeIntervalSince($0.time) > Self.maxAge }
            return events
        }
        var sent = Set<String>()
        var allWent = true
        for start in stride(from: 0, to: waiting.count, by: Self.batchLimit) {
            let batch = Array(waiting[start..<min(start + Self.batchLimit, waiting.count)])
            do {
                try await post(batch)
                sent.formUnion(batch.map(\.insertID))
            } catch {
                Log.app.notice("mixpanel: \(batch.count, privacy: .public) events wait (\(error.localizedDescription, privacy: .public))")
                allWent = false
                break
            }
        }
        let left = queue.withLock { events -> [Event] in
            events.removeAll { sent.contains($0.insertID) }
            return events
        }
        save(left)
        return allWent
    }

    /// The request body: Mixpanel's event objects, with the token, the install's id and the common
    /// properties in each.
    func body(_ batch: [Event]) throws -> Data {
        let objects: [[String: Any]] = batch.map { event in
            var properties: [String: Any] = [
                "token": token,
                "distinct_id": distinctID,
                "time": Int64((event.time.timeIntervalSince1970 * 1000).rounded()),
                "$insert_id": event.insertID,
                "$os": "macOS",
            ]
            for (key, value) in common.merging(event.properties, uniquingKeysWith: { _, new in new }) {
                switch value {
                case .string(let text): properties[key] = text
                case .number(let number): properties[key] = number
                case .bool(let flag): properties[key] = flag
                }
            }
            return ["event": event.name, "properties": properties]
        }
        return try JSONSerialization.data(withJSONObject: objects)
    }

    /// `host` alone is HTTPS; with a scheme (a local stand-in while testing) it is taken as it is.
    var endpoint: URL { URL(string: (host.contains("://") ? host : "https://" + host) + "/track?ip=0&verbose=1")! }

    private func post(_ batch: [Event]) async throws {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try body(batch)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // verbose=1: {"status": 1} when taken, {"status": 0, "error": …} when not.
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200, (answer?["status"] as? Int) == 1 else {
            let error = answer?["error"] as? String ?? String(decoding: data.prefix(200), as: UTF8.self)
            // A batch Mixpanel refuses as such (a bad token, a bad property) would never go: dropped.
            if status == 400 {
                Log.app.error("mixpanel refused \(batch.count, privacy: .public) events: \(error, privacy: .public)")
                return
            }
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Mixpanel answered \(status): \(error)"])
        }
    }

    private func save(_ events: [Event]) {
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(events) { try? data.write(to: file, options: .atomic) }
    }
}
