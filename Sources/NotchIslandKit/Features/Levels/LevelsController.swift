import AppKit
import Observation

/// Volume and brightness for the island: current readings, changes from the island's controls,
/// media keys taken over from the system OSD, and changes made anywhere else.
///
/// Writes for each level go through a per-level queue: strictly in order, one in flight at a time,
/// and a new slider value replaces a queued one (latest wins). While a level has writes outstanding,
/// service notifications only update its capabilities: the write's own result is authoritative, and a
/// notification read before it landed would otherwise yank the slider back under the pointer.
@Observable final class LevelsController {
    private(set) var volume = LevelReading.unavailable(.volume)
    private(set) var brightness = LevelReading.unavailable(.brightness)
    private(set) var interception: InterceptionState = .off
    /// `.key` for intercepted key presses (even when the level is at a limit and did not move),
    /// `.island` for `set(_:to:)` / `toggleMute()`, `.external` for changes made elsewhere.
    @ObservationIgnored var onChange: ((LevelKind, LevelChangeSource) -> Void)?

    @ObservationIgnored private let volumeService = VolumeService()
    @ObservationIgnored private let brightnessService = BrightnessService()
    @ObservationIgnored private let interceptor = MediaKeyInterceptor()
    /// Last state reported by the HAL; its capabilities drive the key policy.
    @ObservationIgnored private var volumeState = VolumeSnapshot.noDevice
    @ObservationIgnored private var writeQueues: [LevelKind: WriteQueue] = [:]
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var wantsInterception = false
    /// Bumped by `stop()`: results and notifications from an earlier run are dropped.
    @ObservationIgnored private var generation = 0
    /// The first reading of each level after `start()` is the state, not a change.
    @ObservationIgnored private var volumeGate = FirstReadingGate()
    @ObservationIgnored private var brightnessGate = FirstReadingGate()
    /// The last `VolumeService` start/stop. Each one waits for the previous: two unstructured tasks
    /// are not ordered, and a stop landing after the next start would leave the HAL unobserved.
    @ObservationIgnored private var volumeLifecycle: Task<Void, Never>?
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?

    init() {
        brightnessService.onUpdate = { [weak self] reading, reason in
            self?.brightnessServiceUpdated(reading, reason: reason)
        }
        interceptor.onKey = { [weak self] event in self?.handleKey(event) }
        interceptor.onStateChange = { [weak self] state in self?.interception = state }
    }

    func reading(_ kind: LevelKind) -> LevelReading {
        switch kind {
        case .volume: volume
        case .brightness: brightness
        }
    }

    /// From the island's Slider. The reading follows immediately so the Slider tracks the pointer.
    func set(_ kind: LevelKind, to value: Double) {
        guard isRunning, reading(kind).isAvailable else { return }
        let target = LevelStepper.clamped(value)
        switch kind {
        case .volume:
            let unmutes = target > 0 && volume.isMuted && volumeState.canSetMute
            guard target != volume.value || unmutes else { return }
            volume.value = target
            if unmutes { volume.isMuted = false }
        case .brightness:
            guard target != brightness.value else { return }
            brightness.value = target
        }
        enqueue(.set(target), on: kind, source: .island)
    }

    func toggleMute() {
        guard isRunning, volumeState.canSetMute else { return }
        volume.isMuted.toggle()
        enqueue(.toggleMute, on: .volume, source: .island)
    }

