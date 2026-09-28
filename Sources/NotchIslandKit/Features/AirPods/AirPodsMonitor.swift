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
    private var known: Set<String> = []
    /// What happened with the last connections (for diagnostics): what arrived, whether macOS's own
    /// card was seen, and what the island showed.
    private(set) var recent: [String] = []
    /// The Bluetooth audio outputs connected now.
    var connectedOutputs: Set<String> { known }

    private func note(_ event: String) {
        recent.append("\(Date().formatted(date: .omitted, time: .standard)) \(event)")
        if recent.count > 30 { recent.removeFirst(recent.count - 30) }
    }
    private var pending: Task<Void, Never>?

    func start() {
        guard listener == nil else { return }
        known = Self.bluetoothOutputs()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.devicesChanged() }
        }
        var address = Self.devicesAddress
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
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
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        listener = nil
    }

    private func devicesChanged() {
        let current = Self.bluetoothOutputs()
        let arrived = current.subtracting(known)
        known = current
        guard let name = arrived.first else { return }
        // What was already at the top of the screen: anything new there is macOS's own card.
        let before = TopEdgeOverlays.current()
        let mode = systemCard()
        note("connected: \(name) (outputs: \(current.sorted().joined(separator: ", ")); card mode: \(mode))")
        pending?.cancel()
        pending = Task { [weak self] in
            if mode == .cover {
                // At once, to come up over macOS's card as it appears; the batteries the profile
                // has a moment later follow into the same card.
                if let info = await Self.readInfo(named: name), info.hasBattery || info.model != .headphones {
                    guard !Task.isCancelled else { return }
                    self?.note("shown at once (cover): \(info)")
                    self?.onConnect?(info)
                } else {
                    self?.note("no headphone info yet for \(name)")
                }
                try? await Task.sleep(for: Self.settleDelay)
                guard !Task.isCancelled, let fresh = await Self.readInfo(named: name), !Task.isCancelled else { return }
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
            // New at the top since the connection, or drawn by the processes that draw macOS's
            // notices (it may have come up a moment before the audio device did).
            var systemCard = TopEdgeOverlays.current().subtracting(before)
                .union(TopEdgeOverlays.current(ownedBy: TopEdgeOverlays.noticeOwners))
            if !systemCard.isEmpty {
                self.note("macOS's card seen (\(systemCard.count) window(s)); \(mode == .after ? "waiting for it to go" : "staying away")")
                guard mode == .after else { return }
                for _ in 0..<32 where !systemCard.isEmpty {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    systemCard.formIntersection(TopEdgeOverlays.current())
                }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            self.note("shown: \(info)")
            self.onConnect?(info)
        }
    }

    // MARK: CoreAudio

    private static let devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// Names of the Bluetooth devices that can play audio right now.
    private static func bluetoothOutputs() -> Set<String> {
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

    private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func hasOutput(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of device: AudioObjectID) -> String? {
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
    @concurrent static func readInfo(named name: String) async -> AirPodsInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
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
    /// `screen`: the notch screen in window-list coordinates (top-left origin); nil takes the
    /// main display.
    /// The processes whose windows at the top are macOS's notices (the AirPods card was a
    /// MenuBarAgent window, 352 × 148 under the notch, on macOS 27 — seen in the window list).
    static let noticeOwners: Set<String> = ["MenuBarAgent", "ControlCenter", "BluetoothUIService", "BluetoothUIServer"]

    static func current(ownedBy owners: Set<String>? = nil, on screen: CGRect? = nil) -> Set<CGWindowID> {
        let own = ProcessInfo.processInfo.processIdentifier
        let screen = screen ?? CGDisplayBounds(CGMainDisplayID())
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return Set(windows.compactMap { window -> CGWindowID? in
            // The Dock puts small windows along the top for Mission Control and Spaces (seen in
            // the window list): not a notice.
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard (window[kCGWindowOwnerPID as String] as? Int32) != own,
                  owner != "Dock",
                  owners.map({ $0.contains(owner) }) ?? true,
                  (window[kCGWindowLayer as String] as? Int ?? 0) > 0,
                  let number = window[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = (window[kCGWindowBounds as String] as? NSDictionary)
                      .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                  screen.contains(bounds.origin),
                  isOverlay(bounds.offsetBy(dx: -screen.minX, dy: -screen.minY)) else { return nil }
            return number
        })
    }

    /// Near the top, small, and not the menu bar (which spans the screen).
    static func isOverlay(_ bounds: CGRect) -> Bool {
        bounds.minY < 100 && bounds.height >= 30 && bounds.height < 160 && bounds.width > 80 && bounds.width < 700
    }
}
