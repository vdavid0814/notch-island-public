import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import NotchIslandKit

@Suite struct DiagnosticsReportTests {
    @Test func textAlignsKeysAndIndentsContinuationLines() {
        var section = DiagnosticsReport.Section("App")
        section.add("Version", "0.4.4")
        section.add("Copies", "one\ntwo")
        let text = DiagnosticsReport(sections: [section]).text
        #expect(text.contains("== App =="))
        #expect(text.contains("Version : 0.4.4"))
        #expect(text.contains("Copies  : one\n          two"))
    }

    @Test func tailKeepsTheEndFromALineStart() {
        let log = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let tail = DiagnosticsFormat.tail(log, limit: 40)
        #expect(tail.hasPrefix("[… "))
        #expect(tail.hasSuffix("line 100"))
        #expect(!tail.contains("line 1\n"))
        #expect(DiagnosticsFormat.tail("short", limit: 40) == "short")
    }

    @Test func headKeepsTheStart() {
        let head = DiagnosticsFormat.head(String(repeating: "a", count: 100), limit: 10)
        #expect(head.hasPrefix("aaaaaaaaaa\n[…"))
    }
}

@Suite struct DiagnosticsFeedbackTests {
    @Test func needsATitleAndADescription() {
        var feedback = DiagnosticsFeedback(kind: .bug, title: "  ", details: "It broke")
        #expect(!feedback.isComplete)
        feedback.title = "Siri"
        #expect(feedback.isComplete)
    }

    @Test func markdownHasOnlyTheFilledInParts() {
        let bug = DiagnosticsFeedback(kind: .bug, title: "T", details: "No apps", expected: "", steps: "Press ⌘Space")
        #expect(bug.markdown == "**What happened**\nNo apps\n\n**Steps to reproduce**\nPress ⌘Space")
        let feature = DiagnosticsFeedback(kind: .feature, title: "T", details: "Weather", why: "Handy")
        #expect(feature.markdown == "**The idea**\nWeather\n\n**Why it would help**\nHandy")
    }
}

@Suite struct DiagnosticsUploaderTests {
    private func envelope(_ kind: DiagnosticsEnvelope.Kind, feedback: DiagnosticsFeedback? = nil,
                          findings: [String] = [], files: [DiagnosticsEnvelope.File] = []) -> DiagnosticsEnvelope {
        DiagnosticsEnvelope(kind: kind, reason: kind == .report ? .launch : nil, sender: "Béla", installID: "abcdef123456",
                            facts: [.init(name: "Version", value: "0.4.4 (14)")], findings: findings,
                            feedback: feedback, files: files)
    }

    @Test func bugReportIsARedEmbedWithTheFormAndFacts() throws {
        let feedback = DiagnosticsFeedback(kind: .bug, title: "Siri finds no apps", details: "Empty gallery", frequency: .always)
        let payload = DiagnosticsUploader.payload(for: envelope(.bug, feedback: feedback, findings: ["Accessibility is off"]))
        let embed = try #require((payload["embeds"] as? [[String: Any]])?.first)
        #expect(embed["title"] as? String == "🐞 Bug: Siri finds no apps")
        #expect(embed["color"] as? Int == 0xFF453A)
        #expect((embed["description"] as? String)?.contains("Empty gallery") == true)
        let fields = try #require(embed["fields"] as? [[String: Any]])
        let names = fields.compactMap { $0["name"] as? String }
        #expect(names.prefix(3) == ["From", "How often", "Version"])
        #expect(fields.first { $0["name"] as? String == "How often" }?["value"] as? String == "Every time")
        #expect(fields.first { $0["name"] as? String == "🔎 Quick diagnosis" }?["value"] as? String == "⚠️ Accessibility is off")
        #expect(payload["content"] as? String == "🐞 **New bug report** from **Béla**")
        #expect((payload["allowed_mentions"] as? [String: [String]])?["parse"] == [])
    }

