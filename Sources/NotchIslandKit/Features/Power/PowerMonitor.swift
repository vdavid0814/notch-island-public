import Foundation
import IOKit.ps
import Observation

/// Battery and power-adapter state, pushed by IOKit — never polled.
///
/// An idle monitor is one mach port on the main run loop plus one notification observer
/// for Low Power Mode. IOKit posts when anything about a power source changes; the
/// monitor then reads once, publishes only real changes and lets `PowerAnnouncer` decide
/// what is worth a banner.
@Observable final class PowerMonitor {

    /// What the UI shows: the demo state while one is injected, the real state otherwise.
    private(set) var state: PowerState = .unknown

    /// `state.isOnBattery` on its own. On battery the level and the time left change about once a
    /// minute; the island's views that only pick lighter work on battery read this instead of
    /// `state`, so those changes do not re-evaluate them (the island's root among them).
    private(set) var isOnBattery = false

    /// Plug / unplug / charged / low. Fired for real transitions only (never for the first
    /// reading after `start()`, never while a demo state is showing).
    @ObservationIgnored var onEvent: ((PowerEvent) -> Void)?

    @ObservationIgnored private let readState: () -> PowerState
    /// The live IOKit reader (not a test fixture): refreshes can run it off the main thread.
    @ObservationIgnored private let readsIOKit: Bool
    /// Latest background read wins; an older one finishing late is dropped.
    @ObservationIgnored private var readGeneration = 0
    @ObservationIgnored private var realState: PowerState = .unknown
    @ObservationIgnored private var demoState: PowerState?
    @ObservationIgnored private var announcer = PowerAnnouncer()
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var callbackContext: Unmanaged<CallbackContext>?
    @ObservationIgnored private var lowPowerObserver: (any NSObjectProtocol)?

    /// - Parameter readState: the source of truth; tests inject fixtures. Defaults to a
    ///   live IOKit read, which system-driven refreshes then do off the main thread.
    init(readState: (() -> PowerState)? = nil) {
        self.readState = readState ?? { PowerMonitor.readIOKit() }
        readsIOKit = readState == nil
    }

    var isRunning: Bool { runLoopSource != nil }

    /// Idempotent. The first reading is published without announcing anything.
    func start() {
        guard runLoopSource == nil else { return }

        let context = CallbackContext(monitor: self)
        let retained = Unmanaged.passRetained(context)
        guard let source = IOPSNotificationCreateRunLoopSource(Self.powerSourcesChanged,
                                                               retained.toOpaque())?.takeRetainedValue()
        else {
            retained.release()
            Log.power.error("could not create the power-source run loop source; battery UI stays off")
            return
        }
        // Common modes, so a change that happens while a menu is open or a drag is being
        // tracked (event-tracking run-loop mode) is not deferred until it ends.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        callbackContext = retained

        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil
        ) { [weak self] _ in
            // Posted on an arbitrary thread.
            Task { @MainActor in self?.refreshFromSystem() }
        }

        // The first reading describes the present, not a change: it only seeds the
        // announcer. It is published unconditionally — `refresh()` skips readings equal to
        // the last one, and after a stop/start cycle the screen may still show a stale
        // state that happens to equal the placeholder.
        announcer = PowerAnnouncer()
        realState = readState()
        _ = announcer.events(from: .unknown, to: realState)
        if demoState == nil { publish(realState) }
        Log.power.notice("power monitor armed (IOKit run-loop source)")
    }

    /// Idempotent.
    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        runLoopSource = nil
        // The source is gone from the main run loop and we are on the main thread, so no
        // callback can still be running with this pointer; a hop it already scheduled holds
        // its own reference.
        callbackContext?.release()
        callbackContext = nil
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
        }
        lowPowerObserver = nil
    }

    /// Demo / screenshot hook. A non-nil state replaces the real one on screen until
    /// `injectDemo(nil, event: nil)`; `event` is delivered as if it had happened.
    func injectDemo(_ state: PowerState?, event: PowerEvent?) {
        demoState = state
        publish(state ?? realState)
        if let event { onEvent?(event) }
    }

    /// Reads IOKit once and publishes the result. Internal so tests can drive it.
    func refresh() {
        apply(readState())
    }

    /// A change reported by the system: IOKit is read on a background thread (it is an IPC round
    /// trip to powerd) and only the parsed state comes back to the main actor.
    private func refreshFromSystem() {
        guard readsIOKit else { return refresh() }
        readGeneration &+= 1
        let generation = readGeneration
        Task.detached(priority: .utility) { [weak self] in
            let next = PowerMonitor.readIOKit()
            await self?.applyRead(next, generation: generation)
        }
    }

    private func applyRead(_ next: PowerState, generation: Int) {
        guard generation == readGeneration, runLoopSource != nil else { return }
        apply(next)
    }

    private func apply(_ next: PowerState) {
        guard next != realState else { return }
        let previous = realState
        realState = next

        // The announcer always sees real transitions so its memory stays true; the events
        // are dropped while a demo owns the screen, because a banner describing real data
        // over a fake state would contradict itself.
        let events = announcer.events(from: previous, to: next)
        guard demoState == nil else { return }
        publish(next)
        for event in events {
            Log.power.notice("power event: \(String(describing: event), privacy: .public)")
            onEvent?(event)
        }
    }

    private func publish(_ next: PowerState) {
        // Observation notifies on every assignment; IOKit posts for fields we do not
        // model, so skip no-op writes.
        if state != next { state = next }
        if isOnBattery != next.isOnBattery { isOnBattery = next.isOnBattery }
    }

    // MARK: IOKit bridge

    /// Weak hop from the C callback back to the monitor. Retained by the monitor while
    /// the run-loop source exists, so the context pointer IOKit holds is always valid,
    /// while the monitor itself can still be released at any time.
    private final class CallbackContext {
        weak var monitor: PowerMonitor?
        init(monitor: PowerMonitor) { self.monitor = monitor }
    }

    /// Runs on the main run loop (that is where the source is installed), but as a C
    /// function it is nonisolated, so it hops onto the main actor explicitly.
    private nonisolated static let powerSourcesChanged: IOPowerSourceCallbackType = { raw in
        guard let raw else { return }
        let context = Unmanaged<CallbackContext>.fromOpaque(raw).takeUnretainedValue()
        Task { @MainActor in context.monitor?.refreshFromSystem() }
    }

    /// One pass over IOKit's power sources.
    nonisolated static func readIOKit() -> PowerState {
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSourceParser.state(descriptions: [], providingType: nil,
                                           isLowPowerMode: isLowPowerMode)
        }
        let sources = (IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]) ?? []
        let descriptions = sources.compactMap { source in
            IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        }
        let providingType = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        return PowerSourceParser.state(descriptions: descriptions, providingType: providingType,
                                       isLowPowerMode: isLowPowerMode)
    }
}
