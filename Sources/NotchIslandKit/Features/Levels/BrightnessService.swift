import CoreGraphics
import Foundation
import os

/// Brightness of the built-in display through the private DisplayServices framework.
///
/// Why private API: there is no public brightness-change notification, and the public
/// `IODisplayGetFloatParameter` route does not work on Apple-silicon internal displays at all.
/// DisplayServices is event-driven and needs no permission.
///
/// Availability = symbols resolved AND a built-in display exists (`CGDisplayIsBuiltin`) AND change
/// registration returned 0. Only then are brightness keys swallowed; anything less would risk dead keys.
///
/// Registration happens on the main actor, where the legacy app verified callbacks arrive (the
/// framework may bind to the registering thread's run loop). Get/Set go through `BrightnessIO`, off main.
@MainActor final class BrightnessService {
    /// Current reading and why it changed.
    var onUpdate: ((LevelReading, LevelUpdateReason) -> Void)?
    private(set) var reading = LevelReading.unavailable(.brightness)

    /// Notifications can arrive in quick succession; one read per frame is plenty.
    private static let coalescingWindow: Duration = .milliseconds(16)

    private var io: BrightnessIO?
    private var display: CGDirectDisplayID?
    private var routerToken: UInt?
    private var lastWrite: BrightnessChangeFilter.OwnWrite?
    private var pendingRefresh: Task<Void, Never>?
    private var isRunning = false

    /// Idempotent. Resolves DisplayServices lazily (so tests and launch never touch it before this).
    func start() {
        guard !isRunning else { return }
        isRunning = true
        guard let api = DisplayServices.shared else {
            Log.levels.error("DisplayServices symbols missing — brightness HUD off")
            return
        }
        io = BrightnessIO(api: api)
        bindBuiltInDisplay()
    }

    /// Idempotent.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        unbind()
        io = nil
        lastWrite = nil
        reading = .unavailable(.brightness)
    }

    /// Displays were added, removed or reconfigured (`didChangeScreenParametersNotification`): the
    /// built-in display may have gone (clamshell) or come back with another ID.
    func displaysChanged() {
        guard isRunning, io != nil, Self.builtInDisplay() != display else { return }
        bindBuiltInDisplay()
    }

    /// Island slider. Returns the level now set, or `nil` when unavailable or the write failed.
    func set(_ value: Double) async -> Double? {
        guard let io, let display, reading.isAvailable else { return nil }
        let target = LevelStepper.clamped(value)
        guard let result = await io.write(target, to: display) else { return nil }
        didWrite(result)
        return result
    }

    /// Media key. Steps from the value we last set while it is fresh: the panel ramps towards a new
    /// level, and stepping from a mid-ramp read would snap back onto the grid line we just set.
    func step(up: Bool, fine: Bool) async -> Double? {
        guard let io, let display, reading.isAvailable else { return nil }
        let base: Double
        if let lastWrite, lastWrite.isFresh(at: .now) {
            base = lastWrite.value
        } else if let current = await io.read(display) {
            base = current
        } else {
            return nil
        }
        guard let result = await io.write(LevelStepper.stepped(base, up: up, fine: fine), to: display)
        else { return nil }
        didWrite(result)
        return result
    }

    // MARK: - Private

    private func didWrite(_ value: Double) {
        lastWrite = .init(value: value, at: .now)
        reading.value = value
    }

    private func bindBuiltInDisplay() {
        unbind()
        guard let api = DisplayServices.shared, let io, let display = Self.builtInDisplay() else {
            publish(.unavailable(.brightness), .silent)
            return
        }
        let token = BrightnessNotificationRouter.add { [weak self] in
            Task { @MainActor in self?.brightnessDidChange() }
        }
        let status = api.register(display, BrightnessNotificationRouter.context(for: token),
                                  BrightnessNotificationRouter.callback)
        guard status == 0 else {
            BrightnessNotificationRouter.remove(token)
            Log.levels.error("brightness registration failed (\(status)) — brightness HUD off")
            publish(.unavailable(.brightness), .silent)
            return
        }
        routerToken = token
        self.display = display
        pendingRefresh = Task { [weak self] in
            let value = await io.read(display)
            guard let self, !Task.isCancelled, self.display == display else { return }
            self.pendingRefresh = nil
            self.publish(LevelReading(value: value ?? 0, isMuted: false, isAvailable: true, kind: .brightness), .silent)
        }
    }

    private func unbind() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        if let display, let routerToken, let api = DisplayServices.shared {
            _ = api.unregister(display, BrightnessNotificationRouter.context(for: routerToken))
        }
        if let routerToken { BrightnessNotificationRouter.remove(routerToken) }
        routerToken = nil
        display = nil
    }

    private func brightnessDidChange() {
        guard isRunning, pendingRefresh == nil, let io, let display else { return }
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: Self.coalescingWindow)
            guard !Task.isCancelled else { return }
            let value = await io.read(display)
            guard let self, !Task.isCancelled, self.display == display else { return }
            self.pendingRefresh = nil
            guard let value else { return }
            self.classify(value)
        }
    }

    private func classify(_ value: Double) {
        var next = reading
        next.value = value
        switch BrightnessChangeFilter.verdict(for: value, previous: reading.value, ownWrite: lastWrite, now: .now) {
        case .ignore: return
        case .silent: publish(next, .silent)
        case .external: publish(next, .external)
        }
    }

    private func publish(_ next: LevelReading, _ reason: LevelUpdateReason) {
        reading = next
        onUpdate?(next, reason)
    }

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
}