    @Test func reportsAndFeaturesHaveTheirOwnLook() throws {
        let report = DiagnosticsUploader.payload(for: envelope(.report))
        let embed = try #require((report["embeds"] as? [[String: Any]])?.first)
        #expect(embed["title"] as? String == "📊 Diagnostics · Launch")
        #expect(embed["color"] as? Int == 0x0A84FF)
        #expect(embed["description"] == nil)
        let fields = try #require(embed["fields"] as? [[String: Any]])
        #expect(fields.first { $0["name"] as? String == "🔎 Quick diagnosis" }?["value"] as? String == "✅ Nothing stands out")
        let feature = DiagnosticsUploader.payload(for: envelope(.feature, feedback: .init(kind: .feature, title: "Weather", details: "x")))
        #expect(((feature["embeds"] as? [[String: Any]])?.first?["color"] as? Int) == 0x30D158)
    }

    @Test func bodyCarriesThePayloadAndEveryFile() {
        let files = [DiagnosticsEnvelope.File(name: "report.txt", text: "REPORT"), .init(name: "log.txt", text: "LOG")]
        let body = String(decoding: DiagnosticsUploader.body(for: envelope(.report, files: files), boundary: "B"), as: UTF8.self)
        #expect(body.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"payload_json\""))
        #expect(body.contains("name=\"files[0]\"; filename=\"report.txt\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nREPORT\r\n"))
        #expect(body.contains("name=\"files[1]\"; filename=\"log.txt\""))
        #expect(body.hasSuffix("--B--\r\n"))
    }

    @Test func filesAreCutToTheBudget() {
        let big = String(repeating: "x\n", count: 5000)
        var budget = 6000
        let files = DiagnosticsUploader.fitted([.init(name: "log.txt", text: big), .init(name: "crash.ips", text: big)], budget: &budget)
        #expect(files.count == 1)
        #expect(files[0].text.utf8.count < 6000)
        #expect(files[0].text.hasSuffix("x\n"))
    }

    @Test func webhookWaitsForTheMessage() {
        let url = URL(string: "https://discord.com/api/webhooks/1/abc")!
        #expect(DiagnosticsUploader.webhookURL(url).absoluteString == "https://discord.com/api/webhooks/1/abc?wait=true")
        let already = URL(string: "https://discord.com/api/webhooks/1/abc?wait=false")!
        #expect(DiagnosticsUploader.webhookURL(already) == already)
    }

