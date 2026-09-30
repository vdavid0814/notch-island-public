import AppKit
import CoreBluetooth

/// Something Spotlight's System suggestion (⌘5) runs: one of the island's own commands, a
/// Control Center switch, or one of the Mac's (Lock, Sleep, Restart…).
nonisolated enum AssistantCommand: Hashable, Sendable {
    /// A panel page the island actions do not already open (Home).
    case page(ExpandedPage)
    /// A tab of the island's Settings.
    case settings(IslandSettingsPane)
    /// The island stays open (`AppCommand.togglePin`).
    case keepOpen
    /// A countdown of a typed length ("timer 10", "10 min timer").
    case timer(minutes: Double)
    case cancelTimer
    /// A widget's editor (Settings ▸ Widgets), for a widget on the board.
    case editWidget(IslandWidgetKind)
    /// Window Anchor: the window in front goes under the notch; the one held there is let go.
    case anchorWindow, releaseWindow
    case control(SystemControl)
    case mac(MacCommand)

    /// The Control Center items Spotlight lists: the switches (read before they switch) and the
    /// two that open something.
    static let controls: [SystemControl] = [.wifi, .bluetooth, .darkMode, .nightShift, .keepAwake, .microphone, .airDrop, .focus]

    var id: String {
        switch self {
        case .page(let page): "page:\(page.rawValue)"
        case .settings(let pane): "settings:\(pane.rawValue)"
        case .keepOpen: "keepOpen"
        case .timer(let minutes): "timer:\(minutes)"
        case .cancelTimer: "cancelTimer"
        case .editWidget(let kind): "widget:\(kind.rawValue)"
        case .anchorWindow: "anchorWindow"
        case .releaseWindow: "releaseWindow"
        case .control(let control): "control:\(control.rawValue)"
        case .mac(let command): "mac:\(command.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .page(let page): page == .home ? String(localized: "Open Island") : String(localized: "Open \(page.title)")
        case .settings(let pane): String(localized: "Island Settings: \(pane.title)")
        case .keepOpen: String(localized: "Keep Island Open")
        case .timer(let minutes): String(localized: "Start Timer for \(Self.duration(minutes))")
        case .cancelTimer: String(localized: "Cancel Timer")
        case .editWidget(let kind): String(localized: "Edit \(kind.title) Widget")
        case .anchorWindow: String(localized: "Anchor Front Window")
        case .releaseWindow: String(localized: "Release Window")
        case .control(let control): control.title
        case .mac(let command): command.title
        }
    }

    /// What the user may type to find it: its title, and the other words people use for it.
    var searchNames: [String] {
        switch self {
        case .page(let page): [title, page.title]
        case .settings(let pane): [title, "NotchIsland \(pane.title)", "Settings \(pane.title)"]
        case .keepOpen: [title, "Pin Island", "Keep Open"]
        case .timer: [title]
        case .cancelTimer: [title, "Stop Timer"]
        case .editWidget(let kind): [title, "Customize \(kind.title)", "\(kind.title) Widget"]
        case .anchorWindow: [title, "Anchor Window", "Window Under Notch", "Hold Window"]
        case .releaseWindow: [title, "Release Anchored Window", "Unanchor Window", "Anchor Window"]
        case .control(let control): [control.title] + Self.synonyms(of: control)
        case .mac(let command): [command.title] + command.synonyms
        }
    }

    var symbol: String {
        switch self {
        case .page(let page): page == .home ? "house.fill" : page.systemImage
        case .settings(let pane): pane.systemImage
        case .keepOpen: "pin.fill"
        case .timer: "timer"
        case .cancelTimer: "stop.circle.fill"
        case .editWidget(let kind): kind.systemImage
        case .anchorWindow, .releaseWindow: "rectangle.topthird.inset.filled"
        case .control(let control): control.symbol(on: true)
        case .mac(let command): command.symbol
        }
    }

    /// The island's own commands go through the app (which also closes Spotlight).
    var appCommand: AppCommand? {
        switch self {
        case .page(let page): .open(page)
        case .settings(let pane): .showSettingsPane(pane)
        case .keepOpen: .togglePin
        case .timer(let minutes): .startTimer(minutes: minutes)
        case .cancelTimer: .cancelTimer
        case .editWidget(let kind): .editWidget(.kind(kind))
        case .anchorWindow: .anchorFrontWindow
        case .releaseWindow: .releaseAnchoredWindow
        case .control, .mac: nil
        }
    }

    /// A switch with an On/Off state the row shows.
    var hasState: Bool {
        switch self {
        case .keepOpen: true
        case .control(let control): !control.isAction
        default: false
        }
    }

    private static func synonyms(of control: SystemControl) -> [String] {
        switch control {
        case .wifi: ["WiFi", "Wireless", "WLAN"]
        case .bluetooth: ["BT"]
        case .darkMode: ["Light Mode", "Appearance", "Theme"]
        case .nightShift: ["Blue Light", "Warm Screen"]
        case .keepAwake: ["Caffeinate", "Caffeine", "Prevent Sleep", "Stay Awake"]
        case .microphone: ["Mic", "Mute Microphone"]
        case .airDrop: ["Share Files"]
        case .focus: ["Do Not Disturb", "DND"]
        default: []
        }
    }

    /// "10 minutes", "1 hour, 30 minutes".
    static func duration(_ minutes: Double) -> String {
        Duration.seconds((minutes * 60).rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// The minutes of a typed timer: "timer 10", "10 min timer", "timer 1.5 h", "90s timer",
    /// "időzítő 10 perc". The word timer and one number, with an optional unit (minutes without
    /// one); nil for anything else, and beyond `AppCommand.maximumTimerMinutes`.
    static func timerMinutes(in text: String) -> Double? {
        let text = text.lowercased().replacingOccurrences(of: ",", with: ".")
        // "10min" and "90s" split into a number and its unit.
        var words: [String] = []
        for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            if let split = word.firstIndex(where: \.isLetter), split != word.startIndex, Double(word[..<split]) != nil {
                words += [String(word[..<split]), String(word[split...])]
            } else {
                words.append(word)
            }
        }
        guard words.contains(where: { timerWords.contains($0) }) else { return nil }
        var number: Double?
        var scale = 1.0
        for word in words where !timerWords.contains(word) && !fillerWords.contains(word) {
            if let value = Double(word), number == nil {
                number = value
            } else if let unit = units[word], number != nil {
                scale = unit
            } else {
                return nil
            }
        }
        guard let number, number.isFinite, number > 0 else { return nil }
        let minutes = number * scale
        return minutes <= AppCommand.maximumTimerMinutes ? minutes : nil
    }

    private static let timerWords: Set<String> = ["timer", "countdown", "időzítő", "időzítés"]
    private static let fillerWords: Set<String> = ["start", "set", "a", "for", "of", "new", "indíts", "egy"]
    private static let units: [String: Double] = [
        "m": 1, "min": 1, "mins": 1, "minute": 1, "minutes": 1, "perc": 1, "percre": 1, "perces": 1,
        "h": 60, "hr": 60, "hrs": 60, "hour": 60, "hours": 60, "óra": 60, "órás": 60, "órára": 60,
        "s": 1 / 60, "sec": 1 / 60, "secs": 1 / 60, "second": 1 / 60, "seconds": 1 / 60, "mp": 1 / 60, "másodperc": 1 / 60,
    ]
}

/// The Mac's own commands. Restart, Shut Down and Log Out show macOS's confirmation; Empty Trash
/// asks for a second Return in its row first (`AssistantModel.confirming`).
nonisolated enum MacCommand: String, CaseIterable, Hashable, Sendable {
    case lock, sleep, displaySleep, screenSaver, showDesktop, missionControl, restart, shutDown, logOut, emptyTrash

    var title: String {
        switch self {
        case .lock: String(localized: "Lock Screen")
        case .sleep: String(localized: "Sleep")
        case .displaySleep: String(localized: "Turn Display Off")
        case .screenSaver: String(localized: "Start Screen Saver")
        case .showDesktop: String(localized: "Show Desktop")
        case .missionControl: String(localized: "Mission Control")
        case .restart: String(localized: "Restart…")
        case .shutDown: String(localized: "Shut Down…")
        case .logOut: String(localized: "Log Out…")
        case .emptyTrash: String(localized: "Empty Trash")
        }
    }

    var synonyms: [String] {
        switch self {
        case .lock: ["Lock"]
        case .sleep: ["Suspend"]
        case .displaySleep: ["Display Sleep", "Screen Off", "Sleep Display"]
        case .screenSaver: ["Screen Saver", "Screensaver"]
        case .showDesktop: ["Desktop"]
        case .missionControl: ["Exposé", "Spaces"]
        case .restart: ["Reboot"]
        case .shutDown: ["Shutdown", "Power Off", "Turn Off"]
        case .logOut: ["Logout", "Sign Out"]
        case .emptyTrash: ["Trash", "Bin"]
        }
    }

    var symbol: String {
        switch self {
        case .lock: "lock.fill"
        case .sleep: "moon.zzz.fill"
        case .displaySleep: "display"
        case .screenSaver: "play.display"
        case .showDesktop: "menubar.dock.rectangle"
        case .missionControl: "rectangle.3.group.fill"
        case .restart: "restart"
        case .shutDown: "power"
        case .logOut: "rectangle.portrait.and.arrow.right"
        case .emptyTrash: "trash.fill"
        }
    }
}

/// What Spotlight's commands do to the Mac, and the running apps it switches between. The app
/// gives the model the live one; a model made without it does nothing, so a test can never lock,
/// sleep, restart or empty anything.
struct AssistantSystem {
    /// A switch's state as the system has it now; nil when there is none to show. `mayAsk`: a read
    /// that may bring up a permission prompt is allowed (Bluetooth's, the first time).
    var state: (_ command: AssistantCommand, _ mayAsk: Bool) -> Bool? = { _, _ in nil }
    /// Switches a Control Center item to `on`, or opens it (AirDrop, Focus).
    var setControl: (SystemControl, _ on: Bool) -> Void = { _, _ in }
    var run: (MacCommand) -> Void = { _ in }
    /// A System Settings pane, an app or a file.
    var open: (URL) -> Void = { _ in }
    /// Brings the app and that window to the front.
    var switchTo: (AssistantWindow) -> Void = { _ in }
    var hide: (AssistantWindow) -> Void = { _ in }
    /// Quits the app; macOS asks about unsaved documents itself.
    var quit: (AssistantWindow) -> Void = { _ in }
    /// Shows a file in Quick Look; `closed` when its panel goes.
    var quickLook: (URL, _ closed: @escaping () -> Void) -> Void = { _, closed in closed() }
    /// Shows a file or an app in Finder.
    var reveal: (URL) -> Void = { _ in }

    static func live(controls: SystemControls, isPinned: @escaping () -> Bool) -> AssistantSystem {
        AssistantSystem(
            state: { command, mayAsk in
                switch command {
                case .keepOpen:
                    return isPinned()
                case .control(let control) where !control.isAction:
                    // Reading Bluetooth asks for its permission the first time: a row only shows
                    // it once given.
                    if control == .bluetooth, !mayAsk, CBManager.authorization != .allowedAlways { return nil }
                    return controls.liveState(of: control)
                default:
                    return nil
                }
            },
            setControl: { controls.set($0, to: $1) },
            run: { MacCommands.run($0, controls: controls) },
            open: { NSWorkspace.shared.open($0) },
            switchTo: RunningWindows.switchTo,
            hide: { NSRunningApplication(processIdentifier: $0.pid)?.hide() },
            quit: { NSRunningApplication(processIdentifier: $0.pid)?.terminate() },
            quickLook: { QuickLookPreview.shared.show($0, closed: $1) },
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        )
    }
}

/// How the Mac's commands are carried out (`MacCommand`).
enum MacCommands {
    static func run(_ command: MacCommand, controls: SystemControls) {
        Log.app.info("assistant: \(command.rawValue, privacy: .public)")
        switch command {
        // Control Center's own Lock Screen.
        case .lock: controls.set(.lockScreen, to: true)
        case .sleep: pmset("sleepnow")
        // The one implementation: SystemControl.showDesktop/.missionControl/.displaySleep (ExtendedControls) must call MacCommands.run.
        case .displaySleep: pmset("displaysleepnow")
        case .screenSaver: open("/System/Library/CoreServices/ScreenSaverEngine.app")
        case .showDesktop: dock("com.apple.showdesktop.awake")
        case .missionControl: open("/System/Applications/Mission Control.app")
        case .restart: send(kCoreEventClass, kAEShowRestartDialog, to: loginWindow, waits: false)
        case .shutDown: send(kCoreEventClass, kAEShowShutdownDialog, to: loginWindow, waits: false)
        case .logOut: send(kCoreEventClass, kAELogOut, to: loginWindow, waits: false)
        // Finder's own Empty Trash (its sound, locked items and all); the first time macOS asks
        // whether NotchIsland may control Finder.
        case .emptyTrash: send(finderSuite, emptyEvent, to: "com.apple.finder", waits: true)
        }
    }

    private static let loginWindow = "com.apple.loginwindow"
    private static let finderSuite: AEEventClass = 0x666E_6472   // 'fndr'
    private static let emptyEvent: AEEventID = 0x656D_7074      // 'empt'

    private static func pmset(_ argument: String) {
        do {
            try Process.run(URL(fileURLWithPath: "/usr/bin/pmset"), arguments: [argument])
        } catch {
            Log.app.error("assistant: pmset \(argument, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func open(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private static let applicationServices = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
    private typealias DockNotification = @convention(c) (CFString, Int32) -> Void

    /// The Dock's own gestures (Show Desktop), as the trackpad and hot corners send them.
    private static func dock(_ notification: String) {
        guard let symbol = dlsym(applicationServices, "CoreDockSendNotification") else {
            Log.app.error("assistant: the Dock's notifications are unavailable")
            return
        }
        unsafeBitCast(symbol, to: DockNotification.self)(notification as CFString, 0)
    }

    /// An Apple Event, sent off the main thread: the first one to an app may wait on macOS's
    /// Automation prompt.
    private static func send(_ eventClass: some BinaryInteger, _ eventID: some BinaryInteger, to bundleID: String, waits: Bool) {
        let eventClass = AEEventClass(eventClass), eventID = AEEventID(eventID)
        Task.detached(priority: .userInitiated) {
            let event = NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID,
                                               targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleID),
                                               returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            do {
                _ = try event.sendEvent(options: waits ? [.waitForReply] : [.noReply], timeout: 30)
            } catch {
                Log.app.error("assistant: Apple Event to \(bundleID, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
