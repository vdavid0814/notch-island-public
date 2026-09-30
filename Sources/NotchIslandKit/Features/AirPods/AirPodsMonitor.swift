import CoreAudio
import CoreGraphics
import Foundation
import os

/// What the AirPods banner shows: the name, which picture, and each battery the system reports
/// (nil when it does not: one-piece headphones have only `single`).
nonisolated struct AirPodsInfo: Sendable, Equatable {
    var name: String
    var model: Model
    var left: Int?
    var right: Int?
    var chargingCase: Int?
    var single: Int?
    /// Set when the card is for a change of noise control (a long press on the stem), not a
    /// connection: the card shows the mode instead of the batteries.
    var listeningMode: AirPodsListeningMode? = nil

    nonisolated enum Model: Sendable, Equatable {
        case airPods, airPodsPro, airPods3, airPods4, airPodsMax, beats, headphones

        /// From the name the user sees (it carries the model unless renamed) and Apple's product id.
        init(name: String, productID: String?) {
            let lower = name.lowercased()
            // Beats first: "Powerbeats Pro" is not an AirPods Pro.
            if lower.contains("beats") { self = .beats }
            else if lower.contains("max") { self = .airPodsMax }
            else if lower.contains("pro") { self = .airPodsPro }
            else if lower.contains("airpods") {
                switch productID?.lowercased() {
                case "0x2013": self = .airPods3
                case "0x2019", "0x201b": self = .airPods4
                default: self = .airPods
                }
            } else { self = .headphones }
        }
    }

    /// The whole set, for the banner's leading ear.
    var symbol: String {
        switch model {
        case .airPods: "airpods"
        case .airPodsPro: "airpods.pro"
        case .airPods3: "airpods.gen3"
        case .airPods4: "airpods.gen4"
        case .airPodsMax: "airpodsmax"
        case .beats: "beats.headphones"
        case .headphones: "headphones"
        }
    }

    var leftSymbol: String { model == .airPodsPro ? "airpodpro.left" : "airpod.left" }
    var rightSymbol: String { model == .airPodsPro ? "airpodpro.right" : "airpod.right" }

    var caseSymbol: String {
        switch model {
        case .airPodsPro: "airpods.pro.chargingcase.wireless.fill"
        case .airPods3: "airpods.gen3.chargingcase.wireless.fill"
        default: "airpods.chargingcase.fill"
        }
    }

    /// Anything to show beside the name.
    var hasBattery: Bool { left != nil || right != nil || chargingCase != nil || single != nil }

    static let demo = AirPodsInfo(name: "AirPods Pro", model: .airPodsPro, left: 80, right: 82, chargingCase: 86)
}

/// The AirPods' noise control, as the Bluetooth framework reports it (`listeningMode`).
nonisolated enum AirPodsListeningMode: UInt8, Sendable, Equatable, CaseIterable {
    case off = 1
    case noiseCancellation = 2
    case transparency = 3
    case adaptive = 4

    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .noiseCancellation: String(localized: "Noise Cancellation")
        case .transparency: String(localized: "Transparency")
        case .adaptive: String(localized: "Adaptive")
        }
    }

    /// Control Center's symbols for the modes.
    var symbol: String {
        switch self {
        case .off: "person.fill"
        case .noiseCancellation: "person.and.background.striped.horizontal"
        case .transparency: "person.and.background.dotted"
        case .adaptive: "person.and.background.dotted"
        }
    }
}

/// Notices headphones connecting — a new Bluetooth output in CoreAudio's device list (no
/// permission needed) — and reads their name and batteries from `system_profiler`, which reports
/// AirPods' left, right and case levels (also without a Bluetooth permission prompt, since the
/// query runs in its own process).
///
/// Outputs already there when it starts are the baseline: only a connection made later is
/// announced.
@MainActor final class AirPodsMonitor {
    /// A set of headphones connected (after its batteries were read, and after macOS's own card
    /// for them has gone, see `TopEdgeOverlays`).
    var onConnect: ((AirPodsInfo) -> Void)?
    /// Fresher batteries for the card already up (cover mode).
    var onUpdate: ((AirPodsInfo) -> Void)?
    /// What to do about macOS's own AirPods card (`AirPodsSystemCard`).
    var systemCard: () -> AirPodsSystemCard = { .cover }

    /// The profile reports freshly connected AirPods' batteries after a moment; asked at once it
    /// can still hold the levels from their last connection.
    static let settleDelay: Duration = .milliseconds(1200)