    @Test func envelopeSurvivesTheOutbox() throws {
        let original = envelope(.bug, feedback: .init(kind: .bug, title: "T", details: "D"), files: [.init(name: "a.txt", text: "A")])
        let decoded = try JSONDecoder().decode(DiagnosticsEnvelope.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}

@Suite struct DiagnosticsFindingsTests {
    private func report(_ entries: [(String, String, String)]) -> DiagnosticsReport {
        var sections: [String: DiagnosticsReport.Section] = [:]
        var order: [String] = []
        for (title, key, value) in entries {
            if sections[title] == nil { order.append(title); sections[title] = .init(title) }
            sections[title]?.add(key, value)
        }
        return DiagnosticsReport(sections: order.compactMap { sections[$0] })
    }

    @Test func healthyReportFindsNothing() {
        let healthy = report([
            ("App", "In /Applications", "true"), ("Permissions", "Accessibility", "true"),
            (DiagnosticsProbes.spotlightTitle, DiagnosticsProbes.missingKey, "0"),
            ("Copies", "Instances running", "1"), ("Running apps", "Other notch apps running", "none"),
        ])
        #expect(DiagnosticsFindings.findings(healthy, crashes: 0).isEmpty)
        #expect(DiagnosticsFindings.runsFrom(healthy) == "/Applications")
    }

    @Test func spotsTheUsualCulprits() {
        let broken = report([
            ("App", "Run from a disk image", "true"), ("Permissions", "Accessibility", "false"),
            (DiagnosticsProbes.spotlightTitle, DiagnosticsProbes.missingKey, "37"),
            (DiagnosticsProbes.spotlightTitle, DiagnosticsProbes.galleryKey, "0 apps in 12 ms"),
            (DiagnosticsProbes.spotlightTitle, "mdutil -s /", "/:\n\tIndexing disabled."),
            ("Copies", "Instances running", "2"),
        ])
        let found = DiagnosticsFindings.findings(broken, crashes: 1)
        #expect(found.count == 6)
        #expect(found.contains { $0.hasPrefix("1 new crash report attached") })
        // Siri finds apps Spotlight's index misses: not a finding any more.
        #expect(!found.contains { $0.contains("missing from Spotlight") })
        #expect(found.contains("Spotlight indexing is disabled"))
        #expect(found.contains("2 copies of NotchIsland are running at once"))
        #expect(DiagnosticsFindings.runsFrom(broken) == "The disk image")
    }
}

@Suite struct DiagnosticsCenterTests {
    private func defaults() -> UserDefaults {
        let name = "diagnostics-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test @MainActor func onByDefaultOffWhenTurnedOffWithAStableInstallID() {
        let store = defaults()
        let first = DiagnosticsCenter(defaults: store, destinations: DiagnosticsDestinations(), outbox: nil)
        // The standard mode costs nothing at rest: on unless the user turns it off.
        #expect(first.isEnabled && !first.isDetailed)
        #expect(first.sender == "Anonymous")
        first.name = "  Béla  "
        first.isEnabled = false
        let second = DiagnosticsCenter(defaults: store, destinations: DiagnosticsDestinations(), outbox: nil)
        #expect(second.installID == first.installID)
        #expect(!second.isEnabled)
        #expect(second.sender == "Béla")
    }

    @Test @MainActor func withoutAnAddressNothingIsSent() async {
        let center = DiagnosticsCenter(defaults: defaults(), destinations: DiagnosticsDestinations(), outbox: nil)
        #expect(!center.isConfigured)
        let delivered = await center.sendFeedback(.init(kind: .feature, title: "T", details: "D"), attachDiagnostics: false)
        #expect(!delivered)
        #expect(center.state == .failed("This build has no diagnostics address."))
    }
}

@Suite struct DiagnosticsEnergyTests {
    private func sample(_ seconds: TimeInterval, energyJ: Double, cpuS: Double, wakeups: UInt64,
                        battery: Bool = true, level: Int? = nil) -> EnergySample {
        EnergySample(date: Date(timeIntervalSince1970: seconds),
                     own: ProcessUsage(energyNJ: UInt64(energyJ * 1e9), cpuNS: UInt64(cpuS * 1e9), wakeups: wakeups, footprint: 100 * 1_048_576),
                     helpers: ProcessUsage(), onBattery: battery, batteryLevel: level, systemMW: battery ? 4000 : nil)
    }

    @Test func intervalTurnsCountersIntoRates() throws {
        let a = sample(0, energyJ: 0, cpuS: 0, wakeups: 0, level: 80)
        let b = sample(600, energyJ: 6, cpuS: 6, wakeups: 6000, level: 79)
        let interval = try #require(EnergyInterval(from: a, to: b))
        #expect(abs(interval.ownMW - 10) < 0.001)
        #expect(abs(interval.cpuPercent - 1) < 0.001)
        #expect(abs(interval.wakeupsPerSecond - 10) < 0.001)
        #expect(abs((interval.drainPerHour ?? 0) - 6) < 0.001)
        #expect(interval.footprintMB == 100)
    }

    @Test func aCounterGoingBackIsNoInterval() {
        #expect(EnergyInterval(from: sample(0, energyJ: 5, cpuS: 1, wakeups: 0), to: sample(600, energyJ: 1, cpuS: 2, wakeups: 0)) == nil)
    }

    @Test func summaryIsTimeWeighted() throws {
        let s0 = sample(0, energyJ: 0, cpuS: 0, wakeups: 0)
        let s1 = sample(100, energyJ: 1, cpuS: 0, wakeups: 0)     // 10 mW for 100 s
        let s2 = sample(400, energyJ: 1.6, cpuS: 0, wakeups: 0)   // 2 mW for 300 s
        let intervals = [EnergyInterval(from: s0, to: s1), EnergyInterval(from: s1, to: s2)].compactMap { $0 }
        let summary = try #require(EnergySummary(intervals))
        #expect(abs(summary.ownMW - 4) < 0.001)
        #expect(summary.systemMW == 4000)
        #expect(summary.line.contains("4.0 mW"))
    }

    @Test func ownProcessCanBeRead() throws {
        let usage = try #require(ProcessUsage.read(ProcessInfo.processInfo.processIdentifier))
        #expect(usage.cpuNS > 0)
        #expect(usage.footprint > 0)
    }
}

@Suite struct DiagnosticsBaselineTests {
    private let baseline = DiagnosticsBaseline(version: "0.4.4", build: "14", created: Date(timeIntervalSince1970: 0),
                                               machine: "Mac16,12", uptimeHours: 5,
                                               metrics: ["powerMW": 10, "wakeupsPerSecond": 5, "spotlightMissingPercent": 0],
                                               rules: ["wakeupsPerSecond": .init(factor: 10, minimum: 1)])

    @Test func flagsOnlyWhatIsPastBothMinimumAndFactor() {
        let result = DiagnosticsComparison.compare([.powerMW: 30, .wakeupsPerSecond: 40, .spotlightMissingPercent: 25, .crashes: 0], with: baseline)
        let unusual = Set(result.filter(\.isUnusual).map(\.metric))
        // 30 mW > 2.5 × 10 and ≥ 25; wakeups 40 < 10 × 5 (rule from the file); 25% missing vs 0.
        #expect(unusual == [.powerMW, .spotlightMissingPercent])
        #expect(result.first { $0.metric == .powerMW }?.line == "Energy use (since launch): 30.0 mW — 3.0× the reference (10.0 mW)")
    }

    @Test func belowTheMinimumIsNeverUnusual() {
        #expect(!DiagnosticsComparison.isUnusual(20, reference: 1, rule: .init(factor: 2.5, minimum: 25)))
    }

    @Test func countsNeedNoReference() {
        #expect(DiagnosticsComparison.isUnusual(1, reference: nil, rule: DiagnosticsMetric.crashes.defaultRule))
        #expect(!DiagnosticsComparison.isUnusual(40, reference: nil, rule: DiagnosticsMetric.powerMW.defaultRule))
    }

    @Test func baselineRoundTripsAsJSON() throws {
        let data = try DiagnosticsBaseline.encoder.encode(baseline)
        #expect(try DiagnosticsBaseline.decoder.decode(DiagnosticsBaseline.self, from: data) == baseline)
    }

    @Test func versionsCompareNumerically() {
        #expect(DiagnosticsVersions.isOlder("0.4.3.1", than: "v0.4.4"))
        #expect(DiagnosticsVersions.isOlder("0.4.9", than: "0.4.10"))
        #expect(!DiagnosticsVersions.isOlder("0.4.4", than: "0.4.4"))
        #expect(DiagnosticsVersions.normalized("v0.4.4") == "0.4.4")
    }

    @Test func anomaliesSkipCountsButExplainAnUncleanExit() {
        let comparisons = DiagnosticsComparison.compare([.powerMW: 30, .crashes: 2, .uncleanExits: 1], with: baseline)
        let found = DiagnosticsFindings.anomalies(comparisons, metrics: [.uncleanExits: 1], crashes: 0)
        #expect(found.count == 2)
        #expect(found[0].hasPrefix("Energy use"))
        #expect(found[1].hasPrefix("The previous run did not end normally"))
        #expect(DiagnosticsFindings.anomalies(comparisons, metrics: [.uncleanExits: 1], crashes: 1).count == 1)
    }
}

@Suite struct DiagnosticsRoutingTests {
    @Test func configFromInfoPlistOrTheOldSingleWebhook() {
        let json = #"{"users":"https://discord.com/api/webhooks/1/u","alerts":"https://discord.com/api/webhooks/2/a","guild":"42","bugTag":"7"}"#
        let routed = DiagnosticsDestinations.from(info: [DiagnosticsDestinations.infoKey: json])
        #expect(routed.users?.absoluteString == "https://discord.com/api/webhooks/1/u")
        #expect(routed.bugTag == "7")
        #expect(routed.link(channel: "5", message: "6")?.absoluteString == "https://discord.com/channels/42/5/6")
        let legacy = DiagnosticsDestinations.from(info: [DiagnosticsDestinations.legacyInfoKey: "https://discord.com/api/webhooks/3/x"])
        #expect(legacy.fallback != nil && legacy.users == nil && legacy.isConfigured)
        #expect(!DiagnosticsDestinations.from(info: nil).isConfigured)
    }

    @Test func threadIDGoesIntoTheQuery() {
        let url = DiagnosticsUploader.webhookURL(URL(string: "https://discord.com/api/webhooks/1/abc")!, threadID: "99")
        #expect(url.absoluteString == "https://discord.com/api/webhooks/1/abc?wait=true&thread_id=99")
    }

    @Test func alertLinksToTheDetails() throws {
        let envelope = DiagnosticsEnvelope(kind: .anomaly, reason: .anomaly, sender: "Béla", installID: "abc",
                                           facts: [.init(name: "Version", value: "0.4.4 (14)")],
                                           findings: ["Energy use: 40 mW"], feedback: nil, files: [])
        #expect(envelope.isAlert)
        let payload = DiagnosticsUploader.alertPayload(for: envelope, link: URL(string: "https://discord.com/channels/1/2/3"))
        let embed = try #require((payload["embeds"] as? [[String: Any]])?.first)
        #expect(embed["title"] as? String == "⚡ Unusual behaviour at Béla")
        let text = try #require(embed["description"] as? String)
        #expect(text.contains("⚠️ Energy use: 40 mW"))
        #expect(text.contains("[→ Open the details](https://discord.com/channels/1/2/3)"))
    }

    @Test func aQuietReportIsNoAlert() {
        let envelope = DiagnosticsEnvelope(kind: .report, sender: "B", installID: "a", facts: [], findings: [], feedback: nil, files: [])
        #expect(!envelope.isAlert)
    }

    @Test func threadNames() {
        #expect(DiagnosticsUploader.userThreadName(sender: "Béla", installID: "1a2b3c4d5e6f") == "👤 Béla · 1a2b3c4d")
        let bug = DiagnosticsEnvelope(kind: .bug, sender: "Béla", installID: "a", facts: [], findings: [],
                                      feedback: .init(kind: .bug, title: "No apps", details: "x"), files: [])
        #expect(DiagnosticsUploader.feedbackThreadName(bug) == "🐞 No apps — Béla")
    }
}

@Suite struct DiagnosticsHistoryTests {
    @Test @MainActor func noticesARunThatDidNotQuit() {
        let name = "history-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = DiagnosticsHistory(defaults: defaults, version: "0.4.4")
        #expect(!first.previousEndedUncleanly && first.launches == 1)
        first.markCleanExit()
        let second = DiagnosticsHistory(defaults: defaults, version: "0.4.4")
        #expect(!second.previousEndedUncleanly && second.launches == 2)
        // No clean exit this time: killed.
        let third = DiagnosticsHistory(defaults: defaults, version: "0.4.5")
        #expect(third.previousEndedUncleanly && third.uncleanExits == 1)
        #expect(third.versions.map(\.version) == ["0.4.4", "0.4.5"])
    }

    @Test func presentationKinds() {
        #expect(DiagnosticsHistory.kind(of: .expanded(.home)) == "expanded")
        #expect(DiagnosticsHistory.kind(of: .settings) == "settings")
    }

    @Test func errorLinesOfACompactLog() {
        let log = """
            Timestamp               Ty Process[PID:TID]
            2026-09-27 21:10:40.892 Df NotchIsland[1:2] [x] fine
            2026-09-27 21:10:41.000 E  NotchIsland[1:2] [x] broke
            2026-09-27 21:10:42.000 Fa NotchIsland[1:2] [x] fault
            """
        #expect(DiagnosticsProbes.errorLines(in: log).count == 2)
    }
}

@Suite struct PublishedBaselineTests {
    /// `docs/diagnostics-baseline.json` is what every copy downloads: it must decode, and its metric
    /// and rule names must be ones the app knows.
    @Test func publishedReferenceDecodes() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/diagnostics-baseline.json")
        let baseline = try DiagnosticsBaseline.decoder.decode(DiagnosticsBaseline.self, from: Data(contentsOf: url))
        let known = Set(DiagnosticsMetric.allCases.map(\.rawValue))
        #expect(Set(baseline.metrics.keys).isSubset(of: known))
        #expect(Set((baseline.rules ?? [:]).keys).isSubset(of: known))
        #expect(baseline.value(.powerMW) != nil)
    }
}

@Suite struct DiagnosticsMediaTests {
    private func picture(width: Int, height: Int, type: UTType) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + (type.preferredFilenameExtension ?? "img"))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func aSmallScreenshotIsSentAsItIs() async throws {
        let source = try picture(width: 400, height: 300, type: .png)
        let file = try await DiagnosticsMedia.prepare(source)
        defer { DiagnosticsMedia.discard([file]) }
        #expect(file.name == source.lastPathComponent)
        #expect(file.contentType == "image/png")
        #expect(!file.isVideo)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    /// HEIC and TIFF are not shown in Discord: they become JPEGs, no larger than the limit.
    @Test func otherPicturesBecomeJPEGs() async throws {
        let source = try picture(width: 3000, height: 2000, type: .tiff)
        let file = try await DiagnosticsMedia.prepare(source)
        defer { DiagnosticsMedia.discard([file]) }
        #expect(file.contentType == "image/jpeg")
        #expect(file.name.hasSuffix(".jpg"))
        #expect(file.bytes <= DiagnosticsMedia.maxBytes)
        let image = try #require(CGImageSourceCreateWithURL(file.url as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any]
        #expect((properties?[kCGImagePropertyPixelWidth] as? Int).map { $0 <= DiagnosticsMedia.maxPixels } == true)
    }

    @Test func onlyPicturesAndVideos() async {
        let text = FileManager.default.temporaryDirectory.appendingPathComponent("notes.txt")
        #expect(!DiagnosticsMedia.isSupported(text))
        #expect(DiagnosticsMedia.isSupported(URL(fileURLWithPath: "/tmp/a.mov")))
        #expect(DiagnosticsMedia.isSupported(URL(fileURLWithPath: "/tmp/a.PNG")))
        await #expect(throws: DiagnosticsMedia.Failure.unsupported("notes.txt")) {
            try await DiagnosticsMedia.prepare(text)
        }
    }

