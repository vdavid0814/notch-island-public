import Foundation
import Testing
@testable import NotchIslandKit

// Nothing here reaches Sentry or Mixpanel: the mapping is pure, and Mixpanel's requests go to a
// stub URLProtocol.

@Suite struct TelemetryConfigTests {
    @Test func readFromTheInfoPlistOrNothing() {
        #expect(!TelemetryConfig.from(info: nil).isConfigured)
        #expect(!TelemetryConfig.from(info: ["NITelemetry": ["sentryDSN": "  "]]).isConfigured)
        let config = TelemetryConfig.from(info: ["NITelemetry": [
            "sentryDSN": "https://key@o1.ingest.de.sentry.io/2", "mixpanelToken": "abc", "environment": "debug",
        ]])
        #expect(config.hasSentry && config.hasMixpanel)
        // The EU unless told otherwise.
        #expect(config.mixpanelHost == "api-eu.mixpanel.com" && config.environment == "debug")
    }

    @MainActor @Test func aBuildWithoutItSendsNoReportsButMayStillSendFeedbackToDiscord() {
        let defaults = UserDefaults(suiteName: "TelemetryConfigTests.\(UUID().uuidString)")!
        let center = DiagnosticsCenter(defaults: defaults, destinations: DiagnosticsDestinations(),
                                       telemetry: Telemetry(config: .none, defaults: defaults, queueFile: nil), outbox: nil)
        #expect(!center.sendsReports && !center.isConfigured)
    }
}

@Suite struct TelemetryMappingTests {
    @Test func whatWasTypedIsLeftOut() {
        #expect(TelemetryMapping.redacted(#"siri: "xcode" in root → 1 apps"#) == #"siri: "‹5›" in root → 1 apps"#)
        #expect(TelemetryMapping.redacted(#"Siri found no app for "tort", "dei""#) == #"Siri found no app for "‹4›", "‹3›""#)
        #expect(TelemetryMapping.redacted(#"half "open"#) == #"half "‹4›"#)
        #expect(TelemetryMapping.redacted("island idle → open") == "island idle → open")
    }

    @Test func eachLikelyCauseIsAnIssueGroupedByItsID() {
        var verdict = DiagnosticsVerdict()
        verdict.checks = [
            .init(id: "feature.Volume/brightness keys", severity: .issue, feature: "Volume/brightness keys",
                  title: "Volume/brightness keys is on but not running", action: "Allow Accessibility"),
            .init(id: "siri.noApp", severity: .warning, feature: "Siri", title: #"Siri found no app for "tort""#,
                  confidence: .medium),
            .init(id: "feature.AirPods", severity: .healthy, feature: "AirPods", title: "AirPods works"),
        ]
        let causes = TelemetryMapping.causes(verdict)
        #expect(causes.map(\.id) == ["feature.Volume/brightness keys", "siri.noApp"])
        #expect(causes[0].isIssue && !causes[1].isIssue)
        #expect(causes[1].message == #"[Siri] Siri found no app for "‹4›""#)
        #expect(causes[0].fingerprint == ["notchisland-cause", "feature.Volume/brightness keys"])
        #expect(TelemetryMapping.causes(nil).isEmpty)
    }

    @Test func onlyNotchIslandsOwnErrorLinesAreTakenAndGroupedWithoutNumbers() {
        var report = DiagnosticsReport()
        var section = DiagnosticsReport.Section("Errors by source")
        section.add("NotchIsland's own", "[com.davidvarga.notchisland:levels] 4×")
        section.add("4× [com.davidvarga.notchisland:levels]",
                    "2026-10-09 16:03:33.127 E  NotchIsland[37643:1b2e4e] [com.davidvarga.notchisland:levels] media key tap could not be created")
        section.add("6× [com.apple.coreui:framework]", "CoreUI: unable to find a bundle")
        report.sections = [section]
        let errors = TelemetryMapping.ownErrors(report)
        #expect(errors == [.init(category: "levels", count: 4, message: "media key tap could not be created")])
        #expect(TelemetryMapping.template("pid 407 at 979,832") == "pid N at N,N")
    }

