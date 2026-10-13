import AppKit
import QuartzCore
import SwiftUI

/// A place in the island's SwiftUI content, found again as a layer.
///
/// SwiftUI draws the island's content as one flat list of layers, an item each (a text, a plate, a
/// glass button), in drawing order inside one container layer: no layer stands for a page or a
/// pill. Two marks — an empty view before a piece of content and one after it — bound that
/// piece's stretch of the list (`LeafLayers.between`), so the render server can be told to move or
/// fade exactly those items.
struct LayerMark: NSViewRepresentable {
    enum Slot: Hashable, Sendable { case pagesBegin, pagesEnd, panelBegin, panelEnd, contentBegin, contentEnd }
    let slot: Slot

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        LeafLayers.marks[slot] = Weak(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if LeafLayers.marks[slot]?.view !== view { LeafLayers.marks[slot] = Weak(view) }
    }

    final class Weak {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }
}

extension View {
    /// `first` drawn before this view's content and `last` after it: its stretch of the island's layers.
    func layerMarks(_ first: LayerMark.Slot, _ last: LayerMark.Slot) -> some View {
        background(alignment: .topLeading) { LayerMark(slot: first).frame(width: 1, height: 1).allowsHitTesting(false) }
            .overlay(alignment: .topLeading) { LayerMark(slot: last).frame(width: 1, height: 1).allowsHitTesting(false) }
    }
}

@MainActor enum LeafLayers {
    static var marks: [LayerMark.Slot: LayerMark.Weak] = [:]

    /// The item layers SwiftUI drew between two marks, in drawing order (the marks' own left out);
    /// nil when the marks are not both in a window or not in one list.
    static func between(_ first: LayerMark.Slot, _ last: LayerMark.Slot) -> [CALayer]? {
        guard let a = marks[first]?.view, let b = marks[last]?.view, a.window != nil, a.window === b.window,
              let start = a.layer, let end = b.layer else { return nil }
        // The lowest layer both marks are under holds the list; each mark's branch of it is an item.
        var ancestors: [CALayer] = []
        var layer: CALayer? = start
        while let current = layer {
            ancestors.append(current)
            layer = current.superlayer
        }
        var branch = end
        while let parent = branch.superlayer {
            if let index = ancestors.firstIndex(where: { $0 === parent }) {
                guard index > 0, let items = parent.sublayers,
                      let from = items.firstIndex(where: { $0 === ancestors[index - 1] }),
                      let to = items.firstIndex(where: { $0 === branch }), from < to else { return nil }
                return Array(items[(from + 1)..<to])
            }
            branch = parent
        }
        return nil
    }
}

/// The panel's page switch, moved by the render server.
///
/// A switch shows one page and hides another: SwiftUI sets the opacity of each of their items and
/// moves the incoming page's from its side into place. Animated by SwiftUI those were ~100 turns
/// of the main thread for six switches (83–98 ms a switch, measured), and a main thread busy with
/// anything else held the slide still. Here SwiftUI makes the change at once, and each item's own
/// layer carries it, on the same curve for the same time: an animation from where the item was to
/// wherever SwiftUI has put it (no end value: Core Animation takes the layer's own). The items,
/// their order and what takes a click are SwiftUI's as before — only who draws the frames in
/// between has changed.
///
/// In two steps, as SwiftUI's own animation went. A page draws some of its items only once it is
/// shown (the battery's charts: 60–80 ms of the main thread, over two or three updates), and
/// SwiftUI's animation, driven by that same thread, stood still meanwhile. So until the shown page
/// has stopped getting items every item is held as it was (`hold`): the old page whole, the new
/// one unseen. Then all of them start together (`start`). An item that comes later still joins
/// where the others have got to.
@MainActor final class PanelPageMotion {
    static let shared = PanelPageMotion()
    static let key = "ni.pageSwitch"
    /// The longest the items are held waiting for SwiftUI's update.
    static let patience: TimeInterval = 0.15

