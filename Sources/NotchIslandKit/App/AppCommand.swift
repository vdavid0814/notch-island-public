import Foundation

/// Fake state for screenshots and visual verification. Kept in release builds on purpose: it is how
/// the island is checked without waiting for a charger, a timer or a track change.
nonisolated enum DemoCommand: Sendable, Equatable {
    case media, charging, unplug, low, volume(Double), brightness(Double), timerDone, drop, shelf, reset
    /// Pointer over / away from the island, without moving the real pointer.
    case hover(Bool)
    /// Logs presentation, stage and where SwiftUI actually placed the island.
    case state
    /// Logs every segmented control on screen: its frame and the width it wants.
    case segments
    /// The AirPods-connected banner with sample batteries.
    case airPods
    /// The card for the AirPods' noise control changing (`demo/airpodsmode?mode=anc|transparency|adaptive|off`).
    case airPodsMode(AirPodsListeningMode)
    /// The timer widget's ruler moves on to its next unit (hours → minutes → seconds).
    case timerUnit
    /// The battery page on a made-up day (`BatteryHistory.demoRecords`), never written to the history.
    case batteryHistory
    /// Siri opened on its app gallery (as ⌘Space then ⌘1).
    case siriApps
    /// Siri opened on the clipboard history (as ⌘Space then ⌘4).
    case siriClipboard
    /// Types `text` into Siri a letter every 120 ms, as a person would (for measuring a search).
    case siriType(String)
    /// Switches the island's surface style, as the Settings cards do (animated).
    case surface(IslandGlassStyle)
    /// Holds every island spring this long after its start (nil: runs them again), so single frames
    /// of a transition can be compared.
    case freeze(TimeInterval?)
}

/// The widget a `widget/…` link means: the first on the board of a kind, or one instance.
nonisolated enum WidgetTarget: Sendable, Equatable {
    case kind(IslandWidgetKind)
    case instance(WidgetID)
}

