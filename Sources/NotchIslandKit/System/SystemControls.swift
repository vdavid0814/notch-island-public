import AppKit
import CoreAudio
import CoreWLAN
import IOKit.pwr_mgt

/// A Control Center switch; each is its own widget (`IslandWidgetKind.systemControl`).
nonisolated enum SystemControl: String, Sendable, Codable, CaseIterable, Identifiable {
    case wifi, bluetooth, airDrop, darkMode, nightShift, keepAwake, microphone
    // Actions, like Control Center's app and utility controls: they open or do one thing.
    case calculator, voiceMemos, screenshot, notes, lockScreen, focus, clock, home

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .airDrop: "AirDrop"
        case .darkMode: "Dark Mode"
        case .nightShift: "Night Shift"
        case .keepAwake: "Keep Awake"
        case .microphone: "Microphone"
        case .calculator: "Calculator"
        case .voiceMemos: "Voice Memos"
        case .screenshot: "Screenshot"
        case .notes: "Notes"
        case .lockScreen: "Lock Screen"
        case .focus: "Focus"
        case .clock: "Clock"
        case .home: "Home"
        }
    }

    /// The SF Symbol, as Control Center shows it. Bluetooth has none (its logo is drawn:
    /// `BluetoothLogo`), so it has the nearest one only for places that need a symbol name.
    func symbol(on: Bool) -> String {
        switch self {
        case .wifi: on ? "wifi" : "wifi.slash"
        case .bluetooth: "antenna.radiowaves.left.and.right"
        case .airDrop: "dot.radiowaves.up.forward"
        case .darkMode: "circle.lefthalf.filled"
        case .nightShift: on ? "sun.horizon.fill" : "sun.horizon"
        case .keepAwake: on ? "cup.and.heat.waves.fill" : "cup.and.saucer.fill"
        case .microphone: on ? "mic.fill" : "mic.slash.fill"
        case .calculator: "plus.forwardslash.minus"
        case .voiceMemos: "waveform"
        case .screenshot: "camera.viewfinder"
        case .notes: "note.text"
        case .lockScreen: "lock.fill"
        case .focus: "moon.fill"
        case .clock: "clock.fill"
        case .home: "house.fill"
        }
    }

    /// "On", "Off", or what it does.
    func status(on: Bool) -> String {
        switch self {
        case .airDrop, .calculator, .voiceMemos, .notes, .focus, .clock, .home: String(localized: "Open")
        case .screenshot: String(localized: "Capture")
        case .lockScreen: String(localized: "Lock")
        case .microphone: on ? String(localized: "On") : String(localized: "Muted")
        default: on ? String(localized: "On") : String(localized: "Off")
        }
    }

    /// Opens something rather than switching (no state to show).
    var isAction: Bool {
        switch self {
        case .wifi, .bluetooth, .darkMode, .nightShift, .keepAwake, .microphone: false
        case .airDrop, .calculator, .voiceMemos, .screenshot, .notes, .lockScreen, .focus, .clock, .home: true
        }
    }

    /// What an action opens: an app, or a System Settings pane.
    var actionURL: URL? {
        switch self {
        case .airDrop: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
        case .calculator: URL(fileURLWithPath: "/System/Applications/Calculator.app")
        case .voiceMemos: URL(fileURLWithPath: "/System/Applications/VoiceMemos.app")
        case .screenshot: URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        case .notes: URL(fileURLWithPath: "/System/Applications/Notes.app")
        case .clock: URL(fileURLWithPath: "/System/Applications/Clock.app")
        case .home: URL(fileURLWithPath: "/System/Applications/Home.app")
        case .focus: URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension")
        default: nil
        }
    }
}

/// Reads and switches the Control Center items the widgets offer.
///
/// Energy: nothing polls. States are read when a widget comes on screen (`refresh`) and right
/// after a switch; Dark Mode also follows the system's theme notification while observed. The
/// private switches (Bluetooth, Night Shift, keyboard backlight, Dark Mode) are looked up once
/// with `dlsym` / `NSClassFromString` and simply stay unavailable if an OS release drops them.
@Observable final class SystemControls {
    private(set) var states: [SystemControl: Bool] = [:]
    /// 0…1, nil without a keyboard backlight.
    private(set) var keyboardBrightness: Double?
    /// The last switch that failed, for a moment (the widget shakes it).
    private(set) var failed: SystemControl?

