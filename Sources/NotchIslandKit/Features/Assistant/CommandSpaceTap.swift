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
@MainActor final class CommandSpaceTap {
    /// Called on the main actor for each ⌘Space press.
    var onPress: (() -> Void)?

    private let shared = CommandSpaceTapShared()
    private var generation: UInt64 = 0
    private(set) var isRunning = false

    /// The space bar (`kVK_Space`).
    nonisolated static let spaceKeyCode: Int64 = 49

    /// The modifier held with Space (Settings ▸ Siri ▸ Shortcut); takes effect on the next press.
    func setModifiers(_ modifiers: CGEventFlags) {
        shared.setModifiers(modifiers)
    }

    /// Idempotent. Without Accessibility nothing is created (the tap could not swallow anything).
    func start() {
        guard !isRunning, AXIsProcessTrusted() else { return }
        isRunning = true
        generation &+= 1
        let generation = generation
        shared.begin(generation: generation)
        let deliver: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.onPress?() }
        }
        let thread = Thread { [shared] in
            CommandSpaceTapThread.run(generation: generation, shared: shared, deliver: deliver)
        }
        thread.name = "com.davidvarga.notchisland.commandspace"
        thread.qualityOfService = .userInteractive
        thread.start()
        Log.app.notice("⌘Space tap armed")
    }

    /// Idempotent.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation &+= 1
        shared.end()
        Log.app.notice("⌘Space tap stopped")
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
    var port: CFMachPort?
    var pressed = false

    init(deliver: @escaping @Sendable () -> Void, shared: CommandSpaceTapShared) {
        self.deliver = deliver
        self.shared = shared
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            let isDown = type == .keyDown
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
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
    static func run(generation: UInt64, shared: CommandSpaceTapShared, deliver: @escaping @Sendable () -> Void) {
        let session = CommandSpaceTapSession(deliver: deliver, shared: shared)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            return Unmanaged<CommandSpaceTapSession>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
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
                return
            }
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0),
                  let runLoop = CFRunLoopGetCurrent(),
                  shared.attach(runLoop, generation: generation) else {
                CFMachPortInvalidate(port)
                return
            }
            session.port = port
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            // No timeout: a finite one would wake this thread periodically forever.
            while shared.isActive(generation) {
                let result = CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, false)
                if result == .finished || result == .stopped, !shared.isActive(generation) { break }
            }
            CGEvent.tapEnable(tap: port, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(port)
        }
    }
}