    private var listener: AudioObjectPropertyListenerBlock?
    /// Where the device list is listened to: the spectrum tap's private aggregate device comes and
    /// goes with the music and changes the list each time, so the Bluetooth outputs are worked out
    /// here and the main thread hears only of a change to them (as quickly as before: a connection
    /// is covered at once).
    private let queue = DispatchQueue(label: "com.davidvarga.notchisland.airpods", qos: .userInitiated)
    private var known: Set<String> = []
    /// What happened with the last connections (for diagnostics): what arrived, whether macOS's own
    /// card was seen, and what the island showed.
    private(set) var recent: [String] = []
    /// The Bluetooth audio outputs connected now.
    var connectedOutputs: Set<String> { known }
    /// The Bluetooth outputs changed (the listening-mode watch follows the headphones connected).
    var onOutputsChanged: ((Set<String>) -> Void)?
    /// The last batteries read for each set of headphones: a change of noise control shows them at
    /// once, as macOS's card does, while fresher ones are read.
    private(set) var lastInfo: [String: AirPodsInfo] = [:]

    /// Every reading as it is remembered (the AirPods widget keeps the last).
    var onRemember: ((AirPodsInfo) -> Void)?

    func remember(_ info: AirPodsInfo) {
        var info = info
        info.listeningMode = nil
        lastInfo[info.name] = info
        onRemember?(info)
    }

    private func note(_ event: String) {
        recent.append("\(Date().formatted(date: .omitted, time: .standard)) \(event)")
        if recent.count > 30 { recent.removeFirst(recent.count - 30) }
    }
    private var pending: Task<Void, Never>?

    func start() {
        guard listener == nil else { return }
        known = Self.bluetoothOutputs()
        onOutputsChanged?(known)
        let block = Self.listener(from: known, to: self)
        var address = Self.devicesAddress
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        if status == noErr {
            listener = block
        } else {
            Log.system.error("audio device listener failed (\(status)) — AirPods connections unobserved")
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        if let listener {
            var address = Self.devicesAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
        }
        listener = nil
    }

    /// Runs on `queue`, where the HAL calls it: the main actor is told only when the Bluetooth
    /// outputs differ from the last ones seen.
    nonisolated private static func listener(from initial: Set<String>, to monitor: AirPodsMonitor) -> AudioObjectPropertyListenerBlock {
        let last = OSAllocatedUnfairLock(initialState: initial)
        return { [weak monitor] _, _ in
            let current = bluetoothOutputs()
            guard last.withLock({ seen in
                defer { seen = current }
                return seen != current
            }) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { monitor?.outputsChanged(to: current) }
            }
        }
    }

    private func outputsChanged(to current: Set<String>) {
        // Stopped since the list was read.
        guard listener != nil else { return }
        let arrived = current.subtracting(known)
        known = current
        onOutputsChanged?(current)
        guard let name = arrived.first else { return }
        let mode = systemCard()
        // What was already at the top of the screen: anything new there is macOS's own card (only
        // looked for when the island does not cover it).
        let before: Set<CGWindowID> = mode == .cover ? [] : Set(TopEdgeOverlays.current().keys)
        note("connected: \(name) (outputs: \(current.sorted().joined(separator: ", ")); card mode: \(mode))")
        pending?.cancel()
        pending = Task { [weak self] in
            if mode == .cover {
                // At once, to come up over macOS's card as it appears; the batteries the profile
                // has a moment later follow into the same card.
                if let info = await Self.readInfo(named: name), info.hasBattery || info.model != .headphones {
                    guard !Task.isCancelled else { return }
                    self?.note("shown at once (cover): \(info)")
                    self?.remember(info)
                    self?.onConnect?(info)
                } else {
                    self?.note("no headphone info yet for \(name)")
                }
                try? await Task.sleep(for: Self.settleDelay)
                guard !Task.isCancelled, let fresh = await Self.readInfo(named: name), !Task.isCancelled else { return }
                self?.remember(fresh)
                self?.onUpdate?(fresh)
                return
            }
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            let info = await Self.readInfo(named: name)
            guard !Task.isCancelled, let self else { return }
            // Only headphones the profile knows as such (a Bluetooth speaker also has a name).
            guard let info, info.hasBattery || info.model != .headphones else {
                self.note("not shown: \(name) is not headphones the profile knows")
                return
            }
            // Never both at once: while macOS's own AirPods card is up, ours waits for it to go
            // (or, if the user chose so, stays away).
            var systemCard = await TopEdgeOverlays.systemCard(since: before)
            if !systemCard.isEmpty {
                self.note("macOS's card seen (\(systemCard.count) window(s)); \(mode == .after ? "waiting for it to go" : "staying away")")
                guard mode == .after else { return }
                for _ in 0..<32 where !systemCard.isEmpty {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    systemCard = await TopEdgeOverlays.stillUp(systemCard)
                }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            self.note("shown: \(info)")
            self.remember(info)
            self.onConnect?(info)
        }
    }

    // MARK: CoreAudio

    nonisolated private static let devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// Names of the Bluetooth devices that can play audio right now.
    nonisolated private static func bluetoothOutputs() -> Set<String> {
        var address = devicesAddress
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return Set(devices.compactMap { device -> String? in
            guard isBluetooth(device), hasOutput(device) else { return nil }
            return name(of: device)
        })
    }

    nonisolated private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    nonisolated private static func hasOutput(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    nonisolated private static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() as String? else { return nil }
        return value
    }

    // MARK: system_profiler

    /// The device's entry in the Bluetooth profile, off the main thread.
    ///
    /// `-nospawn` has the report made in this one process: by default `system_profiler` starts a
    /// second copy of itself with it (seen in the process list) to make each report in, which cost
    /// another launch and ~20 % more CPU for the same JSON (compared byte for byte, macOS 27).
    @concurrent static func readInfo(named name: String) async -> AirPodsInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-nospawn", "SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(data, name: name)
    }