    /// How many widgets on screen show each control. Only these are read: reading Bluetooth asks
    /// for its permission the first time.
    @ObservationIgnored private var shown: [SystemControl: Int] = [:]
    @ObservationIgnored private var themeToken: (any NSObjectProtocol)?
    @ObservationIgnored private var awakeAssertion: IOPMAssertionID?

    func isOn(_ control: SystemControl) -> Bool { states[control] ?? false }

    /// A widget showing `control` appeared (balanced by `stopObserving`).
    func startObserving(_ control: SystemControl) {
        shown[control, default: 0] += 1
        refresh()
        if control == .darkMode, themeToken == nil {
            themeToken = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.states[.darkMode] = Self.readDarkMode() }
            }
        }
    }

    func stopObserving(_ control: SystemControl) {
        let count = (shown[control] ?? 0) - 1
        shown[control] = count > 0 ? count : nil
        if shown[.darkMode] == nil, let themeToken {
            DistributedNotificationCenter.default().removeObserver(themeToken)
            self.themeToken = nil
        }
    }

    func refresh() {
        var next = states
        for control in shown.keys {
            next[control] = switch control {
            case .wifi: CWWiFiClient.shared().interface()?.powerOn() ?? false
            case .bluetooth: Private.bluetoothPower() ?? false
            case .airDrop, .calculator, .voiceMemos, .screenshot, .notes, .lockScreen, .focus, .clock, .home: false
            case .darkMode: Self.readDarkMode()
            case .nightShift: Private.nightShiftActive() ?? false
            case .keepAwake: awakeAssertion != nil
            case .microphone: !(Microphone.isMuted() ?? false)
            }
        }
        if next != states { states = next }
        let keyboard = Private.keyboardBrightness()
        if keyboard != keyboardBrightness { keyboardBrightness = keyboard }
    }

    func toggle(_ control: SystemControl) {
        let target = !isOn(control)
        let succeeded: Bool
        switch control {
        case .wifi:
            succeeded = (try? CWWiFiClient.shared().interface()?.setPower(target)) != nil
        case .bluetooth:
            succeeded = Private.setBluetoothPower(target)
        case .lockScreen:
            if !Private.lockScreen() { Log.app.error("lock screen unavailable") }
            return
        case .airDrop, .calculator, .voiceMemos, .screenshot, .notes, .focus, .clock, .home:
            if let url = control.actionURL { NSWorkspace.shared.open(url) }
            return
        case .darkMode:
            succeeded = Private.setDarkMode(target)
        case .nightShift:
            succeeded = Private.setNightShift(target)
        case .keepAwake:
            succeeded = setKeepAwake(target)
        case .microphone:
            succeeded = Microphone.setMuted(!target)
        }
        if succeeded {
            states[control] = target
        } else {
            Log.app.error("control \(control.rawValue, privacy: .public) could not be switched")
            failed = control
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                if self?.failed == control { self?.failed = nil }
            }
        }
        // Read back what the system actually did (a switch may be refused or take a moment).
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.refresh()
        }
    }

    func setKeyboardBrightness(_ value: Double) {
        guard Private.setKeyboardBrightness(value) else { return }
        keyboardBrightness = value
    }

    /// Keeps the Mac (and its display) awake until switched off or the app quits.
    private func setKeepAwake(_ on: Bool) -> Bool {
        if on {
            guard awakeAssertion == nil else { return true }
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "NotchIsland Keep Awake" as CFString, &id)
            guard result == kIOReturnSuccess else { return false }
            awakeAssertion = id
        } else if let id = awakeAssertion {
            IOPMAssertionRelease(id)
            awakeAssertion = nil
        }
        return true
    }

    private static func readDarkMode() -> Bool {
        Private.darkMode() ?? (UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
    }

    isolated deinit {
        if let id = awakeAssertion { IOPMAssertionRelease(id) }
        if let themeToken { DistributedNotificationCenter.default().removeObserver(themeToken) }
    }
}