    @Test func theWholeReportOnlyWhenAskedForOrSomethingHappened() {
        #expect(TelemetryMapping.sendsWholeReport(.manual) && TelemetryMapping.sendsWholeReport(.crash)
                && TelemetryMapping.sendsWholeReport(.anomaly) && TelemetryMapping.sendsWholeReport(.problem))
        #expect(!TelemetryMapping.sendsWholeReport(.periodic) && !TelemetryMapping.sendsWholeReport(.launch))
    }

    @Test func theSnapshotCarriesNumbersAndStatesButNoPaths() {
        var report = DiagnosticsReport()
        report.metrics = [.powerMW: 0.4567, .memoryMB: 61, .cpuPercent: .nan]
        var health = DiagnosticsReport.Section("Feature health")
        health.add("Volume/brightness keys", "paused (locked, asleep or a permission reset) — off")
        health.add("Now Playing", "✅ running — on")
        health.add("⌘Space for Siri", "⚠︎ wanted but not running")
        health.add("AirPods", "off (by the user)")
        var app = DiagnosticsReport.Section("App")
        app.add("Path", "/Users/someone/Downloads/NotchIsland.app")
        report.sections = [health, app]
        let snapshot = TelemetryMapping.snapshot(report, verdict: nil, reason: .periodic, light: true)
        #expect(snapshot["metric_powermw"] == .number(0.46) && snapshot["metric_memorymb"] == .number(61))
        #expect(snapshot["metric_cpupercent"] == nil)
        #expect(snapshot["feature_volume_brightness_keys"] == .string("paused"))
        #expect(snapshot["feature_now_playing"] == .string("running"))
        #expect(snapshot["feature_space_for_siri"] == .string("broken"))
        #expect(snapshot["feature_airpods"] == .string("off"))
        #expect(snapshot["runs_from"] == .string("elsewhere"))
        #expect(snapshot["reason"] == .string("periodic") && snapshot["light"] == .bool(true))
    }
}

@Suite(.serialized) struct MixpanelClientTests {
    func client(_ file: URL?) -> MixpanelClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MixpanelStub.self]
        return MixpanelClient(token: "tok", host: "api-eu.mixpanel.com", distinctID: "install-1",
                              common: ["app_version": .string("0.8.1")], file: file,
                              session: URLSession(configuration: configuration))
    }

    @Test func eventsCarryTheTokenTheInstallAndTheCommonProperties() throws {
        let client = client(nil)
        let event = MixpanelClient.Event(name: "Health Snapshot", properties: ["metric_powermw": .number(0.4)],
                                         time: Date(timeIntervalSince1970: 1_000), insertID: "x")
        let objects = try JSONSerialization.jsonObject(with: client.body([event])) as! [[String: Any]]
        let properties = objects[0]["properties"] as! [String: Any]
        #expect(objects[0]["event"] as? String == "Health Snapshot")
        #expect(properties["token"] as? String == "tok" && properties["distinct_id"] as? String == "install-1")
        #expect(properties["time"] as? Int == 1_000_000 && properties["$insert_id"] as? String == "x")
        #expect(properties["app_version"] as? String == "0.8.1" && properties["metric_powermw"] as? Double == 0.4)
        // No location: Mixpanel is told not to read the address.
        #expect(client.endpoint.absoluteString == "https://api-eu.mixpanel.com/track?ip=0&verbose=1")
    }

    @Test func theQueueSurvivesARelaunchAndEmptiesWhenSent() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mixpanel-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        MixpanelStub.answer = (503, #"{"status": 0, "error": "down"}"#)
        let first = client(file)
        for index in 0..<60 { first.track("E\(index)") }
        #expect(await first.flush() == false)
        #expect(first.pending == 60)
        // Read back from the file by the next launch; two batches (50 + 10) go.
        MixpanelStub.answer = (200, #"{"status": 1}"#)
        MixpanelStub.requests = 0
        let second = client(file)
        #expect(second.pending == 60)
        #expect(await second.flush())
        #expect(second.pending == 0 && MixpanelStub.requests == 2)
        // Too old for /track: dropped, not sent.
        second.track("Old", at: Date().addingTimeInterval(-MixpanelClient.maxAge - 60))
        MixpanelStub.requests = 0
        #expect(await second.flush())
        #expect(second.pending == 0 && MixpanelStub.requests == 0)
    }
}

/// Answers Mixpanel's requests in tests.
nonisolated final class MixpanelStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answer: (Int, String) = (200, #"{"status": 1}"#)
    nonisolated(unsafe) static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests += 1
        let (status, body) = Self.answer
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
