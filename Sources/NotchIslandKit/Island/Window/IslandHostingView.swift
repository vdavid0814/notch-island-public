import AppKit
import SwiftUI

/// Hosts the SwiftUI island and scopes every pointer interaction to the island
/// itself: hit testing, hover and file drops outside `islandRect` do not exist
/// for this view.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    /// Hit, hover and drop region in window coordinates (AppKit's bottom-left origin, as the stage
    /// geometry computes it). The window controller sets it to the union of both ends during a
    /// transition (the island is visibly large while it closes) and to the target after the settle.
    var islandRect: CGRect = .zero {
        didSet {
            // Also when the rect is unchanged: the window may have been resized under it, which moves
            // it in this (flipped) view's coordinates.
            rebuildTrackingArea()
            // The window frame usually changed together with the rect; a tracking
            // area replaced under a still pointer reports nothing, so re-check.
            setNeedsPointerRefresh()
        }
    }

    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    var onClick: (() -> Void)?
    /// A scroll over the island (trackpad swipe or wheel); true when it was used (then SwiftUI's
    /// scroll views under it do not get it).
    var onScroll: ((NSEvent) -> Bool)?
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var onDrop: (([URL]) -> Bool)?
    /// Asked when a file drag arrives (shelf disabled, or a drag of our own tile → refuse).
    var acceptsDrop: (() -> Bool)?

    /// `islandRect` in this view's own coordinates, where events, hit tests and tracking areas live.
    ///
    /// A hosting view is flipped (origin top-left) while the rect comes with AppKit's bottom-left
    /// origin. Using it unconverted put the hover region `restingMargin` too low whenever the stage
    /// had a margin (compact, banner, mid-transition): the top of the pill, where a pointer thrown at
    /// the notch comes to rest, did not count as inside, and a strip below the island did.
    var region: CGRect { convert(islandRect, from: nil) }

    private var trackingArea: NSTrackingArea?
    private var isPointerInside = false
    private var isDragInside = false
    private var isPointerRefreshPending = false
    private var updatePassDepth = 0

    /// True while AppKit runs this view's constraints or layout pass, which is
    /// where SwiftUI updates its graph and runs view callbacks. Moving the
    /// window then changes the transform SwiftUI is computing, and it asks for
    /// another pass, and another, until AppKit throws; the window controller
    /// defers a stage change requested now.
    var isInUpdatePass: Bool { updatePassDepth > 0 }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        // The island's size comes from IslandLayout, never from the window, and
        // the window's size comes from the stage, never from SwiftUI: no
        // min/max/intrinsic size constraints. (Not enough on its own to keep
        // SwiftUI off the window's frame; see IslandWindowController.ensurePanel.)
        sizingOptions = []
        // The panel overlaps the notch on purpose; a safe-area inset would push the island down.
        safeAreaRegions = []
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("IslandHostingView is created in code only")
    }

    override func updateConstraints() {
        updatePassDepth += 1
        defer { updatePassDepth -= 1 }
        super.updateConstraints()
    }

    override func layout() {
        updatePassDepth += 1
        defer { updatePassDepth -= 1 }
        super.layout()
    }

    // MARK: Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's coordinate system.
        guard region.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    /// The panel never becomes key, so without this the first click on a
    /// control would be spent activating the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Clicks that reach the hosting view itself (not a control's backing view)
    /// are reported; the controller acts on them only when the island is not
    /// expanded, so a click inside the expanded panel never toggles anything.
    /// Reported after SwiftUI has seen the event: an expand re-stages the
    /// window, which must not move the frame under an event still in flight.
    override func mouseDown(with event: NSEvent) {
        let inside = region.contains(convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
        if inside { onClick?() }
    }

    // MARK: Scroll

    override func scrollWheel(with event: NSEvent) {
        let inside = region.contains(convert(event.locationInWindow, from: nil))
        if inside, onScroll?(event) == true { return }
        super.scrollWheel(with: event)
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        guard let trackingArea, event.trackingArea === trackingArea else {
            return super.mouseEntered(with: event)
        }
        setPointerInside(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard let trackingArea, event.trackingArea === trackingArea else {
            return super.mouseExited(with: event)
        }
        setPointerInside(false)
    }

    /// One tracking area over the island only (SwiftUI keeps its own areas).
    /// `.activeAlways` because an accessory app is never active;
    /// `.enabledDuringMouseDrag` so a file drag over the notch counts as hover.
    private func rebuildTrackingArea() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = nil
        let region = region
        guard !region.isEmpty else { return }
        let area = NSTrackingArea(
            rect: region,
            options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// Re-derives hover from the real pointer position on the next main-actor
    /// turn. Needed whenever the rect or the window's visibility changes, because
    /// a tracking area never reports a pointer that was already inside when it
    /// appeared.
    ///
    /// Never synchronous: rect changes happen while the stage is being moved,
    /// inside a transition, and a hover callback there would start the next
    /// transition from within the current one. Coalesced: however many changes
    /// a turn makes, only the final rect is judged, so a pointer resting where
    /// one rect contains it and the next does not produces no enter/exit pair.
    func setNeedsPointerRefresh() {
        guard !isPointerRefreshPending else { return }
        isPointerRefreshPending = true
        Task { [weak self] in
            guard let self else { return }
            self.isPointerRefreshPending = false
            self.refreshPointerState()
        }
    }

    private func refreshPointerState() {
        guard let window else { return }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setPointerInside(window.isVisible && region.contains(location))
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        if inside { onPointerEntered?() } else { onPointerExited?() }
    }

    // MARK: File drops

    // File drops are handled here and reported to the controller (SwiftUI drop
    // destinations inside the island are intentionally bypassed). AppKit routes
    // a drag to this view anywhere over the window, including the transparent
    // stage margin, so every callback re-checks the island rect.

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        endDragInside()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isDragInside && !fileURLs(in: sender).isEmpty
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = fileURLs(in: sender)
        isDragInside = false
        guard !urls.isEmpty else { return false }
        return onDrop?(urls) ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        endDragInside()
    }

    private func updateDrag(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let over = region.contains(convert(sender.draggingLocation, from: nil))
        guard over, acceptsDrop?() ?? false, !fileURLs(in: sender).isEmpty else {
            endDragInside()
            return []
        }
        if !isDragInside {
            isDragInside = true
            onDragEntered?()
        }
        return .copy
    }

    private func endDragInside() {
        guard isDragInside else { return }
        isDragInside = false
        onDragExited?()
    }

    private func fileURLs(in sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}
