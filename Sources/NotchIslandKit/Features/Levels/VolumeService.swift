import AudioToolbox
import CoreAudio
import os

/// Output volume state of the default output device, as read from the HAL.
nonisolated struct VolumeSnapshot: Sendable, Equatable {
    var value: Double
    var isMuted: Bool
    /// Virtual main volume (or channel 1/2 scalars) settable: gates swallowing the volume keys.
    var canSetVolume: Bool
    /// `kAudioDevicePropertyMute` settable: gates swallowing the mute key.
    var canSetMute: Bool

    static let noDevice = VolumeSnapshot(value: 0, isMuted: false, canSetVolume: false, canSetMute: false)

    var reading: LevelReading {
        LevelReading(value: value, isMuted: isMuted, isAvailable: canSetVolume, kind: .volume)
    }

    /// A change a person would notice: more than 0.1 % or a mute flip.
    func differsAudibly(from other: VolumeSnapshot) -> Bool {
        abs(value - other.value) > 0.001 || isMuted != other.isMuted
    }

    func hasSameCapabilities(as other: VolumeSnapshot) -> Bool {
        canSetVolume == other.canSetVolume && canSetMute == other.canSetMute
    }
}

/// Owns the CoreAudio HAL for output volume. Output volume needs no permission (TCC covers input only).
///
/// Every HAL call happens on one private serial queue, which is also this actor's executor: property
/// listener blocks are registered on that queue, so they run isolated to the actor, and reads, writes
/// and notification handling are strictly ordered. That ordering is what lets `lastPublished` swallow
/// the echo of our own writes at the source.
actor VolumeService {
    typealias UpdateHandler = @Sendable (VolumeSnapshot, LevelUpdateReason) -> Void

    private let queue = DispatchSerialQueue(label: "com.davidvarga.notchisland.coreaudio", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// Holding a volume key (or dragging Control Center's slider) produces a burst of HAL
    /// notifications, several per change (main volume + each channel). One read per frame is plenty.
    private static let coalescingWindow: Duration = .milliseconds(16)

    private var onUpdate: UpdateHandler?
    private var device = AudioObjectID(kAudioObjectUnknown)
    /// Listener blocks can only be removed with the identical block object, so they are kept with
    /// the address they were added for.
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListeners: [(address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []
    private var lastPublished = VolumeSnapshot.noDevice
    private var pendingRead: Task<Void, Never>?

    /// Binds to the current default output, starts listening, and returns the current state.
    /// Idempotent.
    func start(onUpdate: @escaping UpdateHandler) -> VolumeSnapshot {
        self.onUpdate = onUpdate
        if systemListener == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                // The HAL invokes this on `queue`, our executor; `assumeIsolated` verifies that.
                self?.assumeIsolated { $0.defaultDeviceChanged() }
            }
            var address = HAL.defaultOutputDeviceAddress
            let status = AudioObjectAddPropertyListenerBlock(HAL.systemObject, &address, queue, block)
            if status == noErr {
                systemListener = block
            } else {
                Log.levels.error("default output listener failed (\(status)) — device switches unobserved")
            }
        }
        bind(to: HAL.defaultOutputDevice())
        lastPublished = read()
        return lastPublished
    }

    /// Removes every listener. Idempotent.
    func stop() {
        onUpdate = nil
        pendingRead?.cancel()
        pendingRead = nil
        unbind()
        if let block = systemListener {
            var address = HAL.defaultOutputDeviceAddress
            AudioObjectRemovePropertyListenerBlock(HAL.systemObject, &address, queue, block)
            systemListener = nil
        }
        lastPublished = .noDevice
    }

    /// Island slider. Raising the level of a muted output unmutes it, like Control Center's slider.
    func setVolume(_ value: Double) -> VolumeSnapshot {
        let current = read()
        let target = LevelStepper.clamped(value)
        if current.canSetVolume { writeVolume(target) }
        if target > 0, current.isMuted, current.canSetMute { writeMute(false) }
        return commit()
    }

    /// Media key. Stepping up while muted unmutes first, the way the hardware key does.
    func step(up: Bool, fine: Bool) -> VolumeSnapshot {
        let current = read()
        if up, current.isMuted, current.canSetMute { writeMute(false) }
        if current.canSetVolume { writeVolume(LevelStepper.stepped(current.value, up: up, fine: fine)) }
        return commit()
    }

    func toggleMute() -> VolumeSnapshot {
        let current = read()
        if current.canSetMute { writeMute(!current.isMuted) }
        return commit()
    }

    // MARK: - Private

    /// The state after a write is what the caller gets back; remembering it makes the HAL's
    /// notifications about that same write compare equal and publish nothing.
    private func commit() -> VolumeSnapshot {
        lastPublished = read()
        return lastPublished
    }

    private func defaultDeviceChanged() {
        let newDevice = HAL.defaultOutputDevice()
        guard newDevice != device else { return }
        bind(to: newDevice)
        pendingRead?.cancel()
        pendingRead = nil
        // The new device's state is the current state, not a change: adopt it silently. Its
        // capabilities (and so which keys may be swallowed) may differ — AirPods vs. HDMI.
        lastPublished = read()
        onUpdate?(lastPublished, .silent)
    }

    private func levelChanged() {
        guard pendingRead == nil else { return }
        pendingRead = Task {
            try? await Task.sleep(for: Self.coalescingWindow)
            guard !Task.isCancelled else { return }
            pendingRead = nil
            publishIfChanged()
        }
    }

    private func publishIfChanged() {
        guard let onUpdate else { return }
        let snapshot = read()
        guard snapshot != lastPublished else { return }
        lastPublished = snapshot
        onUpdate(snapshot, .external)
    }

    private func bind(to newDevice: AudioObjectID) {
        unbind()
        device = newDevice
        guard newDevice != kAudioObjectUnknown else { return }
        // Channel scalars only matter (and only cost wakeups) when there is no virtual main volume.
        let volumeAddresses = HAL.has(newDevice, HAL.virtualMainVolumeAddress)
            ? [HAL.virtualMainVolumeAddress]
            : HAL.channelVolumeAddresses
        for var address in volumeAddresses + [HAL.muteAddress] where HAL.has(newDevice, address) {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                // Runs on `queue`, our executor (see the type comment).
                self?.assumeIsolated { $0.levelChanged() }
            }
            let status = AudioObjectAddPropertyListenerBlock(newDevice, &address, queue, block)
            if status == noErr {
                deviceListeners.append((address, block))
            } else {
                Log.levels.error("volume listener failed (\(status)) on device \(newDevice)")
            }
        }
    }

    private func unbind() {
        for var listener in deviceListeners {
            AudioObjectRemovePropertyListenerBlock(device, &listener.address, queue, listener.block)
        }
        deviceListeners.removeAll()
        device = AudioObjectID(kAudioObjectUnknown)
    }

    private func read() -> VolumeSnapshot {
        guard device != kAudioObjectUnknown else { return .noDevice }
        var snapshot = VolumeSnapshot.noDevice
        if HAL.has(device, HAL.virtualMainVolumeAddress) {
            snapshot.value = Double(HAL.float32(device, HAL.virtualMainVolumeAddress) ?? 0)
            snapshot.canSetVolume = HAL.isSettable(device, HAL.virtualMainVolumeAddress)
        } else {
            // Many HDMI/aggregate devices have no virtual main volume: average the channels that answer.
            let channels = HAL.channelVolumeAddresses.filter { HAL.has(device, $0) }
            let values = channels.compactMap { HAL.float32(device, $0) }
            snapshot.value = values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
            snapshot.canSetVolume = channels.contains { HAL.isSettable(device, $0) }
        }
        snapshot.value = LevelStepper.clamped(snapshot.value)
        if HAL.has(device, HAL.muteAddress) {
            snapshot.isMuted = (HAL.uint32(device, HAL.muteAddress) ?? 0) != 0
            snapshot.canSetMute = HAL.isSettable(device, HAL.muteAddress)
        }
        return snapshot
    }

    private func writeVolume(_ value: Double) {
        let level = Float32(value)
        if HAL.isSettable(device, HAL.virtualMainVolumeAddress) {
            HAL.setFloat32(device, HAL.virtualMainVolumeAddress, level)
        } else {
            for address in HAL.channelVolumeAddresses where HAL.isSettable(device, address) {
                HAL.setFloat32(device, address, level)
            }
        }
    }

    private func writeMute(_ muted: Bool) {
        HAL.setUInt32(device, HAL.muteAddress, muted ? 1 : 0)
    }
}

