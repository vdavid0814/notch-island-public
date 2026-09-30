import CoreGraphics
import Foundation

// Window Anchor: another app's window held under the notch. Everything here is in the global
// coordinates Accessibility and the window server use (points, the origin at the top-left of the
// primary display, y down), and pure: the numbers are testable without a window.

/// The notch screen as the anchor sees it.
nonisolated struct AnchorScreen: Sendable, Equatable {
    /// The whole screen.
    var frame: CGRect
    /// The menu bar's height: a window's top edge cannot go above `frame.minY + band` (the window
    /// server puts it back below the bar, in every app measured).
    var band: CGFloat
    var notch: CGSize

    /// The band's bottom edge.
    var bandBottom: CGFloat { frame.minY + band }
}

/// The size anchored windows are given, set in Settings: automatic (the screen's own,
/// `AnchorGeometry.defaultSize`), a size picked by name (it follows the screen), or one set by hand.
nonisolated struct AnchorSizePreference: Codable, Sendable, Equatable {
    var width: Double?
    var height: Double?
    /// Picked by name; nil: automatic, or the width and height set by hand.
    var preset: AnchorSizePreset?

    init(width: Double? = nil, height: Double? = nil, preset: AnchorSizePreset? = nil) {
        self.width = width
        self.height = height
        self.preset = preset
    }

    static let widthRange: ClosedRange<Double> = 240...1600
    static let heightRange: ClosedRange<Double> = 160...1200

    var isAutomatic: Bool { choice == .automatic }

    /// What Settings shows as picked.
    var choice: AnchorSizePreset {
        if let preset, preset != .custom { return preset }
        return width == nil && height == nil ? .automatic : .custom
    }

    /// On `screen`: the set size, clamped to what the screen leaves under the menu bar.
    func size(on screen: AnchorScreen) -> CGSize {
        if let preset, let size = preset.size(on: screen) { return size }
        let standard = AnchorGeometry.defaultSize(screen)
        let width = min(CGFloat(width ?? Double(standard.width)), screen.frame.width)
        let height = min(CGFloat(height ?? Double(standard.height)), Self.maximumHeight(on: screen))
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    /// The width and height that can be set on `screen`.
    static func widths(on screen: AnchorScreen) -> ClosedRange<CGFloat> {
        CGFloat(widthRange.lowerBound)...max(CGFloat(widthRange.lowerBound), min(CGFloat(widthRange.upperBound), screen.frame.width))
    }

    static func heights(on screen: AnchorScreen) -> ClosedRange<CGFloat> {
        CGFloat(heightRange.lowerBound)...max(CGFloat(heightRange.lowerBound), min(CGFloat(heightRange.upperBound), maximumHeight(on: screen)))
    }

    private static func maximumHeight(on screen: AnchorScreen) -> CGFloat { screen.frame.height - screen.band * 2 }
}

/// The sizes Settings offers by name, as parts of the screen.
nonisolated enum AnchorSizePreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case automatic, small, medium, large, tall, wide, custom

    var id: Self { self }

    /// Width and height as parts of the screen's (nil: automatic, custom).
    var fractions: (width: CGFloat, height: CGFloat)? {
        switch self {
        case .automatic, .custom: nil
        case .small: (0.36, 0.36)
        case .medium: (0.5, 0.55)
        case .large: (0.62, 0.68)
        case .tall: (0.42, 0.82)
        case .wide: (0.8, 0.5)
        }
    }

    func size(on screen: AnchorScreen) -> CGSize? {
        guard let fractions else { return nil }
        let widths = AnchorSizePreference.widths(on: screen), heights = AnchorSizePreference.heights(on: screen)
        return CGSize(width: min(max((screen.frame.width * fractions.width).rounded(), widths.lowerBound), widths.upperBound),
                      height: min(max((screen.frame.height * fractions.height).rounded(), heights.lowerBound), heights.upperBound))
    }
}