/// Everything the app can be asked to do from outside the island: the menu bar menu and the
/// `notchisland://` URL scheme. An agent app has no window to click, so the scheme is also what makes
/// it scriptable (Shortcuts, `open`, tests).
nonisolated enum AppCommand: Sendable, Equatable {
    case open(ExpandedPage?), close, togglePin
    case media(MediaCommand)
    case startTimer(minutes: Double), cancelTimer, startStopwatch
    case showSettings
    /// Settings on one tab (`settings/widgets`…).
    case showSettingsPane(IslandSettingsPane)
    /// A widget's editor in Settings ▸ Widgets (`widget/timer`, `widget/<id>`).
    case editWidget(WidgetTarget)
    /// The widget editor (Customize Island).
    case customize
    /// ⌘Space (Siri or Spotlight), from the notch.
    case assistant
    /// A diagnostics report now (`diagnostics/send`); only while the user has diagnostics on.
    case sendDiagnostics
    /// The hourly report now (light unless a full one is due): for measuring its cost.
    case sendPeriodicDiagnostics
    /// The developer's Mac writes its numbers as the reference (`diagnostics/baseline`).
    case publishBaseline
    case demo(DemoCommand)

    static let scheme = "notchisland"
    /// `timer` without `minutes`.
    static let defaultTimerMinutes: Double = 5
    /// Upper bound for URL-started timers (24 h); anything longer is almost certainly a typo.
    static let maximumTimerMinutes: Double = 24 * 60
    static let defaultDemoVolume = 0.6
    static let defaultDemoBrightness = 0.4

    /// Parses `notchisland://<route>[?query]`.
    ///
    /// Routes and parameter names are case-insensitive; both `notchisland://media/next` and
    /// `notchisland:media/next` work. Unknown routes and malformed parameters return nil (so the
    /// caller can log them) instead of guessing.
    ///
    ///     open[?page=home|shelf|timer|battery]   close   pin   settings[/general|widgets|activities|permissions|about]
    ///     customize   widget/<kind>|<id>   siri   diagnostics/send   diagnostics/baseline
    ///     media/play|pause|toggle|next|previous
    ///     timer[?minutes=N]   timer/cancel   stopwatch
    ///     demo/media|charging|unplug|low|timerdone|drop|shelf|batteryhistory|reset
    ///     demo/volume[?level=0…1]   demo/brightness[?level=0…1]
    ///     demo/hover[?inside=1|0]   demo/state   demo/surface?style=smoked|black|fade   demo/airpods
    ///     demo/freeze[?t=seconds]
    static func parse(_ url: URL) -> AppCommand? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        var segments: [String] = []
        if let host = components.host, !host.isEmpty { segments.append(host) }
        segments += components.path.split(separator: "/").map(String.init)
        let route = segments.map { $0.lowercased() }.joined(separator: "/")

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name.lowercased()] == nil {
            query[item.name.lowercased()] = item.value ?? ""
        }

        switch route {
        case "open":
            guard let page = query["page"] else { return .open(nil) }
            return ExpandedPage(rawValue: page.lowercased()).map { .open($0) }
        case "close": return .close
        case "pin": return .togglePin
        case "settings": return .showSettings
        case let route where route.hasPrefix("widget/"):
            let name = String(route.dropFirst("widget/".count))
            if let id = WidgetID(string: name) { return .editWidget(.instance(id)) }
            return IslandWidgetKind.allCases.first { $0.rawValue.lowercased() == name }.map { .editWidget(.kind($0)) }
        case let route where route.hasPrefix("settings/"):
            return IslandSettingsPane.named(String(route.dropFirst("settings/".count))).map { .showSettingsPane($0) }
        case "customize": return .customize
        case "assistant", "siri": return .assistant
        case "diagnostics/send": return .sendDiagnostics
        case "diagnostics/periodic": return .sendPeriodicDiagnostics
        case "diagnostics/baseline": return .publishBaseline

        case "media/play": return .media(.play)
        case "media/pause": return .media(.pause)
        case "media/toggle": return .media(.togglePlayPause)
        case "media/next": return .media(.next)
        case "media/previous": return .media(.previous)

        case "timer":
            guard let raw = query["minutes"] else { return .startTimer(minutes: defaultTimerMinutes) }
            guard let minutes = Double(raw), minutes > 0, minutes <= maximumTimerMinutes else { return nil }
            return .startTimer(minutes: minutes)
        case "timer/cancel": return .cancelTimer
        case "stopwatch": return .startStopwatch

        case "demo/media": return .demo(.media)
        case "demo/charging": return .demo(.charging)
        case "demo/unplug": return .demo(.unplug)
        case "demo/low": return .demo(.low)
        case "demo/timerdone": return .demo(.timerDone)
        case "demo/drop": return .demo(.drop)
        case "demo/shelf": return .demo(.shelf)
        case "demo/reset": return .demo(.reset)
        case "demo/volume":
            return level(query["level"], default: defaultDemoVolume).map { .demo(.volume($0)) }
        case "demo/brightness":
            return level(query["level"], default: defaultDemoBrightness).map { .demo(.brightness($0)) }
        case "demo/hover":
            switch query["inside"]?.lowercased() {
            case nil, "1", "true": return .demo(.hover(true))
            case "0", "false": return .demo(.hover(false))
            default: return nil
            }
        case "demo/state": return .demo(.state)
        case "demo/segments": return .demo(.segments)
        case "demo/airpods": return .demo(.airPods)
        case "demo/airpodsmode":
            let modes: [String: AirPodsListeningMode] = ["anc": .noiseCancellation, "transparency": .transparency,
                                                         "adaptive": .adaptive, "off": .off]
            return modes[query["mode"]?.lowercased() ?? "anc"].map { .demo(.airPodsMode($0)) }
        case "demo/timerunit": return .demo(.timerUnit)
        case "demo/batteryhistory": return .demo(.batteryHistory)
        case "demo/siriapps": return .demo(.siriApps)
        case "demo/siriclipboard": return .demo(.siriClipboard)
        case "demo/siritype": return .demo(.siriType(query["text"] ?? "notch"))
        case "demo/surface":
            return query["style"].flatMap { IslandGlassStyle(rawValue: $0.lowercased()) }.map { .demo(.surface($0)) }
        case "demo/freeze":
            guard let raw = query["t"] else { return .demo(.freeze(nil)) }
            guard let time = TimeInterval(raw), time >= 0 else { return nil }
            return .demo(.freeze(time))

        default: return nil
        }
    }

    /// A 0…1 level; missing means `fallback`, out of range or non-numeric means invalid.
    private static func level(_ raw: String?, default fallback: Double) -> Double? {
        guard let raw else { return fallback }
        guard let value = Double(raw), (0...1).contains(value) else { return nil }
        return value
    }
}