    @Test func aMediaMessageCarriesTheFileWithItsType() throws {
        let data = Data([0xFF, 0xD8, 0xFF, 0x00])
        let body = DiagnosticsUploader.mediaBody(payload: ["content": "🖼️ 1/1"], name: "shot\".jpg", contentType: "image/jpeg",
                                                 data: data, boundary: "B")
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("name=\"payload_json\""))
        #expect(text.contains("filename=\"shot.jpg\""))
        #expect(text.contains("Content-Type: image/jpeg"))
        #expect(body.range(of: data) != nil)
        #expect(text.hasSuffix("--B--\r\n"))
    }

    @Test func theReportListsItsScreenshots() throws {
        var envelope = DiagnosticsEnvelope(kind: .bug, reason: nil, sender: "Béla", installID: "abcdef123456", facts: [],
                                           findings: [], feedback: DiagnosticsFeedback(kind: .bug, title: "T", details: "D"), files: [])
        envelope.media = [DiagnosticsMediaFile(name: "rec.mp4", path: "/x", contentType: "video/mp4", bytes: 10, isVideo: true, wasTrimmed: true)]
        let embed = try #require((DiagnosticsUploader.payload(for: envelope)["embeds"] as? [[String: Any]])?.first)
        let fields = try #require(embed["fields"] as? [[String: Any]])
        let value = fields.first { ($0["name"] as? String)?.contains("Screenshots") == true }?["value"] as? String
        #expect(value?.contains("`rec.mp4` (cut to fit)") == true)
        // Kept in the outbox with the report.
        let decoded = try JSONDecoder().decode(DiagnosticsEnvelope.self, from: JSONEncoder().encode(envelope))
        #expect(decoded.media == envelope.media)
    }
}

