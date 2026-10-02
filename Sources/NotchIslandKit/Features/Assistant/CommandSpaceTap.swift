import AppKit
import ApplicationServices
import os

/// ⌘Space opens Siri in the notch instead of the system's Search window.
///
/// A session event tap for key presses only, inserted at the head, so it sees ⌘Space before the
/// system's own shortcut handling and swallows it (both the key-down and its key-up, so the system
/// never sees half a press). Every other key passes straight through, in microseconds. It runs on
/// its own thread (a tap callback must never wait for the main thread) and needs Accessibility,
/// which the app already asks for. Off → the system shortcut works as before.
///
/// The key tap is only switched on while the chosen modifier is held (or a swallowed press is still
/// down): a second tap on modifier changes alone switches it. On for good, every key typed anywhere
/// woke the app twice (Energy Impact ~0.2 while typing, measured); modifiers change rarely. The
/// modifier tap is not listen-only, so the key tap is on before the event after it is delivered.
@MainActor final class CommandSpaceTap {
    /// Called on the main actor for each ⌘Space press.
    var onPress: (() -> Void)?

    private let shared = CommandSpaceTapShared()
    private var generation: UInt64 = 0
    /// A tap thread is out (starting or installed). Not "working": see `state`.
    private(set) var isRunning = false
    /// What the tap really does: `.active` only once the thread has installed it, `.failed` when
    /// macOS refused it (Input Monitoring off, or right after unlocking the screen).
    private(set) var state: InterceptionState = .off {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((InterceptionState) -> Void)?
    /// Set between `start()` and `stop()`: the owner wants the tap, even while it is retried.
    private var wantsRunning = false
    private var retry: Task<Void, Never>?
    private var failedAttempts = 0
    /// After a refused tap: tried again this long after each failure, then left failed (a later
    /// start, an unlock or a permission granted tries again).
    nonisolated static let retryDelays: [Duration] = [.seconds(1), .seconds(3), .seconds(8)]

    /// The space bar (`kVK_Space`).
    nonisolated static let spaceKeyCode: Int64 = 49

    /// The modifier held with Space (Settings ▸ Siri ▸ Shortcut); takes effect on the next press.
    func setModifiers(_ modifiers: CGEventFlags) {
        shared.setModifiers(modifiers)
    }

    /// Idempotent. Without Accessibility nothing is created (the tap could not swallow anything).
    func start() {
        wantsRunning = true
        guard !isRunning else { return }
        guard AXIsProcessTrusted() else {
            state = .needsPermission
            return
        }
        isRunning = true
        generation &+= 1
        let generation = generation
        shared.begin(generation: generation)
        let deliver: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.onPress?() }
        }
        let report: @Sendable (Bool) -> Void = { [weak self] installed in
            Task { @MainActor in self?.received(installed: installed, generation: generation) }
        }
        let thread = Thread { [shared] in
            CommandSpaceTapThread.run(generation: generation, shared: shared, deliver: deliver, report: report)
        }
        thread.name = "com.davidvarga.notchisland.commandspace"
        thread.qualityOfService = .userInteractive
        thread.start()
        Log.app.notice("⌘Space tap armed")
    }

    /// Idempotent.
    func stop() {
        wantsRunning = false
        retry?.cancel()
        retry = nil
        failedAttempts = 0
        state = .off
        guard isRunning else { return }
        isRunning = false
        generation &+= 1
        shared.end()
        Log.app.notice("⌘Space tap stopped")
    }

    private func received(installed: Bool, generation: UInt64) {
        guard generation == self.generation, isRunning else { return }
        if installed {
            failedAttempts = 0
            state = .active
            return
        }
        isRunning = false
        shared.end()
        state = .failed(CGPreflightListenEventAccess()
            ? "macOS refused the keyboard event tap."
            : "Input Monitoring is not allowed, so macOS refused the keyboard event tap.")
        guard wantsRunning, retry == nil, failedAttempts < Self.retryDelays.count else { return }
        let delay = Self.retryDelays[failedAttempts]
        failedAttempts += 1
        retry = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.retry = nil
            guard self.wantsRunning, !self.isRunning else { return }
            Log.app.notice("⌘Space tap: trying again")
            self.start()
        }
    }

    /// A permission changed or the screen was unlocked: a failed tap gets a fresh set of attempts.
    func retryIfFailed() {
        guard wantsRunning, !isRunning else { return }
        retry?.cancel()
        retry = nil
        failedAttempts = 0
        start()
    }

    /// The decision for one key event. Pure, for tests: Space with exactly the chosen modifier
    /// (⌘ by default; no other of Shift, Option, Control, Command, which other shortcuts use) is
    /// ours; its key-up and repeats go with it.
    nonisolated static func swallows(keyCode: Int64, isDown: Bool, flags: CGEventFlags,
                                     modifiers wanted: CGEventFlags = .maskCommand, pressed: inout Bool) -> Bool {
        guard keyCode == spaceKeyCode else { return false }
        if !isDown {
            defer { pressed = false }
            return pressed
        }
        let modifiers = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        if modifiers == wanted {
            pressed = true
            return true
        }
        return pressed
    }
}