/// The default input device's mute (the Control Center microphone switch).
nonisolated enum Microphone {
    private static func defaultInput() -> AudioObjectID? {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func isMuted() -> Bool? {
        guard let device = defaultInput() else { return nil }
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultInput() else { return false }
        var address = muteAddress
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}

/// Private system switches, looked up at run time.
private enum Private {
    // MARK: Bluetooth (IOBluetooth)

    private static let bluetooth = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)
    private typealias GetPower = @convention(c) () -> Int32
    private typealias SetPower = @convention(c) (Int32) -> Void

    static func bluetoothPower() -> Bool? {
        // Reading the controller needs the Bluetooth permission (NSBluetoothAlwaysUsageDescription).
        guard let symbol = dlsym(bluetooth, "IOBluetoothPreferenceGetControllerPowerState") else { return nil }
        return unsafeBitCast(symbol, to: GetPower.self)() != 0
    }

    static func setBluetoothPower(_ on: Bool) -> Bool {
        guard let symbol = dlsym(bluetooth, "IOBluetoothPreferenceSetControllerPowerState") else { return false }
        unsafeBitCast(symbol, to: SetPower.self)(on ? 1 : 0)
        return true
    }

    // MARK: Lock Screen (login)

    private static let login = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY)
    private typealias LockNow = @convention(c) () -> Void

    /// Locks the screen at once, as Control Center's Lock Screen does.
    static func lockScreen() -> Bool {
        guard let symbol = dlsym(login, "SACLockScreenImmediate") else { return false }
        unsafeBitCast(symbol, to: LockNow.self)()
        return true
    }

    // MARK: Dark Mode (SkyLight)

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private typealias GetTheme = @convention(c) () -> Bool
    private typealias SetTheme = @convention(c) (Bool) -> Void

    static func darkMode() -> Bool? {
        guard let symbol = dlsym(skyLight, "SLSGetAppearanceThemeLegacy") else { return nil }
        return unsafeBitCast(symbol, to: GetTheme.self)()
    }

    static func setDarkMode(_ on: Bool) -> Bool {
        guard let symbol = dlsym(skyLight, "SLSSetAppearanceThemeLegacy") else { return false }
        unsafeBitCast(symbol, to: SetTheme.self)(on)
        return true
    }

    // MARK: Night Shift and keyboard backlight (CoreBrightness)

    private static let coreBrightness = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)

    private static let blueLight: NSObject? = {
        _ = coreBrightness
        return (NSClassFromString("CBBlueLightClient") as? NSObject.Type)?.init()
    }()

    private static let keyboard: NSObject? = {
        _ = coreBrightness
        return (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }()

    /// `getBlueLightStatus:` fills a struct whose first byte is "active".
    static func nightShiftActive() -> Bool? {
        guard let client = blueLight else { return nil }
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: selector) else { return nil }
        typealias Get = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let status = UnsafeMutableRawPointer.allocate(byteCount: 128, alignment: 8)
        defer { status.deallocate() }
        status.initializeMemory(as: UInt8.self, repeating: 0, count: 128)
        guard unsafeBitCast(client.method(for: selector), to: Get.self)(client, selector, status) else { return nil }
        return status.load(as: UInt8.self) != 0
    }

    static func setNightShift(_ on: Bool) -> Bool {
        guard let client = blueLight else { return false }
        let selector = NSSelectorFromString("setEnabled:")
        guard client.responds(to: selector) else { return false }
        typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Bool
        return unsafeBitCast(client.method(for: selector), to: Set.self)(client, selector, on)
    }

    private static var keyboardID: UInt64? {
        guard let client = keyboard else { return nil }
        let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber]
        return ids?.first?.uint64Value
    }

    static func keyboardBrightness() -> Double? {
        guard let client = keyboard, let id = keyboardID else { return nil }
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        typealias Get = @convention(c) (AnyObject, Selector, UInt64) -> Float
        return Double(unsafeBitCast(client.method(for: selector), to: Get.self)(client, selector, id))
    }

    static func setKeyboardBrightness(_ value: Double) -> Bool {
        guard let client = keyboard, let id = keyboardID else { return false }
        let selector = NSSelectorFromString("setBrightness:forKeyboard:")
        typealias Set = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        return unsafeBitCast(client.method(for: selector), to: Set.self)(client, selector, Float(min(max(value, 0), 1)), id)
    }
}