@Suite struct DiagnosticsDetailTests {
    private func defaults() -> UserDefaults {
        let name = "diagnostics-detail-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func baseline(uptime: Double, machine: String = "Mac17,3 · Apple M5", metrics: [String: Double],
                          settings: [String: String]? = nil) -> DiagnosticsBaseline {
        DiagnosticsBaseline(version: "0.4.7", build: "17", created: Date(timeIntervalSince1970: 0), machine: machine,
                            uptimeHours: uptime, metrics: metrics, rules: nil, settings: settings)
    }

    @Test func jsonCarriesSectionsNumbersAndFindings() throws {
        var report = DiagnosticsReport()
        var section = DiagnosticsReport.Section("App")
        section.add("Version", "0.4.8")
        report.sections = [section]
        report.metrics = [.powerMW: 1.5]
        report.attachments = [.init(name: "log.txt", text: "x")]
        let comparisons = DiagnosticsComparison.compare(report.metrics, with: baseline(uptime: 9, metrics: ["powerMW": 0.5]))
        let text = report.json(meta: ["kind": "report"], findings: ["one"], comparisons: comparisons)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect((json["meta"] as? [String: String])?["kind"] == "report")
        #expect((json["findings"] as? [String]) == ["one"])
        #expect((json["metrics"] as? [String: Double])?["powerMW"] == 1.5)
        #expect((json["attachments"] as? [String]) == ["log.txt"])
        let sections = try #require(json["sections"] as? [[String: Any]])
        #expect(sections.first?["title"] as? String == "App")
        let compared = try #require((json["comparisons"] as? [[String: Any]])?.first)
        #expect(compared["reference"] as? Double == 0.5)
    }