/// State shared between the main actor and the tap thread.
nonisolated private final class CommandSpaceTapShared: Sendable {
    private struct State {
        var activeGeneration: UInt64?
        var runLoop: CFRunLoop?
        var modifiers: CGEventFlags = .maskCommand
    }

    private let lock = OSAllocatedUnfairLock(uncheckedState: State())

    func begin(generation: UInt64) {
        lock.withLockUnchecked {
            $0.activeGeneration = generation
            $0.runLoop = nil
        }
    }

    func end() {
        let runLoop = lock.withLockUnchecked { state -> CFRunLoop? in
            state.activeGeneration = nil
            defer { state.runLoop = nil }
            return state.runLoop
        }
        if let runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(CFRunLoopGetCurrent()) }
            CFRunLoopWakeUp(runLoop)
        }
    }

    func attach(_ runLoop: CFRunLoop, generation: UInt64) -> Bool {
        lock.withLockUnchecked { state in
            guard state.activeGeneration == generation else { return false }
            state.runLoop = runLoop
            return true
        }
    }

    func setModifiers(_ modifiers: CGEventFlags) {
        lock.withLockUnchecked { $0.modifiers = modifiers }
    }

    var modifiers: CGEventFlags {
        lock.withLockUnchecked { $0.modifiers }
    }

    func isActive(_ generation: UInt64) -> Bool {
        lock.withLockUnchecked { $0.activeGeneration == generation }
    }
}

/// Confined to the tap thread.
nonisolated private final class CommandSpaceTapSession {
    let deliver: @Sendable () -> Void
    let shared: CommandSpaceTapShared
    /// Key presses: on only while `armed`.
    var port: CFMachPort?
    /// Modifier changes: always on.
    var flagsPort: CFMachPort?
    var pressed = false
    /// The chosen modifier is held: the key tap is on.
    private var heldModifier = false
    private var armed = false

    init(deliver: @escaping @Sendable () -> Void, shared: CommandSpaceTapShared) {
        self.deliver = deliver
        self.shared = shared
    }

    /// The key tap follows the modifier, and stays on until a swallowed press has come back up.
    func updateArming(flags: CGEventFlags) {
        heldModifier = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == shared.modifiers
        rearm()
    }

    private func rearm() {
        let wanted = heldModifier || pressed
        guard wanted != armed, let port else { return }
        armed = wanted
        CGEvent.tapEnable(tap: port, enable: wanted)
    }

    func handleFlags(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let flagsPort { CGEvent.tapEnable(tap: flagsPort, enable: true) }
        case .flagsChanged:
            updateArming(flags: event.flags)
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port, armed { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            let isDown = type == .keyDown
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            // A key's own flags are the truth (a modifier change the other tap missed).
            heldModifier = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]) == shared.modifiers
            defer { rearm() }
            guard CommandSpaceTap.swallows(keyCode: keyCode, isDown: isDown, flags: event.flags,
                                           modifiers: shared.modifiers, pressed: &pressed) else {
                return Unmanaged.passUnretained(event)
            }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isDown, !isRepeat { deliver() }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}

nonisolated private enum CommandSpaceTapThread {
    static func run(generation: UInt64, shared: CommandSpaceTapShared, deliver: @escaping @Sendable () -> Void,
                    report: @escaping @Sendable (Bool) -> Void) {
        let session = CommandSpaceTapSession(deliver: deliver, shared: shared)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<CommandSpaceTapSession>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
        }
        let flagsCallback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<CommandSpaceTapSession>.fromOpaque(refcon).takeUnretainedValue().handleFlags(type, event)
        }
        withExtendedLifetime(session) {
            let mask = (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue))
                | (CGEventMask(1) << CGEventMask(CGEventType.keyUp.rawValue))
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(session).toOpaque()
            ) else {
                Log.app.error("⌘Space tap could not be created")
                report(false)
                return
            }
            guard let flagsPort = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1) << CGEventMask(CGEventType.flagsChanged.rawValue),
                callback: flagsCallback,
                userInfo: Unmanaged.passUnretained(session).toOpaque()
            ) else {
                CFMachPortInvalidate(port)
                Log.app.error("⌘Space modifier tap could not be created")
                report(false)
                return
            }
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0),
                  let flagsSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, flagsPort, 0),
                  let runLoop = CFRunLoopGetCurrent(),
                  shared.attach(runLoop, generation: generation) else {
                CFMachPortInvalidate(port)
                CFMachPortInvalidate(flagsPort)
                return
            }
            session.port = port
            session.flagsPort = flagsPort
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CFRunLoopAddSource(runLoop, flagsSource, .commonModes)
            // Off until the modifier goes down (it may be held already).
            CGEvent.tapEnable(tap: port, enable: false)
            CGEvent.tapEnable(tap: flagsPort, enable: true)
            session.updateArming(flags: CGEventSource.flagsState(.combinedSessionState))
            report(true)
            // No timeout: a finite one would wake this thread periodically forever.
            while shared.isActive(generation) {
                let result = CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, false)
                if result == .finished || result == .stopped, !shared.isActive(generation) { break }
            }
            CGEvent.tapEnable(tap: port, enable: false)
            CGEvent.tapEnable(tap: flagsPort, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopRemoveSource(runLoop, flagsSource, .commonModes)
            CFMachPortInvalidate(port)
            CFMachPortInvalidate(flagsPort)
        }
    }
}
