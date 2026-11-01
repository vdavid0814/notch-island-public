import AppKit

/// A display the island can live on, named so a choice outlives a reconnection: its display id
/// changes every time it is plugged in, its vendor, model and serial do not.
nonisolated struct ScreenID: Sendable, Hashable, Codable {
    /// "builtin" for the Mac's own screen, else "vendor-model-serial" (with "#2" for a second one
    /// alike and without a serial).
    var key: String
    /// The name macOS gives it ("MAG 321CQ E18", "Built-in Retina Display").
    var name: String

    static let builtInKey = "builtin"

    var isBuiltIn: Bool { key == Self.builtInKey }

    /// For a segment of a bar: a long monitor name is cut.
    var shortName: String {
        let limit = 18
        return name.count > limit ? String(name.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" : name
    }
}

/// Where the island lives (Settings ▸ Live Activities ▸ Displays, and the notice that comes when a
/// display is connected).
nonisolated enum IslandScreenChoice: Sendable, Hashable, Codable {
    /// The screen with a notch, else the menu bar's (as it always was): `NSScreen.screens.first`,
    /// not `NSScreen.main`, which follows the key window and would move the island between
    /// displays as focus changes.
    case automatic
    /// The MacBook's own screen, while it is open.
    case builtIn
    /// A monitor: this one when it is connected, else any monitor; nil: any monitor.
    case external(ScreenID?)

    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .builtIn: "MacBook"
        case .external(let id): id?.shortName ?? String(localized: "Monitor")
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "sparkles.rectangle.stack"
        case .builtIn: "laptopcomputer"
        case .external: "display"
        }
    }
}

/// A screen as the island sees it: where its notch is and which display it is.
nonisolated struct ScreenCandidate: Sendable, Equatable {
    var metrics: NotchMetrics
    var id: ScreenID

    var isBuiltIn: Bool { metrics.isBuiltin }

    /// What picking this screen in a bar sets.
    var choice: IslandScreenChoice { isBuiltIn ? .builtIn : .external(id) }
}

nonisolated enum IslandScreenPicker {
    /// The screen the island goes on, from the screens in menu-bar order (the first owns it).
    ///
    /// A choice that cannot be met falls back rather than hiding the island: the MacBook's screen
    /// closed (clamshell) → automatic; the monitor chosen not connected → another monitor, else
    /// automatic.
    static func pick(_ screens: [ScreenCandidate], choice: IslandScreenChoice) -> ScreenCandidate? {
        switch choice {
        case .automatic:
            return screens.first(where: \.metrics.isPhysical) ?? screens.first
        case .builtIn:
            return screens.first(where: \.isBuiltIn) ?? pick(screens, choice: .automatic)
        case .external(let id):
            let monitors = screens.filter { !$0.isBuiltIn }
            if let id, let exact = monitors.first(where: { $0.id.key == id.key }) { return exact }
            return monitors.first ?? pick(screens, choice: .automatic)
        }
    }

    /// The choices a bar offers: Automatic (optional), the MacBook (on a Mac with its own screen,
    /// open or closed), every monitor connected, and the monitor chosen before if it is not
    /// connected now (or a plain "Monitor" while none is).
    static func choices(screens: [ScreenCandidate], current: IslandScreenChoice, hasBuiltIn: Bool,
                        includesAutomatic: Bool) -> [IslandScreenChoice] {
        var choices: [IslandScreenChoice] = includesAutomatic ? [.automatic] : []
        if hasBuiltIn || screens.contains(where: \.isBuiltIn) { choices.append(.builtIn) }
        let monitors = screens.filter { !$0.isBuiltIn }.map { IslandScreenChoice.external($0.id) }
        choices += monitors
        if case .external(let saved?) = current, !monitors.contains(.external(saved)) {
            choices.append(current)
        } else if monitors.isEmpty {
            choices.append(.external(nil))
        }
        return choices
    }

    /// The choice in `choices` that stands for `current` (a saved monitor that is the one
    /// connected, "any monitor" while one is).
    static func selection(in choices: [IslandScreenChoice], current: IslandScreenChoice) -> IslandScreenChoice {
        if choices.contains(current) { return current }
        if case .external = current, let monitor = choices.first(where: { if case .external = $0 { true } else { false } }) {
            return monitor
        }
        return choices.first ?? current
    }

    /// The display ids that were not there before, among `screens`: the monitors just connected.
    static func connected(_ screens: [ScreenCandidate], since known: Set<String>) -> [ScreenCandidate] {
        screens.filter { !$0.isBuiltIn && !known.contains($0.id.key) }
    }
}

extension ScreenLocator {
    /// Every screen, in menu-bar order, each with its lasting id.
    static func candidates() -> [ScreenCandidate] {
        var seen: [String: Int] = [:]
        return NSScreen.screens.compactMap { screen -> ScreenCandidate? in
            guard let metrics = metrics(for: screen) else { return nil }
            let id = metrics.displayID
            var key = ScreenID.builtInKey
            if !metrics.isBuiltin {
                key = "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
                seen[key, default: 0] += 1
                if let count = seen[key], count > 1 { key += "#\(count)" }
            }
            let name = metrics.isBuiltin ? String(localized: "MacBook") : screen.localizedName
            return ScreenCandidate(metrics: metrics, id: ScreenID(key: key, name: name))
        }
    }

    /// The island's screen for the user's choice.
    static func preferred(choice: IslandScreenChoice) -> NotchMetrics? {
        IslandScreenPicker.pick(candidates(), choice: choice)?.metrics
    }
}