    @Test func settingsAreComparedWithTheReference() {
        var report = DiagnosticsReport()
        report.sections = [
            .init("Menu bar, Dock & Spaces", [.init(key: "dock.autohide", value: "1"), .init(key: "dock.tilesize", value: "48")]),
            .init("App", [.init(key: "Version", value: "0.4.8")]),
        ]
        #expect(report.settings == ["Menu bar, Dock & Spaces › dock.autohide": "1", "Menu bar, Dock & Spaces › dock.tilesize": "48"])
        let lines = DiagnosticsReport.differences(report.settings, from: [
            "Menu bar, Dock & Spaces › dock.autohide": "0", "Menu bar, Dock & Spaces › dock.tilesize": "48",
            "Keyboard & input › fn / 🌐 key": "Show emoji & symbols",
        ])
        #expect(lines == ["Keyboard & input › fn / 🌐 key: — (reference: Show emoji & symbols)",
                          "Menu bar, Dock & Spaces › dock.autohide: 1 (reference: 0)"])
    }

    @Test func aShorterRunKeepsThePublishedNumbersButTakesTheSettings() {
        let old = baseline(uptime: 9, metrics: ["powerMW": 0.5, "memoryMB": 61])
        let new = baseline(uptime: 0.2, metrics: ["powerMW": 40, "worstPowerMW": 3], settings: ["a": "b"])
        let merged = DiagnosticsCenter.mergedBaseline(new, over: old)
        #expect(merged.metrics == ["powerMW": 0.5, "memoryMB": 61, "worstPowerMW": 3])
        #expect(merged.uptimeHours == 9)
        #expect(merged.settings == ["a": "b"])
        // A longer run, another Mac, or none published: the new one as it is.
        #expect(DiagnosticsCenter.mergedBaseline(baseline(uptime: 12, metrics: ["powerMW": 1]), over: old).metrics == ["powerMW": 1])
        #expect(DiagnosticsCenter.mergedBaseline(baseline(uptime: 1, machine: "Mac16,1", metrics: ["powerMW": 1]), over: old).metrics == ["powerMW": 1])
        #expect(DiagnosticsCenter.mergedBaseline(new, over: nil) == new)
    }

    @Test @MainActor func anUpdateOrACrashIsReportedSoon() {
        let store = defaults()
        let first = DiagnosticsHistory(defaults: store, version: "0.4.7")
        #expect(!first.isNewVersion)
        #expect(DiagnosticsCenter.firstReport(history: first, newCrash: false).reason == .launch)
        first.markCleanExit()
        let updated = DiagnosticsHistory(defaults: store, version: "0.4.8")
        #expect(updated.isNewVersion)
        #expect(DiagnosticsCenter.firstReport(history: updated, newCrash: false) == (.update, DiagnosticsCenter.urgentLaunchDelay))
        #expect(DiagnosticsCenter.firstReport(history: updated, newCrash: true).reason == .crash)
        // Not quit this time.
        let killed = DiagnosticsHistory(defaults: store, version: "0.4.8")
        #expect(!killed.isNewVersion)
        #expect(DiagnosticsCenter.firstReport(history: killed, newCrash: false).reason == .crash)
    }

    @Test @MainActor func aSecondSendByHandSoonAfterSendsNothing() async {
        let store = defaults()
        store.set(Date(), forKey: DiagnosticsCenter.lastSentKey)
        let center = DiagnosticsCenter(defaults: store, destinations: DiagnosticsDestinations(), outbox: nil)
        // Without an address a real send fails; this one is not attempted at all.
        #expect(await center.sendReport(.manual))
        #expect(center.state == .idle)
    }

    @Test @MainActor func intervalsWithAReportInThemAreNotJudged() throws {
        let meter = EnergyMeter(launchedAt: Date()) { .unknown }
        func sample(_ offset: TimeInterval, _ joules: Double) -> EnergySample {
            EnergySample(date: Date().addingTimeInterval(offset), own: ProcessUsage(energyNJ: UInt64(joules * 1e9), cpuNS: 1),
                         helpers: ProcessUsage(), onBattery: false)
        }
        let before = try #require(EnergyInterval(from: sample(-1200, 0), to: sample(-600, 1)))
        meter.beginCollecting()
        #expect(meter.isCollection(try #require(EnergyInterval(from: sample(-600, 1), to: sample(1, 2)))))
        meter.endCollecting()
        #expect(!meter.isCollection(before))
        #expect(meter.isCollection(try #require(EnergyInterval(from: sample(-600, 1), to: sample(600, 2)))))
        #expect(!meter.isCollection(try #require(EnergyInterval(from: sample(60, 2), to: sample(660, 3)))))
    }

    @Test func environmentReadsThisMac() {
        let keyboard = DiagnosticsEnvironment.keyboard()
        #expect(keyboard.entries.contains { $0.key == "⌘Space: Spotlight" })
        #expect(DiagnosticsEnvironment.format(["b": 1, "a": [true]]) == #"{"a":[true],"b":1}"#)
        #expect(DiagnosticsEnvironment.format(nil) == "—")
        let apps = DiagnosticsEnvironment.installedApps()
        #expect(apps.entries.contains { $0.key == DiagnosticsEnvironment.interferingKey })
    }
}