    /// Finds `name` among the connected (then the remembered) devices of a profile.
    nonisolated static func parse(_ data: Data, name: String) -> AirPodsInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controller = (root["SPBluetoothDataType"] as? [[String: Any]])?.first else { return nil }
        for key in ["device_connected", "device_not_connected"] {
            for entry in controller[key] as? [[String: Any]] ?? [] {
                for (deviceName, value) in entry where deviceName == name {
                    let fields = value as? [String: Any] ?? [:]
                    func level(_ field: String) -> Int? {
                        (fields[field] as? String).flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
                    }
                    return AirPodsInfo(
                        name: deviceName,
                        model: .init(name: deviceName, productID: fields["device_productID"] as? String),
                        left: level("device_batteryLevelLeft"),
                        right: level("device_batteryLevelRight"),
                        chargingCase: level("device_batteryLevelCase"),
                        single: level("device_batteryLevelMain") ?? level("device_batteryLevel")
                    )
                }
            }
        }
        return nil
    }
}

/// Small windows of other apps at the top of the screen — what macOS's own notices (the AirPods
/// card, a HUD) are made of. Window numbers and bounds only: no names, so no Screen Recording
/// permission is needed.
nonisolated enum TopEdgeOverlays {
    /// The processes whose windows at the top are macOS's notices (the AirPods card was a
    /// MenuBarAgent window, 352 × 148 under the notch, on macOS 27 — seen in the window list).
    static let noticeOwners: Set<String> = ["MenuBarAgent", "ControlCenter", "BluetoothUIService", "BluetoothUIServer"]

    /// Those on the main display now, with the process that drew each.
    static func current() -> [CGWindowID: String] {
        let own = ProcessInfo.processInfo.processIdentifier
        let screen = CGDisplayBounds(CGMainDisplayID())
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var overlays: [CGWindowID: String] = [:]
        for window in windows {
            // The Dock puts small windows along the top for Mission Control and Spaces (seen in
            // the window list): not a notice.
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard (window[kCGWindowOwnerPID as String] as? Int32) != own,
                  owner != "Dock",
                  (window[kCGWindowLayer as String] as? Int ?? 0) > 0,
                  let number = window[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
                      .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                  screen.contains(bounds.origin),
                  isOverlay(bounds.offsetBy(dx: -screen.minX, dy: -screen.minY)) else { continue }
            overlays[number] = owner
        }
        return overlays
    }

    /// macOS's card, if it is up: windows new at the top since `before`, or drawn by the processes
    /// that draw macOS's notices (it may have come up a moment before the audio device did). One
    /// window-list read, off the main thread.
    @concurrent static func systemCard(since before: Set<CGWindowID>) async -> Set<CGWindowID> {
        Set(current().filter { !before.contains($0.key) || noticeOwners.contains($0.value) }.keys)
    }

    /// Those of `windows` still up, read off the main thread.
    @concurrent static func stillUp(_ windows: Set<CGWindowID>) async -> Set<CGWindowID> {
        windows.intersection(current().keys)
    }

    /// Near the top, small, and not the menu bar (which spans the screen).
    static func isOverlay(_ bounds: CGRect) -> Bool {
        bounds.minY < 100 && bounds.height >= 30 && bounds.height < 160 && bounds.width > 80 && bounds.width < 700
    }
}