/// Decides what a brightness notification means. Pure, so the thresholds are unit-tested.
///
/// Replaces the legacy "expect self change" flag, which stayed set when a write produced no
/// notification (at a limit) and then let the next ambient micro-change through as a HUD.
nonisolated enum BrightnessChangeFilter {
    nonisolated struct OwnWrite: Sendable, Equatable {
        var value: Double
        var at: ContinuousClock.Instant

        func isFresh(at now: ContinuousClock.Instant) -> Bool {
            now - at < BrightnessChangeFilter.echoWindow
        }
    }

    nonisolated enum Verdict: Sendable, Equatable { case ignore, silent, external }

    /// How long after our own write a notification is presumed to be about that write.
    static let echoWindow: Duration = .seconds(1)
    /// Below the fine step (1/64), above Float32 round-trip noise.
    static let echoTolerance = 0.01
    /// Ambient-light auto-brightness walks the level in many tiny steps; a key press moves it by a
    /// whole step at once. Only key-sized jumps are worth a HUD — otherwise the island would pop
    /// open every time a cloud passes.
    static let reportThreshold = LevelStepper.step * 0.6

    static func verdict(
        for value: Double, previous: Double, ownWrite: OwnWrite?, now: ContinuousClock.Instant
    ) -> Verdict {
        if let ownWrite, ownWrite.isFresh(at: now) {
            // Our level arriving: adopt it quietly. Anything else meanwhile is a ramp frame or a
            // stale read that our write supersedes.
            return abs(value - ownWrite.value) <= echoTolerance ? .silent : .ignore
        }
        let delta = abs(value - previous)
        if delta < 0.001 { return .ignore }
        return delta >= reportThreshold ? .external : .silent
    }
}

/// Serialises DisplayServices Get/Set off the main actor.
private actor BrightnessIO {
    private let api: DisplayServices

    init(api: DisplayServices) {
        self.api = api
    }

    func read(_ display: CGDirectDisplayID) -> Double? {
        var level: Float = 0
        let status = api.getBrightness(display, &level)
        guard status == 0 else {
            Log.levels.error("DisplayServicesGetBrightness failed (\(status))")
            return nil
        }
        return LevelStepper.clamped(Double(level))
    }

    /// Returns the level set. The value we asked for, not a read-back: the panel ramps towards it.
    func write(_ value: Double, to display: CGDirectDisplayID) -> Double? {
        let status = api.setBrightness(display, Float(value))
        guard status == 0 else {
            Log.levels.error("DisplayServicesSetBrightness failed (\(status))")
            return nil
        }
        return value
    }
}

/// Function table resolved from the private DisplayServices framework with dlopen/dlsym. Nothing is
/// linked, so a macOS update that removes a symbol switches the feature off instead of breaking
/// launch. The handle is never dlclosed (the functions must stay valid for the process lifetime).
nonisolated private struct DisplayServices: Sendable {
    /// Verified on macOS 27.0 (26A428): (context, display, "DisplayServicesBrightness", unused, ["value": Float]).
    typealias ChangeCallback = @convention(c) (
        UnsafeMutableRawPointer?, UInt32, CFString?, UnsafeMutableRawPointer?, CFDictionary?
    ) -> Void
    typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    typealias Register = @convention(c) (UInt32, UnsafeMutableRawPointer?, ChangeCallback) -> Int32
    typealias Unregister = @convention(c) (UInt32, UnsafeMutableRawPointer?) -> Int32

    let getBrightness: GetBrightness
    let setBrightness: SetBrightness
    let register: Register
    let unregister: Unregister

    /// Resolved on first use (from `BrightnessService.start()`), once per process.
    static let shared: DisplayServices? = load()

    private static func load() -> DisplayServices? {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        func symbol<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let get = symbol("DisplayServicesGetBrightness", as: GetBrightness.self),
              let set = symbol("DisplayServicesSetBrightness", as: SetBrightness.self),
              let register = symbol("DisplayServicesRegisterForBrightnessChangeNotifications", as: Register.self),
              let unregister = symbol("DisplayServicesUnregisterForBrightnessChangeNotifications", as: Unregister.self)
        else { return nil }
        return DisplayServices(getBrightness: get, setBrightness: set, register: register, unregister: unregister)
    }
}

/// Routes the capture-less C callback back to its owner. The registration context is an integer
/// token rather than an object pointer, so a callback racing an unregister can never touch freed
/// memory — an unknown token is simply dropped.
nonisolated private enum BrightnessNotificationRouter {
    private struct Registry {
        var nextToken: UInt = 1   // non-zero: the context must not be NULL
        var handlers: [UInt: @Sendable () -> Void] = [:]
    }

    private static let registry = OSAllocatedUnfairLock(initialState: Registry())

    static let callback: DisplayServices.ChangeCallback = { context, _, _, _, _ in
        let token = UInt(bitPattern: context)
        let handler = registry.withLock { $0.handlers[token] }
        handler?()
    }

    static func add(_ handler: @escaping @Sendable () -> Void) -> UInt {
        registry.withLock { registry in
            let token = registry.nextToken
            registry.nextToken += 1
            registry.handlers[token] = handler
            return token
        }
    }

    static func remove(_ token: UInt) {
        registry.withLock { _ = $0.handlers.removeValue(forKey: token) }
    }

    static func context(for token: UInt) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: token)
    }
}
