import Foundation

/// Where crashes, errors and the health numbers go (About ▸ Diagnostics, only when the user turned
/// it on): Sentry for crashes, hangs, errors and the likely causes; Mixpanel for the hourly health
/// numbers. Both in the EU. Written into the build by `Scripts/build.sh` from
/// `Support/telemetry.json` (git-ignored: `Support/telemetry.example.json` shows its keys); a build
/// without it sends nothing.
nonisolated struct TelemetryConfig: Sendable, Equatable {
    static let infoKey = "NITelemetry"
    static let defaultMixpanelHost = "api-eu.mixpanel.com"

    /// The Sentry project's DSN (an EU one ends in `ingest.de.sentry.io`).
    var sentryDSN: String?
    /// The Mixpanel project's token (public by design: every client carries it).
    var mixpanelToken: String?
    /// Mixpanel's ingestion host: the EU data centre unless told otherwise.
    var mixpanelHost = Self.defaultMixpanelHost
    /// "debug" or "release" (Sentry's environment, a Mixpanel property).
    var environment = "release"

    var hasSentry: Bool { sentryDSN.map { !$0.isEmpty } ?? false }
    var hasMixpanel: Bool { mixpanelToken.map { !$0.isEmpty } ?? false }
    var isConfigured: Bool { hasSentry || hasMixpanel }

    static let none = TelemetryConfig()

    static func from(info: [String: Any]?) -> TelemetryConfig {
        guard let values = info?[infoKey] as? [String: Any] else { return .none }
        func text(_ key: String) -> String? {
            (values[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        var config = TelemetryConfig()
        config.sentryDSN = text("sentryDSN")
        config.mixpanelToken = text("mixpanelToken")
        if let host = text("mixpanelHost") { config.mixpanelHost = host }
        if let environment = text("environment") { config.environment = environment }
        return config
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
