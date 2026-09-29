import CoreAudio
import Foundation

/// Notices the AirPods' noise control changing (a long press on the stem, Control Center): macOS
/// then shows its own card — the connection card with the mode where "Connected" was — and the
/// island covers it the same way.
///
/// The headphones' audio device carries the mode as a property of its own (`lstm`: 1 off, 2 noise
/// cancellation, 3 transparency, 4 adaptive; `lsms` the modes it has, found by listing the
/// device's custom properties), and CoreAudio tells a listener when it changes: nothing runs
/// until then, and no Bluetooth permission is needed. (The Bluetooth framework's `listeningMode`
/// stayed 0 in the app and never changed, and AVRouting's devices are the system's only — both
/// tried.)
@MainActor final class AirPodsListeningModeWatch {
    /// The headphones' name and their new mode.
    var onChange: ((String, AirPodsListeningMode) -> Void)?

    private struct Watched {
        let device: AudioObjectID
        let listener: AudioObjectPropertyListenerBlock
        var mode: AirPodsListeningMode?
    }

    private var watched: [String: Watched] = [:]
    /// What happened (for diagnostics).
    private(set) var recent: [String] = []

    static let modeSelector: AudioObjectPropertySelector = fourCC("lstm")

    /// The Bluetooth outputs connected now (`AirPodsMonitor.onOutputsChanged`).
    func follow(_ outputs: Set<String>) {
        for name in watched.keys where !outputs.contains(name) {
            remove(name)
            note("stopped watching \(name)")
        }
        let new = outputs.subtracting(watched.keys)
        guard !new.isEmpty else { return }
        for (device, name) in Self.devicesWithNoiseControl() where new.contains(name) && watched[name] == nil {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.check(name) }
            }
            var address = Self.address
            guard AudioObjectAddPropertyListenerBlock(device, &address, .main, listener) == noErr else {
                note("\(name): could not listen to its mode")
                continue
            }
            let mode = Self.mode(of: device)
            watched[name] = Watched(device: device, listener: listener, mode: mode)
            note("watching \(name) (mode now: \(mode.map { String(describing: $0) } ?? "unknown"))")
        }
    }

    func stop() {
        for name in watched.keys { remove(name) }
    }

    var diagnosticsSummary: String {
        watched.isEmpty ? "not watching" : watched.map { "\($0.key): \($0.value.mode.map { String(describing: $0) } ?? "?")" }
            .sorted().joined(separator: ", ")
    }

    private func check(_ name: String) {
        guard var entry = watched[name], let mode = Self.mode(of: entry.device), mode != entry.mode else { return }
        let first = entry.mode == nil
        entry.mode = mode
        watched[name] = entry
        note("\(name): \(mode)")
        // A first reading is not a change the user made.
        if !first { onChange?(name, mode) }
    }

    private func remove(_ name: String) {
        guard let entry = watched.removeValue(forKey: name) else { return }
        // Gone with the headphones: removing it from a device that is no more logs a HAL error.
        guard HAL.isAlive(entry.device) else { return }
        var address = Self.address
        AudioObjectRemovePropertyListenerBlock(entry.device, &address, .main, entry.listener)
    }

    private func note(_ event: String) {
        recent.append("\(Date().formatted(date: .omitted, time: .standard)) \(event)")
        if recent.count > 30 { recent.removeFirst(recent.count - 30) }
        Log.system.notice("listening mode: \(event, privacy: .public)")
    }

    // MARK: CoreAudio

    private static let address = AudioObjectPropertyAddress(mSelector: modeSelector, mScope: kAudioObjectPropertyScopeGlobal,
                                                            mElement: kAudioObjectPropertyElementMain)

    nonisolated static func fourCC(_ code: String) -> UInt32 {
        code.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// The Bluetooth devices that have a noise-control mode, with their names (one pair of AirPods
    /// shows as more than one device: the first with the mode is taken).
    private static func devicesWithNoiseControl() -> [(AudioObjectID, String)] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        var seen = Set<String>()
        return devices.compactMap { device in
            var mode = Self.address
            guard AudioObjectHasProperty(device, &mode), let name = name(of: device), seen.insert(name).inserted else { return nil }
            return (device, name)
        }
    }

    private static func mode(of device: AudioObjectID) -> AirPodsListeningMode? {
        var address = Self.address
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return AirPodsListeningMode(rawValue: UInt8(truncatingIfNeeded: value))
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}
