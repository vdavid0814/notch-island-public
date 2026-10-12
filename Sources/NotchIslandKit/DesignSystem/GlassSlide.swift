import AppKit

/// Work held back until the glass of the segmented bar just clicked has come to rest.
///
/// A Liquid Glass segmented control slides its selection to the clicked segment on the app's main
/// thread. Any long turn while it slides stops it where it is: the page bar's page switch, the
/// gallery's categories and the stage's modes (~50–100 ms each) made it hitch — mid-way at first,
/// then, once they waited a fixed 0.17 s, once more just before it settled (the user's recordings,
/// frame by frame). So the work waits until the bar's layers stop moving: their places and
/// opacities, as the render server shows them, polled once a frame (a few dozen layers).
///
/// The bar is the one under the click being handled; without one (a change made in code, a key) the
/// work runs after `fallback`.
@MainActor final class GlassSlide {
    private var timer: Timer?
    private var work: (@MainActor () -> Void)?
    private var startedAt: TimeInterval?
    private var found = false
    private var motion: (Int, TimeInterval) = (0, 0)

    /// Whether work is waiting.
    var isWaiting: Bool { work != nil }

    /// Runs `work` once the bar clicked now has settled — not before `minimum`, at the latest after
    /// `maximum` (the glass also leans after the pointer while it rests over the bar). A later call
    /// replaces work still waiting.
    func afterSettling(minimum: TimeInterval = 0.12, maximum: TimeInterval = 0.6, fallback: TimeInterval = 0.17,
                       _ work: @escaping @MainActor () -> Void) {
        cancel()
        self.work = work
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return finish() }
        let control = Self.clickedControl()
        let start = ProcessInfo.processInfo.systemUptime
        startedAt = start
        var last: [CGRect]?
        var still = 0
        var moving = 0
        var lastMove: TimeInterval = 0
        found = control != nil
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                guard let control, control.window != nil else {
                    if elapsed >= fallback { self.finish() }
                    return
                }
                let now = Self.signature(of: control)
                if let last, last.count == now.count, zip(last, now).allSatisfy(Self.isClose) {
                    still += 1
                } else {
                    still = 0
                    moving += 1
                    lastMove = elapsed
                }
                self.motion = (moving, lastMove)
                last = now
                if elapsed >= maximum || (elapsed >= minimum && still >= 2) { self.finish() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        work = nil
    }

    private func finish() {
        if let start = startedAt {
            PerfTrace.mark(String(format: "glass settled after %.0f ms (bar found %@, %d moving looks, last move at %.0f ms)",
                                  (ProcessInfo.processInfo.systemUptime - start) * 1000, found ? "yes" : "no", motion.0, motion.1 * 1000))
        }
        timer?.invalidate()
        timer = nil
        let work = self.work
        self.work = nil
        work?()
    }

    /// Where the last press in a window landed (`SettingsWindow.sendEvent`): the bar clicked is
    /// the one under it. SwiftUI's segmented picker hit-tests to its hosting view, not to the bar.
    static func pressed(at point: NSPoint, in window: NSWindow) {
        lastPress = Press(point: point, window: window, time: ProcessInfo.processInfo.systemUptime)
    }

    /// Held weakly: a window given up (Settings on the charger) must not be kept by its last click.
    private struct Press {
        let point: NSPoint
        weak var window: NSWindow?
        let time: TimeInterval
    }

    private static var lastPress: Press?

    /// The segmented control under the last press, if it was a moment ago.
    private static func clickedControl() -> NSSegmentedControl? {
        guard let press = lastPress, ProcessInfo.processInfo.systemUptime - press.time < 2,
              let content = press.window?.contentView else { return nil }
        func find(_ view: NSView) -> NSSegmentedControl? {
            guard !view.isHidden else { return nil }
            if let control = view as? NSSegmentedControl, control.convert(control.bounds, to: nil).contains(press.point) { return control }
            for sub in view.subviews.reversed() { if let found = find(sub) { return found } }
            return nil
        }
        return find(content)
    }

    /// Where the bar's layers are drawn now, and how opaque, as the render server shows them.
    private static func signature(of control: NSView) -> [CGRect] {
        var frames: [CGRect] = []
        func walk(_ layer: CALayer, depth: Int) {
            let shown = layer.presentation() ?? layer
            frames.append(CGRect(origin: shown.position, size: shown.bounds.size).offsetBy(dx: CGFloat(shown.opacity) * 100, dy: 0))
            guard depth < 6 else { return }
            for sublayer in layer.sublayers ?? [] { walk(sublayer, depth: depth + 1) }
        }
        if let layer = control.layer { walk(layer, depth: 0) }
        return frames
    }

    /// Moved less than half a point (or barely faded) since the last look.
    private static func isClose(_ pair: (CGRect, CGRect)) -> Bool {
        abs(pair.0.minX - pair.1.minX) < 0.5 && abs(pair.0.minY - pair.1.minY) < 0.5
            && abs(pair.0.width - pair.1.width) < 0.5 && abs(pair.0.height - pair.1.height) < 0.5
    }
}