    private struct Flight {
        let id: Int
        let duration: CFTimeInterval
        let timing: CAMediaTimingFunction
        /// How far from its place the incoming page waits, sideways.
        let glide: CGFloat
        /// The items there when the switch began: how each looked and where it stood.
        var before: [ObjectIdentifier: (opacity: Float, position: CGPoint, glides: Bool)]
        /// Items that came with SwiftUI's update, held unseen until the start.
        var arrived: Set<ObjectIdentifier> = []
        /// SwiftUI has updated the pages at least once.
        var isUpdated = false
        /// When the items started moving; nil while they are held.
        var started: CFTimeInterval?
    }

    private var flight: Flight?
    private var nextID = 0
    private var settling: Timer?
    /// How long after the last update that brought the shown page items the motion starts: a
    /// frame, in which a further update would have begun.
    static let settle: TimeInterval = 0.012

    /// Holds the pages' items as they are now, to start the switch's motion once SwiftUI has made
    /// the change; false when they cannot be found (SwiftUI then animates the switch itself, as it
    /// did). Call before the page changes. `glide`: where the incoming page waits, in points to
    /// the right of its place.
    ///
    /// No transaction of its own here or below: committed from inside SwiftUI's update, one sent
    /// what was drawn so far to the screen at once.
    func begin(duration: CFTimeInterval, timing: CAMediaTimingFunction, glide: CGFloat) -> Bool {
        guard let items = LeafLayers.between(.pagesBegin, .pagesEnd), !items.isEmpty else { return false }
        nextID += 1
        var flight = Flight(id: nextID, duration: duration, timing: timing, glide: glide, before: [:])
        for item in items {
            // Where a switch still under way has the item now.
            let isMoving = item.animation(forKey: Self.key) != nil
            let shown = isMoving ? item.presentation() ?? item : item
            let state = (opacity: shown.opacity, position: shown.position, glides: item.opacity == 0 || isMoving)
            flight.before[ObjectIdentifier(item)] = state
            hold(item, opacity: state.opacity, position: state.glides ? state.position : nil)
        }
        self.flight = flight
        if PerfTrace.isOn { PerfTrace.mark("page motion: \(items.count) items held") }
        // Should SwiftUI's update not come: the items go on from where they are. (While the page's
        // items are still coming, `settle` decides — up to `patience` three times over.)
        let id = flight.id
        for (delay, always) in [(Self.patience, false), (Self.patience * 3, true)] {
            let timer = Timer(timeInterval: delay, repeats: false) { _ in
                MainActor.assumeIsolated {
                    if always || PanelPageMotion.shared.settling == nil { PanelPageMotion.shared.start(id) }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        return true
    }

    /// The item drawn as given whatever its layer is set to meanwhile.
    private func hold(_ item: CALayer, opacity: Float, position: CGPoint?) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        fade.toValue = opacity
        var animations: [CAAnimation] = [fade]
        if let position {
            let place = CABasicAnimation(keyPath: "position")
            place.fromValue = NSValue(point: position)
            place.toValue = NSValue(point: position)
            animations.append(place)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = Self.patience * 3 + 1
        item.add(group, forKey: Self.key)
    }

    /// After each of SwiftUI's updates while a switch runs (`IslandHostingView.layout`): the shown
    /// page's new items are held unseen until the start, or, after it, start where the others are.
    func follow() {
        guard var flight else { return }
        if let started = flight.started, CACurrentMediaTime() >= started + flight.duration {
            self.flight = nil
            return
        }
        guard let items = LeafLayers.between(.pagesBegin, .pagesEnd) else { return }
        var arrivals = 0
        for item in items {
            let id = ObjectIdentifier(item)
            guard flight.before[id] == nil, !flight.arrived.contains(id) else { continue }
            flight.arrived.insert(id)
            // Only the shown page's: a hidden page's new items are not seen.
            guard item.opacity > 0 else { continue }
            arrivals += 1
            if let started = flight.started {
                item.add(motion(from: 0, position: CGPoint(x: item.position.x + flight.glide, y: item.position.y),
                                flight: flight, beginTime: item.convertTime(started, from: nil)), forKey: Self.key)
            } else {
                hold(item, opacity: 0, position: nil)
            }
        }
        // The start waits for the shown page to finish drawing: `settle` after the last update that
        // brought it items (the charts come an update or two after the labels), `patience` at most.
        if flight.started == nil, arrivals > 0 || !flight.isUpdated {
            flight.isUpdated = true
            let id = flight.id
            settling?.invalidate()
            let timer = Timer(timeInterval: Self.settle, repeats: false) { _ in
                MainActor.assumeIsolated { PanelPageMotion.shared.start(id) }
            }
            RunLoop.main.add(timer, forMode: .common)
            settling = timer
        }
        self.flight = flight
    }

    /// Every held item starts from how it was held towards what SwiftUI has made of it.
    private func start(_ id: Int) {
        guard var flight, flight.id == id, flight.started == nil else { return }
        settling?.invalidate()
        settling = nil
        flight.started = CACurrentMediaTime()
        self.flight = flight
        guard let items = LeafLayers.between(.pagesBegin, .pagesEnd) else { return }
        var moved = 0
        for item in items {
            let id = ObjectIdentifier(item)
            if let before = flight.before[id] {
                item.add(motion(from: before.opacity, position: before.glides ? before.position : nil, flight: flight, beginTime: 0),
                         forKey: Self.key)
            } else if flight.arrived.contains(id), item.opacity > 0 {
                item.add(motion(from: 0, position: CGPoint(x: item.position.x + flight.glide, y: item.position.y),
                                flight: flight, beginTime: 0), forKey: Self.key)
            } else {
                continue
            }
            moved += 1
        }
        if PerfTrace.isOn { PerfTrace.mark("page motion: \(moved) items start") }
    }

    /// From the given opacity and place to the layer's own.
    private func motion(from opacity: Float, position: CGPoint?, flight: Flight, beginTime: CFTimeInterval) -> CAAnimationGroup {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        var animations: [CAAnimation] = [fade]
        if let position {
            let glide = CABasicAnimation(keyPath: "position")
            glide.fromValue = NSValue(point: position)
            animations.append(glide)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = flight.duration
        group.timingFunction = flight.timing
        group.beginTime = beginTime
        return group
    }
}

/// The island's content swap — a pill into the panel, a banner over a pill, the panel back into its
/// pill — faded by the render server.
///
/// Where the swap is a plain cross-fade (on battery, in Low Power Mode, into and out of Siri:
/// `IslandRootView`), SwiftUI faded the content that left and the content that came frame by
/// frame for 0.1–0.18 s: about half the main thread's work of a hover's opening and closing
/// (~40 updates of the island, measured). Here SwiftUI makes the swap at once, keeping what leaves
/// in place, unseen, for as long as the fade takes (`IslandModel.contentSwap`), and the items' own
/// layers fade from how they were drawn to what SwiftUI has made of them, each as SwiftUI faded it: what leaves to nothing, what comes from nothing, the panel's
/// kept page out in a tenth of a second. The panel coming in is simply there where its page was
/// kept or built ahead, and fades in with the rest where this swap builds it — both as before.
@MainActor final class ContentSwapMotion {
    static let shared = ContentSwapMotion()
    static let key = "ni.contentSwap"
    /// How long the panel's kept page takes to leave, whatever the swap's own length (`IslandContentStack`).
    static let panelFade: CFTimeInterval = 0.1

    private struct Flight {
        let id: Int
        let duration: CFTimeInterval
        /// The content's items when the swap began, each with the opacity it was drawn at.
        let content: [ObjectIdentifier: Float]
        /// The panel's items seen when it began, with their opacity.
        let panel: [ObjectIdentifier: Float]
        /// The panel's page was not there at all when it began (not kept from an earlier opening,
        /// not built ahead in the hover's delay): it is put in by this swap, and fades in with it
        /// as what SwiftUI puts in did.
        let panelIsNew: Bool
        var arrived: Set<ObjectIdentifier> = []
        /// When SwiftUI's update of the swap went to the render server; nil until then.
        var started: CFTimeInterval?
    }

    private var flight: Flight?
    private var nextID = 0

    /// Notes what is shown now, to fade it out and the new content in once SwiftUI has made the
    /// swap; false when the island's items cannot be found (SwiftUI animates the swap itself
    /// then). Call before the presentation changes.
    func begin(duration: CFTimeInterval) -> Bool {
        guard let content = LeafLayers.between(.contentBegin, .contentEnd),
              let panel = LeafLayers.between(.panelBegin, .panelEnd) ?? Optional([]) else { return false }
        nextID += 1
        flight = Flight(id: nextID, duration: duration,
                        content: Dictionary(content.map { (ObjectIdentifier($0), ($0.presentation() ?? $0).opacity) },
                                            uniquingKeysWith: { first, _ in first }),
                        panel: Dictionary(panel.filter { $0.opacity > 0 }.map { (ObjectIdentifier($0), ($0.presentation() ?? $0).opacity) },
                                          uniquingKeysWith: { first, _ in first }),
                        panelIsNew: panel.isEmpty)
        // Should SwiftUI's update not come, nothing is left waiting.
        let id = nextID
        let timer = Timer(timeInterval: 0.3, repeats: false) { _ in
            MainActor.assumeIsolated {
                if ContentSwapMotion.shared.flight?.id == id, ContentSwapMotion.shared.flight?.started == nil {
                    ContentSwapMotion.shared.flight = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    /// After each of SwiftUI's updates (`IslandHostingView.layout`): at the first one of a swap its
    /// fades start, with that update's own frame; what comes later joins where they are.
    func follow() {
        guard var flight else { return }
        if let started = flight.started, CACurrentMediaTime() >= started + flight.duration {
            self.flight = nil
            return
        }
        let timing = CAMediaTimingFunction(name: .easeOut)
        let isFirst = flight.started == nil
        for item in LeafLayers.between(.contentBegin, .contentEnd) ?? [] {
            let id = ObjectIdentifier(item)
            let fade = CABasicAnimation(keyPath: "opacity")
            if let shown = flight.content[id] {
                // There before: what leaves is kept by SwiftUI, unseen, until the fade is over
                // (`IslandModel.contentSwap`); what was leaving and is shown again comes back.
                guard isFirst, item.opacity != shown else { continue }
                fade.fromValue = shown
            } else {
                guard !flight.arrived.contains(id) else { continue }
                flight.arrived.insert(id)
                guard item.opacity > 0 else { continue }
                fade.fromValue = 0
                if let started = flight.started { fade.beginTime = item.convertTime(started, from: nil) }
            }
            fade.duration = flight.duration
            fade.timingFunction = timing
            item.add(fade, forKey: Self.key)
        }
        for item in LeafLayers.between(.panelBegin, .panelEnd) ?? [] {
            let id = ObjectIdentifier(item)
            if let shown = flight.panel[id] {
                // The panel's page hidden by this swap (kept for the next opening).
                guard isFirst, item.opacity == 0 else { continue }
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = shown
                fade.duration = Self.panelFade
                fade.timingFunction = timing
                item.add(fade, forKey: Self.key)
            } else if flight.panelIsNew, !flight.arrived.contains(id) {
                flight.arrived.insert(id)
                guard item.opacity > 0 else { continue }
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.duration = flight.duration
                fade.timingFunction = timing
                if let started = flight.started { fade.beginTime = item.convertTime(started, from: nil) }
                item.add(fade, forKey: Self.key)
            }
        }
        if isFirst { flight.started = CACurrentMediaTime() }
        self.flight = flight
    }
}
