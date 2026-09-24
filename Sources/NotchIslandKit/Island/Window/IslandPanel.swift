import AppKit

/// The borderless overlay window the island lives in.
///
/// Its frame is the stage and belongs to `IslandWindowController` alone (`stage(_:)`). Anything
/// else that tries to move or resize it — AppKit, or an `NSHostingView` fitting a non-resizable
/// window to its SwiftUI content — gets the staged frame back: a frame changing behind the
/// controller offsets the island, and inside a display cycle it makes SwiftUI invalidate its
/// transform on every constraints pass until AppKit throws.
final class IslandPanel: NSPanel {
    /// Above the menu bar, below open menus and Control Center.
    static let restingLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    /// While the AirPods card is up in "cover" mode: above macOS's own AirPods card (a
    /// `popUpMenu`-level window, 101), which it hides.
    static let coveringLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)

    private var stagedFrame: NSRect?

    init(contentRect: NSRect) {
        // Set once and never mutated: changing styleMask on a live panel
        // desynchronises AppKit from the window server's activation flags.
        // `.nonactivatingPanel` (with canBecomeKey == false) means clicking the
        // island never pulls focus from the user's app.
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above the menu bar, deliberately below open menus and Control Center
        // (popUpMenu), so a pulled-down menu that lands under the island wins.
        level = Self.restingLevel
        // All Spaces + fullScreenAuxiliary put the panel over full-screen apps
        // (the level alone does not); stationary keeps Mission Control from
        // moving it, as with the menu bar; ignoresCycle keeps it out of ⌘`.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Transparent everywhere the island is not drawn: the window server
        // hit-tests by per-pixel alpha, so clicks there reach the app below.
        isOpaque = false
        backgroundColor = .clear
        // Always dark, like the CAD app's floating UI: Liquid Glass samples the
        // window's appearance, and the smoked `IslandGlass` needs light content.
        appearance = NSAppearance(named: .darkAqua)
        // Glass draws its own shadow; a window shadow is non-zero alpha that
        // would swallow menu-bar clicks.
        hasShadow = false
        // An accessory app is never active; hiding on deactivate would hide it always.
        hidesOnDeactivate = false
        // No AppKit fade on order-in/out; SwiftUI owns every animation.
        animationBehavior = .none
        isMovable = false
        isMovableByWindowBackground = false
        isRestorable = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        tabbingMode = .disallowed
        // Hover comes from a tracking area; mouse-moved events would only cost wake-ups.
        acceptsMouseMovedEvents = false
    }

    /// Moves the stage and has SwiftUI lay the current content out for it before returning.
    ///
    /// `setFrame(display: true)` is not enough: NSHostingView adopts a new size only in its next
    /// layout, so that display drew the old layout into the new frame and the size arrived one
    /// frame later — inside the transition's animated transaction, which then slid the island in
    /// from where the stale layout had put it (up to the stage margin off-centre). Laying out here
    /// makes the new size a non-animated update of its own, ahead of `withAnimation`.
    func stage(_ frame: NSRect) {
        stagedFrame = frame
        guard self.frame != frame else { return }
        super.setFrame(frame, display: false)
        contentView?.layoutSubtreeIfNeeded()
        displayIfNeeded()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(adopted(frameRect), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(adopted(frameRect), display: displayFlag, animate: animateFlag)
    }

    private func adopted(_ frameRect: NSRect) -> NSRect {
        guard let stagedFrame, frameRect != stagedFrame else { return frameRect }
        Log.window.notice("refused frame \(frameRect.logDescription, privacy: .public); stage is \(stagedFrame.logDescription, privacy: .public)")
        return stagedFrame
    }

    /// True only while the assistant is open: the panel may then become key (without the app
    /// becoming active or taking the front — measured: the frontmost app stays frontmost), so its
    /// text field receives typing. Everywhere else a click on the island must not take focus.
    /// Setting it back to false does not resign key; `IslandWindowController` hands the keyboard
    /// back explicitly.
    var acceptsKeyboard = false

    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }

    /// While the island has the keyboard, app-level shortcuts would act on NotchIsland itself — the
    /// SwiftUI app lifecycle builds a full main menu even for this agent — quitting or hiding it (or
    /// every other app) from inside a search field. Editing shortcuts (⌘C/⌘V/⌘X/⌘A/⌘Z) still reach
    /// the Edit menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if acceptsKeyboard, Self.isSwallowedShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// ⌘Q, ⌘H, ⌥⌘H, ⌘M, ⌘W.
    static func isSwallowedShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control) else { return false }
        return ["q", "h", "m", "w"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "")
    }

    // MARK: Active appearance
    //
    // Liquid Glass renders its live, see-through look (the one the system's Liquid Glass slider
    // controls) only in a window that has the active appearance; in an inactive window it falls back
    // to a flat, near-opaque fill. This panel can never become key or main (it must not take focus),
    // so AppKit would treat it as inactive forever. This answers AppKit's own appearance query
    // instead: the panel looks active (ignoring key focus) without ever becoming key. Measured on
    // macOS 27: this one override is enough; `_hasActiveAppearance` and the main-appearance queries
    // add nothing.
    //
    // It is AppKit SPI (no public equivalent exists: `NSGlassEffectView` has no state property,
    // unlike `NSVisualEffectView.state`). If a future AppKit stops asking, the island falls back to
    // the inactive glass; nothing else depends on it.

    @objc(_hasActiveAppearanceIgnoringKeyFocus) private func islandHasActiveAppearanceIgnoringKeyFocus() -> Bool { true }

    /// The panel sits in the menu-bar strip, where AppKit would otherwise push
    /// it down below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