    /// Idempotent. Services only start observing here, never in `init`.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        Log.levels.notice("levels started")
        volumeGate = FirstReadingGate()
        brightnessGate = FirstReadingGate()
        let generation = generation
        let service = volumeService
        let previous = volumeLifecycle
        volumeLifecycle = Task { [weak self] in
            await previous?.value
            let initial = await service.start { [weak self] snapshot, reason in
                Task { @MainActor in
                    self?.volumeServiceUpdated(snapshot, reason: reason, generation: generation)
                }
            }
            guard let self, generation == self.generation else { return }
            // An update that overtook this result already set the baseline.
            _ = self.volumeGate.admit()
            self.adoptVolume(initial, keepValue: self.isWriting(.volume))
        }
        brightnessService.start()
        // The built-in display can disappear (clamshell) or return with a new ID.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.brightnessService.displaysChanged() }
        }
        updateInterception()
    }

    /// Idempotent. Restores the system OSD and removes every listener.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        interceptor.stop()
        interceptor.setPolicy(.passThrough)
        for queue in writeQueues.values { queue.worker?.cancel() }
        writeQueues.removeAll()
        brightnessService.stop()
        let service = volumeService
        let previous = volumeLifecycle
        volumeLifecycle = Task {
            await previous?.value
            await service.stop()
        }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        volumeState = .noDevice
        volume = .unavailable(.volume)
        brightness = .unavailable(.brightness)
        Log.levels.notice("levels stopped")
    }

    /// Replace the system HUD by intercepting the media keys. Arms the tap only while running and
    /// trusted for Accessibility; otherwise `interception` reports `.needsPermission` / `.off`.
    /// A permission changed: a refused key tap is tried again.
    func retryInterception() { interceptor.retryIfFailed() }

    func setInterceptionEnabled(_ enabled: Bool) {
        wantsInterception = enabled
        updateInterception()
    }

    /// Takes back `injectDemo`: shows the real readings again, silently (no change is reported, so
    /// no banner), without restarting anything. The services never saw the fake values, so their
    /// last readings are the real state.
    func endDemo() {
        guard isRunning else {
            volume = .unavailable(.volume)
            brightness = .unavailable(.brightness)
            return
        }
        if !isWriting(.volume) { volume = volumeState.reading }
        if !isWriting(.brightness) { brightness = brightnessService.reading }
    }

    /// Demo/screenshot hook: shows `value` as if a media key had set it. Touches no system state.
    func injectDemo(_ kind: LevelKind, value: Double) {
        let reading = LevelReading(value: LevelStepper.clamped(value), isMuted: false, isAvailable: true, kind: kind)
        switch kind {
        case .volume: volume = reading
        case .brightness: brightness = reading
        }
        onChange?(kind, .key)
    }

    // MARK: - Interception

    private func updateInterception() {
        guard isRunning, wantsInterception else {
            interceptor.stop()
            return
        }
        updatePolicy()
        interceptor.start()
    }

    /// Only keys we can act on are swallowed; recomputed whenever capabilities change (AirPods
    /// connecting, the built-in display going away).
    private func updatePolicy() {
        interceptor.setPolicy(MediaKeyPolicy(
            volume: volumeState.canSetVolume,
            mute: volumeState.canSetMute,
            brightness: brightness.isAvailable
        ))
    }

    private func handleKey(_ event: MediaKeyEvent) {
        guard isRunning else { return }
        switch event.key {
        case .volumeUp, .volumeDown:
            enqueue(.step(up: event.key == .volumeUp, fine: event.isFine), on: .volume, source: .key)
        case .brightnessUp, .brightnessDown:
            enqueue(.step(up: event.key == .brightnessUp, fine: event.isFine), on: .brightness, source: .key)
        case .mute:
            enqueue(.toggleMute, on: .volume, source: .key)
        }
    }

    // MARK: - Service updates

    private func volumeServiceUpdated(_ snapshot: VolumeSnapshot, reason: LevelUpdateReason, generation: Int) {
        guard generation == self.generation else { return }
        let busy = isWriting(.volume)
        let audible = snapshot.differsAudibly(from: volumeState)
        let isChange = volumeGate.admit()
        adoptVolume(snapshot, keepValue: busy)
        if reason == .external, isChange, audible, !busy { onChange?(.volume, .external) }
    }

    private func brightnessServiceUpdated(_ reading: LevelReading, reason: LevelUpdateReason) {
        guard isRunning else { return }
        let busy = isWriting(.brightness)
        let availabilityChanged = reading.isAvailable != brightness.isAvailable
        if busy {
            // Only when it differs: a level changed in place tells its views even when nothing did.
            if availabilityChanged { brightness.isAvailable = reading.isAvailable }
        } else {
            brightness = reading
        }
        if availabilityChanged { updatePolicy() }
        let isChange = brightnessGate.admit()
        if reason == .external, isChange, !busy { onChange?(.brightness, .external) }
    }

    /// `keepValue`: a slider value is still queued, so keep showing it rather than an older result.
    private func adoptVolume(_ snapshot: VolumeSnapshot, keepValue: Bool) {
        let capabilitiesChanged = !snapshot.hasSameCapabilities(as: volumeState)
        volumeState = snapshot
        if keepValue {
            if volume.isAvailable != snapshot.canSetVolume { volume.isAvailable = snapshot.canSetVolume }
        } else {
            volume = snapshot.reading
        }
        if capabilitiesChanged { updatePolicy() }
    }

    // MARK: - Write queues

    private func enqueue(_ action: LevelAction, on kind: LevelKind, source: LevelChangeSource) {
        var queue = writeQueues[kind, default: WriteQueue()]
        if action.isSet { queue.pending.removeAll { $0.action.isSet } }
        queue.pending.append(PendingWrite(action: action, source: source))
        if queue.worker == nil {
            queue.worker = Task { [weak self] in await self?.drain(kind) }
        }
        writeQueues[kind] = queue
    }

    private func drain(_ kind: LevelKind) async {
        let generation = generation
        while generation == self.generation, let next = writeQueues[kind]?.pending.first {
            writeQueues[kind]?.pending.removeFirst()
            await perform(next, on: kind)
        }
        if generation == self.generation { writeQueues[kind]?.worker = nil }
    }

    private func perform(_ write: PendingWrite, on kind: LevelKind) async {
        let generation = generation
        switch kind {
        case .volume:
            let snapshot = switch write.action {
            case .set(let value): await volumeService.setVolume(value)
            case .step(let up, let fine): await volumeService.step(up: up, fine: fine)
            case .toggleMute: await volumeService.toggleMute()
            }
            guard generation == self.generation else { return }
            adoptVolume(snapshot, keepValue: hasPendingSet(.volume))
        case .brightness:
            let result: Double? = switch write.action {
            case .set(let value): await brightnessService.set(value)
            case .step(let up, let fine): await brightnessService.step(up: up, fine: fine)
            case .toggleMute: nil
            }
            guard generation == self.generation else { return }
            if let result, result != brightness.value, !hasPendingSet(.brightness) { brightness.value = result }
        }
        // Fired even when nothing moved (a key at a limit): the HUD must still answer the key.
        onChange?(kind, write.source)
    }

    private func isWriting(_ kind: LevelKind) -> Bool {
        writeQueues[kind]?.worker != nil
    }

    private func hasPendingSet(_ kind: LevelKind) -> Bool {
        writeQueues[kind]?.pending.contains { $0.action.isSet } ?? false
    }
}

/// Whether a reading may count as a change: the first one after a (re)start is the baseline — the
/// state the level is in, not something that just happened — whichever path delivers it first.
nonisolated struct FirstReadingGate: Sendable, Equatable {
    private(set) var hasBaseline = false

    /// Records a reading; true only if a baseline existed before it.
    mutating func admit() -> Bool {
        defer { hasBaseline = true }
        return hasBaseline
    }
}

nonisolated private enum LevelAction: Sendable, Equatable {
    case set(Double)
    case step(up: Bool, fine: Bool)
    case toggleMute

    var isSet: Bool {
        if case .set = self { true } else { false }
    }
}

nonisolated private struct PendingWrite: Sendable {
    var action: LevelAction
    var source: LevelChangeSource
}

private struct WriteQueue {
    var pending: [PendingWrite] = []
    /// Non-nil while the queue is draining.
    var worker: Task<Void, Never>?
}