/// Thin, typed wrappers over the AudioObject C API. Only ever called from `VolumeService`'s queue.
nonisolated private enum HAL {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static let defaultOutputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// The volume the system's own slider and keys drive (AudioToolbox's virtual main volume).
    static let virtualMainVolumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    /// Fallback for devices without a virtual main volume: the left/right channel scalars.
    static let channelVolumeAddresses: [AudioObjectPropertyAddress] = [1, 2].map {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: $0)
    }

    static func defaultOutputDevice() -> AudioObjectID {
        var address = defaultOutputDeviceAddress
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &device)
        return status == noErr ? device : AudioObjectID(kAudioObjectUnknown)
    }

    static func has(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        // No device (between two, as headphones come and go): asking logs a HAL error.
        guard object != kAudioObjectUnknown else { return false }
        var address = address
        return AudioObjectHasProperty(object, &address)
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        guard has(object, address) else { return false }
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    static func float32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Float32? {
        get(object, address, as: Float32(0))
    }

    static func uint32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        get(object, address, as: UInt32(0))
    }

    static func setFloat32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: Float32) {
        set(object, address, value)
    }

    static func setUInt32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: UInt32) {
        set(object, address, value)
    }

    private static func get<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, as initial: T) -> T? {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func set<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) {
        var address = address
        var value = value
        let status = AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
        if status != noErr {
            Log.levels.error("HAL write '\(address.mSelector)' failed (\(status)) on device \(object)")
        }
    }
}