/// Where the stage shows the app's name and Release: beside the notch in the menu bar, or under the window.
nonisolated enum AnchorBarPlacement: String, Codable, Sendable, CaseIterable, Identifiable {
    case menuBar, belowWindow

    var id: Self { self }
}

/// The live copy's window at the top of the screen (`AnchorMirror`): the window's picture from the
/// screen's top edge down, on an island-black stage with the island's shoulders at the top and a
/// chin under it (as tall as the menu bar: the real window, a menu bar lower, ends there).
nonisolated struct AnchorStageLayout: Sendable, Equatable {
    /// The stage, in global coordinates (y down).
    var frame: CGRect
    /// The window's picture in the stage (top-left origin).
    var copy: CGRect
    /// The bar under it.
    var chin: CGRect
    var shoulder: CGFloat
    var bottomRadius: CGFloat
    /// How far below the picture the real window is (the menu bar): a click is sent this much lower.
    var offset: CGFloat

    static let shoulder: CGFloat = 10
    static let bottomRadius: CGFloat = 22

    init(screen: AnchorScreen, rest: CGRect) {
        shoulder = Self.shoulder
        bottomRadius = Self.bottomRadius
        offset = rest.minY - screen.frame.minY
        let chinHeight = max(offset, 24)
        frame = CGRect(x: rest.minX - shoulder, y: screen.frame.minY, width: rest.width + 2 * shoulder,
                       height: rest.height + chinHeight)
        copy = CGRect(x: shoulder, y: 0, width: rest.width, height: rest.height)
        chin = CGRect(x: shoulder, y: rest.height, width: rest.width, height: chinHeight)
    }

    /// A point on the picture (global) where the real window has it.
    func forwarded(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: point.y + offset) }

    /// A point on the picture (global) in the real window's own coordinates (top-left origin).
    func inWindow(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - frame.minX - copy.minX, y: point.y - frame.minY - copy.minY) }

    /// The picture in global coordinates.
    var copyInScreen: CGRect { copy.offsetBy(dx: frame.minX, dy: frame.minY) }

    /// The least of another window of the app over the stage that makes it step aside: a sheet or a
    /// dialog, not a tooltip, a tab's drag image or a toolbar helper (those are seen through it).
    static let overlaySize = CGSize(width: 120, height: 60)

    /// Another window of the app, in front of the held one, covers enough of the stage to be used.
    func isOverlaid(by window: CGRect) -> Bool {
        let common = window.intersection(frame)
        return !common.isNull && common.width >= Self.overlaySize.width && common.height >= Self.overlaySize.height
    }
}

