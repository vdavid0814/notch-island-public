import AppKit
import CoreAudio
import Foundation
import IOKit

/// The Control Center items added in 0.6 (`SystemControl.soundOutput` … `.displaySleep`): their
/// names, symbols, and what reading and switching them does. `SystemControl` and `SystemControls`
/// hand every question about them to this file.
///
/// Nothing here polls: a state is read when its widget comes on screen and right after a switch
/// (`SystemControls.refresh`). What rests on a private class or a system app is looked up at run
/// time, and its widget is not offered where that is missing (`isAvailable`).
nonisolated enum ExtendedControls {
    static func title(of control: SystemControl) -> String {
        switch control {
        case .soundOutput: "Sound Output"
        case .outputMute: "Mute"
        case .trueTone: "True Tone"
        case .stageManager: "Stage Manager"
        case .lowPowerMode: "Low Power Mode"
        case .screenMirroring: "Screen Mirroring"
        case .missionControl: "Mission Control"
        case .showDesktop: "Show Desktop"
        case .appsLauncher: "Apps"
        case .characterViewer: "Emoji & Symbols"
        case .displaySleep: "Display Sleep"
        default: control.rawValue
        }
    }

    static func symbol(of control: SystemControl, on: Bool) -> String {
        switch control {
        case .soundOutput: "hifispeaker.fill"
        case .outputMute: on ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .trueTone: "sun.max.fill"
        case .stageManager: "rectangle.stack.fill"
        case .lowPowerMode: "battery.25percent"
        case .screenMirroring: "rectangle.on.rectangle"
        case .missionControl: "rectangle.3.group.fill"
        case .showDesktop: "menubar.dock.rectangle"
        case .appsLauncher: "square.grid.3x3.fill"
        case .characterViewer: "face.smiling"
        case .displaySleep: "display"
        default: "questionmark"
        }
    }

    /// Opens or does one thing, with no state to show.
    static func isAction(_ control: SystemControl) -> Bool {
        switch control {
        case .outputMute, .trueTone, .stageManager, .lowPowerMode: false
        default: true
        }
    }

    /// What its widget says under its name: its state, or what a click does.
    static func status(of control: SystemControl, on: Bool) -> String? {
        switch control {
        case .soundOutput: SoundOutput.current()?.name ?? String(localized: "Choose")
        case .outputMute: on ? String(localized: "Muted") : String(localized: "On")
        case .screenMirroring, .missionControl, .appsLauncher, .characterViewer: String(localized: "Open")
        case .showDesktop: String(localized: "Show")
        case .displaySleep: String(localized: "Sleep")
        default: nil
        }
    }

    /// Whether it works on this Mac.
    static func isAvailable(_ control: SystemControl) -> Bool {
        switch control {
        case .trueTone: TrueTone.isSupported
        case .appsLauncher: appsURL != nil
        case .missionControl, .showDesktop: FileManager.default.fileExists(atPath: missionControlURL.path)
        case .lowPowerMode: BatteryAvailability.hasBattery
        default: true
        }
    }

    static func actionURL(of control: SystemControl) -> URL? {
        switch control {
        case .screenMirroring: URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")
        case .lowPowerMode: URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")
        case .appsLauncher: appsURL
        case .missionControl: missionControlURL
        default: nil
        }
    }

    static func isOn(_ control: SystemControl) -> Bool {
        switch control {
        case .outputMute: SoundOutput.isMuted() ?? false
        case .trueTone: TrueTone.isEnabled ?? false
        case .stageManager: StageManager.isEnabled
        case .lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        default: false
        }
    }

    /// Whether the switch was made (an action: whether it ran).
    @MainActor static func toggle(_ control: SystemControl, to on: Bool) -> Bool {
        switch control {
        case .outputMute:
            return SoundOutput.setMuted(on)
        case .trueTone:
            return TrueTone.setEnabled(on)
        case .stageManager:
            StageManager.set(on)
            return true
        case .soundOutput:
            SoundOutput.showMenu()
            return true
        case .lowPowerMode, .screenMirroring, .appsLauncher, .missionControl:
            // Low Power Mode has no public switch: its settings, a click away.
            guard let url = actionURL(of: control) else { return false }
            return NSWorkspace.shared.open(url)
        case .showDesktop:
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["1"]
            NSWorkspace.shared.openApplication(at: missionControlURL, configuration: configuration)
            return true
        case .characterViewer:
            NSApp.orderFrontCharacterPalette(nil)
            return true
        case .displaySleep:
            return DisplaySleep.now()
        default:
            return false
        }
    }

    private static let missionControlURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app")

    /// macOS 26's Apps, or Launchpad before it.
    private static let appsURL: URL? = ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"]
        .first { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
}

/// The sound's output: the devices, the one in use, and its mute.
nonisolated enum SoundOutput {
    nonisolated struct Device: Sendable, Equatable {
        var id: AudioObjectID
        var name: String
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultDevice() -> AudioObjectID? {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    /// Every device the sound can play on (one with output channels), in the system's order.
    static func devices() -> [Device] {
        var address = address(kAudioHardwarePropertyDevices)
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = self.address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            var streamSize = UInt32(0)
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0,
                  let name = name(of: id) else { return nil }
            return Device(id: id, name: name)
        }
    }

    static func current() -> Device? {
        defaultDevice().flatMap { id in name(of: id).map { Device(id: id, name: $0) } }
    }

    @discardableResult
    static func select(_ device: AudioObjectID) -> Bool {
        var device = device
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &device) == noErr
    }

    static func isMuted() -> Bool? {
        guard let device = defaultDevice() else { return nil }
        var address = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultDevice() else { return false }
        var address = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    /// The devices as a menu at the pointer; the one in use is ticked, a click switches to another.
    @MainActor static func showMenu() {
        let menu = NSMenu()
        let current = defaultDevice()
        let target = MenuTarget.shared
        for device in devices() {
            let item = NSMenuItem(title: device.name, action: #selector(MenuTarget.choose(_:)), keyEquivalent: "")
            item.target = target
            item.tag = Int(device.id)
            item.state = device.id == current ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: String(localized: "Sound Settings…"), action: #selector(MenuTarget.openSettings), keyEquivalent: "")
        settings.target = target
        menu.addItem(settings)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @MainActor private final class MenuTarget: NSObject {
        static let shared = MenuTarget()

        @objc func choose(_ item: NSMenuItem) {
            SoundOutput.select(AudioObjectID(item.tag))
        }

        @objc func openSettings() {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(url) }
        }
    }
}

/// True Tone, through CoreBrightness's own client (private): absent, the widget is not offered.
nonisolated enum TrueTone {
    private nonisolated(unsafe) static let client: NSObject? = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        return (NSClassFromString("CBTrueToneClient") as? NSObject.Type)?.init()
    }()

    private typealias Get = @convention(c) (AnyObject, Selector) -> Bool
    private typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Bool

    private static func read(_ name: String) -> Bool? {
        guard let client else { return nil }
        let selector = NSSelectorFromString(name)
        guard client.responds(to: selector) else { return nil }
        return unsafeBitCast(client.method(for: selector), to: Get.self)(client, selector)
    }

    /// The display has True Tone, and the client can read and switch it.
    static var isSupported: Bool {
        guard let client, client.responds(to: NSSelectorFromString("setEnabled:")) else { return false }
        return read("supported") == true && read("available") != false
    }

    static var isEnabled: Bool? { read("enabled") }

    static func setEnabled(_ on: Bool) -> Bool {
        guard let client else { return false }
        let selector = NSSelectorFromString("setEnabled:")
        guard client.responds(to: selector) else { return false }
        return unsafeBitCast(client.method(for: selector), to: Set.self)(client, selector, on)
    }
}

/// Stage Manager: its switch is WindowManager's `GloballyEnabled`, which it follows as it is
/// written. Where a release stops following it, the switch opens Desktop & Dock settings instead.
nonisolated enum StageManager {
    private static var domain: CFString { "com.apple.WindowManager" as CFString }
    private static var key: CFString { "GloballyEnabled" as CFString }

    static var isEnabled: Bool {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? Bool ?? false
    }

    @MainActor static func set(_ on: Bool) {
        CFPreferencesSetAppValue(key, on as CFBoolean, domain)
        CFPreferencesAppSynchronize(domain)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard isEnabled != on, let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return }
            NSWorkspace.shared.open(url)
        }
    }
}

/// The display put to sleep at once (the Mac stays awake).
nonisolated enum DisplaySleep {
    static func now() -> Bool {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IODisplayWrangler")
        guard entry != 0 else { return false }
        defer { IOObjectRelease(entry) }
        return IORegistryEntrySetCFProperty(entry, "IORequestIdle" as CFString, kCFBooleanTrue) == KERN_SUCCESS
    }
}

/// Whether this Mac has a battery, read once; and whether the system shows its temperature to apps
/// (older Macs may not: no Temperature widget there).
nonisolated enum BatteryAvailability {
    static let hasBattery = PowerMonitor.readIOKit().hasBattery
    static let hasTemperature = hasBattery
        && BatteryProbe.properties().flatMap { BatteryProbe.temperature(properties: $0, pack: BatteryProbe.packData()) } != nil
}