nonisolated enum AnchorGeometry {
    /// Between the band and a window at rest: none, the window right under the menu bar (the live
    /// copy takes it up to the screen's top).
    static let gap: CGFloat = 0
    /// How far beside the notch, and how far below the band, a dragged window's pointer lands it.
    static let zoneReach: CGFloat = 140
    static let zoneDepth: CGFloat = 110
    /// Dropped farther than this from its rest, an anchored window is let go.
    static let releaseDistance: CGFloat = 120

    /// Where the pointer must let a dragged window go: around the notch and below the band (not in
    /// it: the top edge is where macOS tiles a window).
    static func dropZone(_ screen: AnchorScreen) -> CGRect {
        let half = screen.notch.width / 2 + zoneReach
        return CGRect(x: screen.frame.midX - half, y: screen.bandBottom, width: half * 2, height: zoneDepth)
    }

    /// A window's size when the app has none remembered: near half the screen, within what reads
    /// as a window under the notch.
    static func defaultSize(_ screen: AnchorScreen) -> CGSize {
        CGSize(width: min(max((screen.frame.width * 0.46).rounded(), 620), 980),
               height: min(max((screen.frame.height * 0.52).rounded(), 400), 680))
    }

    /// The most a window's top may be raised from its rest: up to the screen's top, and no more
    /// than the app (or the window server) was seen to accept.
    static func maximumTuck(_ screen: AnchorScreen, limit: CGFloat?) -> CGFloat {
        max(0, min(gap + screen.notch.height, limit ?? .greatestFiniteMagnitude))
    }

    /// The frame a window of `size` rests in: centred under the notch, its top the gap below the
    /// band, raised by `tuck`. Never wider or taller than the screen leaves.
    static func restFrame(_ screen: AnchorScreen, size: CGSize, tuck: CGFloat = 0, tuckLimit: CGFloat? = nil) -> CGRect {
        let tuck = min(max(tuck, 0), maximumTuck(screen, limit: tuckLimit))
        let top = screen.bandBottom + gap - tuck
        let width = min(size.width, screen.frame.width)
        let height = min(size.height, screen.frame.maxY - top)
        return CGRect(x: (screen.frame.midX - width / 2).rounded(), y: top.rounded(), width: width.rounded(), height: height.rounded())
    }

    /// What was asked for and what the app gave: the accepted size centred again, and the tuck the
    /// window really got (a top that came back lower than asked is the limit).
    static func adopted(_ screen: AnchorScreen, asked: CGRect, got: CGRect) -> (frame: CGRect, tuck: CGFloat, tuckLimit: CGFloat?) {
        let rest = screen.bandBottom + gap
        let tuck = max(0, rest - got.minY)
        let refused = got.minY > asked.minY + 0.5
        let frame = CGRect(x: (screen.frame.midX - got.width / 2).rounded(), y: got.minY, width: got.width, height: got.height)
        return (frame, tuck, refused ? tuck : nil)
    }

    /// An anchored window let go of at `frame`: away from its rest by more than the release distance.
    static func isReleased(_ frame: CGRect, rest: CGRect) -> Bool {
        hypot(frame.minX - rest.minX, frame.minY - rest.minY) > releaseDistance
    }

    /// A resize that fills the screen (zoom, Fill, a tile): the window is the user's again.
    static func fillsScreen(_ size: CGSize, screen: AnchorScreen) -> Bool {
        size.width >= screen.frame.width * 0.9 && size.height >= (screen.frame.height - screen.band) * 0.9
    }

    /// The tuck a user's resize asks for: how far the top edge went above its rest.
    static func tuck(afterResizeTo frame: CGRect, screen: AnchorScreen, limit: CGFloat?) -> CGFloat {
        min(max(0, screen.bandBottom + gap - frame.minY), maximumTuck(screen, limit: limit))
    }
}

/// What is remembered per app: the size its window was given under the notch, and how far up it goes.
nonisolated struct AnchorMemory: Codable, Sendable, Equatable {
    nonisolated struct Entry: Codable, Sendable, Equatable {
        var width: Double
        var height: Double
        var tuck: Double = 0
        /// The highest tuck the app accepted; nil until one was refused.
        var tuckLimit: Double?

        var size: CGSize { CGSize(width: width, height: height) }
    }

    static let key = "ni2.anchor.memory"
    /// As many apps as anyone anchors; the oldest are dropped past it.
    static let capacity = 40

    private(set) var entries: [String: Entry] = [:]
    /// Bundle ids, the most recent last.
    private(set) var order: [String] = []

    init() {}

    subscript(bundleID: String) -> Entry? { entries[bundleID] }

    mutating func remember(_ entry: Entry, for bundleID: String) {
        entries[bundleID] = entry
        order.removeAll { $0 == bundleID }
        order.append(bundleID)
        while order.count > Self.capacity { entries[order.removeFirst()] = nil }
    }

    static func load(from defaults: UserDefaults = .standard) -> AnchorMemory {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(AnchorMemory.self, from: $0) } ?? AnchorMemory()
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// Whether a press became a window drag, decided from where the window under the pointer was at
/// the press and where it is a moment into the movement. Free of AppKit, so it can be tested.
nonisolated struct WindowDragLatch: Sendable, Equatable {
    /// When the window is looked at, measured from the gesture's first drag event: a window follows
    /// the pointer within a frame or two; by the second look one that has not moved is not dragged.
    static let looks: [TimeInterval] = [0.1, 0.25]
    /// Moved at least this far, the window is being dragged (a resize moves an edge, not the origin
    /// with the size kept; a title-bar drag keeps the size).
    static let moved: CGFloat = 3

    nonisolated enum Phase: Sendable, Equatable {
        case idle
        /// Button down over a window, no movement yet.
        case pressed
        /// Moving since `since`; `looks` looks taken.
        case watching(since: TimeInterval, looks: Int)
        /// The window follows the pointer.
        case dragging
        /// Not a window drag: nothing more is looked at until the next press.
        case ignored
    }

    private(set) var phase: Phase = .idle

    var isUndecided: Bool {
        switch phase {
        case .pressed, .watching: true
        case .idle, .dragging, .ignored: false
        }
    }

    var isDragging: Bool { phase == .dragging }

    /// A press: watched only when it is over another app's window.
    mutating func mouseDown(overWindow: Bool) {
        phase = overWindow ? .pressed : .ignored
    }

    /// A drag event: true when the window should be looked at now.
    mutating func mouseDragged(at time: TimeInterval) -> Bool {
        switch phase {
        case .pressed:
            phase = .watching(since: time, looks: 0)
            return false
        case .watching(let since, let looks):
            guard looks < Self.looks.count, time - since >= Self.looks[looks] else { return false }
            phase = .watching(since: since, looks: looks + 1)
            return true
        case .idle, .dragging, .ignored:
            return false
        }
    }

    /// What a look found: the window's frame at the press and now.
    mutating func looked(atPress: CGRect, now: CGRect) {
        guard case .watching(_, let looks) = phase else { return }
        let movedFar = abs(now.minX - atPress.minX) >= Self.moved || abs(now.minY - atPress.minY) >= Self.moved
        let keptSize = abs(now.width - atPress.width) < 1 && abs(now.height - atPress.height) < 1
        if movedFar && keptSize {
            phase = .dragging
        } else if looks >= Self.looks.count || (movedFar && !keptSize) {
            phase = .ignored
        }
    }

    /// The look could not be taken (the window is gone).
    mutating func lookFailed() {
        if case .watching = phase { phase = .ignored }
    }

    /// Ends the gesture: true when a window was being dragged.
    mutating func mouseUp() -> Bool {
        defer { phase = .idle }
        return phase == .dragging
    }
}

/// Whether other windows lie over the anchored one, with a hysteresis so an edge grazing it does
/// not flip the answer back and forth.
nonisolated struct CoverState: Sendable, Equatable {
    static let coveredAbove = 0.04
    static let uncoveredBelow = 0.01

    private(set) var isCovered = false

    /// Takes the share of the window's area under other windows; true when the answer changed.
    mutating func update(share: Double) -> Bool {
        let next = isCovered ? share >= Self.uncoveredBelow : share > Self.coveredAbove
        defer { isCovered = next }
        return next != isCovered
    }

    mutating func reset() { isCovered = false }

    /// The share of `window` under `above` (the windows in front of it): exact for rectangles that
    /// may overlap each other, by sweeping the distinct edges.
    static func share(of window: CGRect, under above: [CGRect]) -> Double {
        guard window.width > 0, window.height > 0 else { return 0 }
        let parts = above.map { $0.intersection(window) }.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
        guard !parts.isEmpty else { return 0 }
        let xs = Array(Set(parts.flatMap { [$0.minX, $0.maxX] })).sorted()
        var covered: CGFloat = 0
        for (left, right) in zip(xs, xs.dropFirst()) {
            let spans = parts.filter { $0.minX <= left && $0.maxX >= right }.map { ($0.minY, $0.maxY) }.sorted { $0.0 < $1.0 }
            var height: CGFloat = 0
            var end = -CGFloat.greatestFiniteMagnitude
            for (top, bottom) in spans {
                if top > end { height += bottom - top; end = bottom } else if bottom > end { height += bottom - end; end = bottom }
            }
            covered += height * (right - left)
        }
        return Double(covered / (window.width * window.height))
    }
}
