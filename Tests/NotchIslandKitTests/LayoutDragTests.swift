import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

/// A widget on the Customize editor's canvas, as the canvas draws it and tells the session what it
/// measured (`EditorCanvas`): drags driven here run the editor's own steps (`LayoutDrag`).
@MainActor final class CanvasHarness {
    let model = AppModel()
    let store: WidgetStore
    let session: EditorSession
    let probe = WidgetFrameProbe()
    let size: CGSize
    private let suite: String
    /// The picture last drawn, kept: gone, its views take what they measured with them.
    private var renderer: ImageRenderer<AnyView>?

    init(_ kind: IslandWidgetKind, _ width: Int, _ height: Int) {
        suite = "notchisland.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let rect = GridRect(column: 0, row: 0, width: width, height: height)
        let widget = IslandWidget(kind: kind, frame: rect, options: kind.defaultOptions, id: WidgetID())
        defaults.set(try? JSONEncoder().encode(WidgetBoard(widgets: [widget])), forKey: WidgetStore.key)
        store = WidgetStore(defaults: defaults)
        session = EditorSession(widget: widget.id, store: store)
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard)
        size = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(layout), grid: .standard).frame(for: rect).size
        model.media.injectDemo(NowPlayingItem(title: "Black & Blue", artist: "Bring Me The Horizon", album: "A", duration: 272,
                                              artworkData: nil, bundleIdentifier: "com.apple.Music"), playing: false)
        render()
    }

    deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }

    /// Drawn as the canvas draws it now (the draft too), and measured into the session.
    func render() {
        guard let widget = session.widget else { return }
        let shown = CanvasWidget.drawn(widget, frame: widget.frame, comparing: false, draft: session.layoutDraft)
        let view = IslandWidgetView(widget: shown, size: size, thumbnails: ThumbnailCache())
            .frame(width: size.width, height: size.height)
            .environment(model)
            .environment(\.widgetRenderMode, .canvas)
            .environment(\.widgetFrameProbe, probe)
            .environment(\.elementFitStore, session.fits)
            .environment(\.widgetReadsLive, true)
            .environment(\.widgetDate, WidgetSnapshotTests.date)
            .environment(\.colorScheme, .dark)
        // Twice: what fits reports in the first pass lays out the second.
        let renderer = ImageRenderer(content: AnyView(view))
        renderer.scale = 2
        _ = renderer.cgImage
        _ = renderer.cgImage
        self.renderer = renderer
        let padding = WidgetMetrics.padding(for: shown)
        let scale = model.layout.scale.factor
        let contentScale = CGFloat(shown.style.layout.contentScale ?? 1)
        let probe = probe, size = size
        session.canvasContext = CanvasContext(size: size, padding: padding, scale: scale, displayScale: 2) {
            probe.unlock(size: size, padding: padding, scale: scale, displayScale: 2, contentScale: contentScale)
        }
        session.measured(frames: probe.frames, drawn: probe.drawn, inks: probe.inks, size: size)
    }

    func frame(_ id: ElementID) -> CGRect? { session.elementFrame(id) }

    /// Moves `id` by `delta` and lets go; where the drag said it would land.
    @discardableResult
    func move(_ id: ElementID, by delta: CGSize, snapping: Bool = false) -> CGRect? {
        guard var drag = session.beginMoveDrag(id) else { return nil }
        session.moveDrag(&drag, by: delta, zoom: 1, snapping: snapping)
        render()
        let landed = drag.starts.count == 1 ? drag.landed : nil
        session.commitDraft()
        render()
        return landed
    }

    /// Drags `handle` of `id` by `delta` and lets go; where the drag said it would land.
    @discardableResult
    func resize(_ id: ElementID, _ handle: ResizeHandle, by delta: CGSize, snapping: Bool = false) -> CGRect? {
        guard var drag = session.beginResizeDrag(id, handle: handle) else { return nil }
        session.resizeDrag(&drag, id, by: delta, zoom: 1, keepsAspect: false, snapping: snapping)
        render()
        let landed = drag.landed
        session.commitDraft()
        render()
        return landed
    }
}

private func close(_ a: CGRect?, _ b: CGRect?, _ tolerance: CGFloat = 0.75) -> Bool {
    guard let a, let b else { return false }
    return abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
        && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
}

private func describe(_ rect: CGRect?) -> String {
    rect.map { String(format: "(%.2f, %.2f, %.2f × %.2f)", $0.minX, $0.minY, $0.width, $0.height) } ?? "nil"
}

/// Dragging and resizing a custom layout's elements on the canvas: every element lands where the
/// drag showed it, stays there once let go, comes back exactly when dragged back, and a side of a
/// button changes that side alone.
@MainActor @Suite(.serialized) struct LayoutDragTests {
    nonisolated static let cases: [(IslandWidgetKind, Int, Int)] = [
        (.nowPlaying, 7, 3), (.nowPlaying, 5, 2), (.timer, 5, 2), (.timer, 12, 3), (.stopwatch, 4, 2),
        (.batteryChart, 3, 1), (.batteryChart, 5, 2), (.uptime, 4, 2), (.network, 4, 2), (.worldClock, 4, 2),
    ]

    nonisolated static let names = cases.map { "\($0.0.rawValue)-\($0.1)x\($0.2)" }

    private func unlocked(_ name: String) throws -> CanvasHarness {
        let (kind, width, height) = try #require(Self.cases.first { "\($0.0.rawValue)-\($0.1)x\($0.2)" == name })
        let harness = CanvasHarness(kind, width, height)
        harness.session.setCustomLayout(true)
        harness.render()
        #expect(harness.session.layoutState.isCustom, "\(name): not unlocked")
        return harness
    }

    /// Unlocking draws every element where the stacks drew it (the frames the editor shows are
    /// where the widget draws them).
    @Test(arguments: names) func movedElementsLandWhereTheDragShowedAndComeBack(_ name: String) throws {
        let harness = try unlocked(name)
        let ids = harness.session.elementFrames.map(\.id)
        #expect(!ids.isEmpty, "\(name): nothing on the canvas")
        for id in ids {
            let before = harness.session.elementFrames
            guard let start = harness.frame(id) else { continue }
            let type = harness.session.drawn[id]
            let landed = harness.move(id, by: CGSize(width: 3, height: 2))
            let after = harness.frame(id)
            #expect(close(after, landed), "\(name) \(id.rawValue): landed \(describe(landed)), drawn \(describe(after))")
            // The others stay.
            for (other, frame) in before where other != id {
                #expect(close(harness.frame(other), frame), "\(name) \(other.rawValue) moved with \(id.rawValue): \(describe(frame)) → \(describe(harness.frame(other)))")
            }
            // Text keeps its size.
            if case .text(let was, _, _)? = type, case .text(let now, _, _)? = harness.session.drawn[id] {
                #expect(abs(was.points - now.points) < 0.05, "\(name) \(id.rawValue): \(was.points) pt → \(now.points) pt")
            }
            guard let moved = after else { continue }
            harness.move(id, by: CGSize(width: start.minX - moved.minX, height: start.minY - moved.minY))
            #expect(close(harness.frame(id), start), "\(name) \(id.rawValue): back at \(describe(harness.frame(id))), was \(describe(start))")
        }
    }

    /// Every element is drawn exactly where its resize showed it; a button's side changes that side
    /// alone; text made wider or narrower keeps its type; anything but text comes back when dragged back.
    @Test(arguments: names) func resizedElementsLandWhereTheDragShowedAndComeBack(_ name: String) throws {
        let harness = try unlocked(name)
        for id in harness.session.elementFrames.map(\.id) {
            for (handle, delta) in [(ResizeHandle.bottom, CGSize(width: 0, height: -3)), (.trailing, CGSize(width: -4, height: 0)),
                                    (.bottomTrailing, CGSize(width: -4, height: -3))] {
                guard let start = harness.frame(id) else { continue }
                let type = harness.session.textType(id)
                let landed = harness.resize(id, handle, by: delta)
                let after = harness.frame(id)
                #expect(close(after, landed), "\(name) \(id.rawValue) \(handle): landed \(describe(landed)), drawn \(describe(after))")
                if let type, handle == .trailing, let now = harness.session.textType(id) {
                    #expect(abs(now.points - type.points) < 0.05, "\(name) \(id.rawValue): \(type.points) pt → \(now.points) pt as it was made narrower")
                }
                // A button's side changes that side alone.
                if harness.session.widget?.kind.spec.filledButtons.contains(id) == true, let after, handle != .bottomTrailing {
                    if handle.vertical == 0 { #expect(abs(after.height - start.height) < 0.75, "\(name) \(id.rawValue): taller as it was made wider") }
                    if handle.horizontal == 0 { #expect(abs(after.width - start.width) < 0.75, "\(name) \(id.rawValue): wider as it was made taller") }
                }
                guard let resized = after, type == nil else { continue }
                // Back by the same handle.
                harness.resize(id, handle, by: CGSize(width: handle.horizontal == 0 ? 0 : start.maxX - resized.maxX,
                                                      height: handle.vertical == 0 ? 0 : start.maxY - resized.maxY))
                #expect(close(harness.frame(id), start, 1), "\(name) \(id.rawValue) \(handle): back at \(describe(harness.frame(id))), was \(describe(start))")
            }
        }
    }

    /// Text resized: wider, the same type and height; taller, more lines (or, not growing lines,
    /// larger type); kept in shape, its type scales with it. Its rectangle is always its lines' height.
    @Test func textIsResizedByLinesAndType() throws {
        let harness = try unlocked("nowPlaying-7x3")
        let id = ElementID.artist
        let session = harness.session
        let type = try #require(session.textType(id))
        let line = WidgetTypography.lineHeight(type)
        // Wider: only the width.
        let start = try #require(harness.frame(id))
        harness.resize(id, .trailing, by: CGSize(width: 20, height: 0))
        let wider = try #require(harness.frame(id))
        #expect(abs(wider.width - start.width - 20) < 0.75)
        #expect(abs(wider.height - TextFit.frameHeight(points: type.points, lines: 1, spec: type)) < 0.5)
        #expect(abs((session.textType(id)?.points ?? 0) - type.points) < 0.05)
        // Taller by a line: two lines, its type as it was, its top held.
        harness.resize(id, .bottom, by: CGSize(width: 0, height: line))
        let taller = try #require(harness.frame(id))
        #expect(session.textLines(id) == 2)
        #expect(abs(taller.height - TextFit.frameHeight(points: type.points, lines: 2, spec: type)) < 0.5)
        #expect(abs(taller.minY - wider.minY) < 0.5)
        #expect(abs((session.textType(id)?.points ?? 0) - type.points) < 0.05)
        // Not growing lines: taller makes larger type.
        session.editLayout { LayoutEdit.setGrowsLines(false, [id], in: &$0) }
        harness.render()
        harness.resize(id, .bottom, by: CGSize(width: 0, height: taller.height))
        let larger = try #require(session.textType(id))
        #expect(session.textLines(id) == 2 && larger.points > type.points * 1.6)
        // Kept in shape: a corner scales its type with it.
        session.editLayout { LayoutEdit.setKeepsAspect(true, [id], in: &$0) }
        harness.render()
        let before = try #require(harness.frame(id))
        harness.resize(id, .bottomTrailing, by: CGSize(width: before.width * 0.5, height: before.height * 0.5))
        let scaled = try #require(session.textType(id))
        #expect(abs(scaled.points / larger.points - 1.5) < 0.05, "\(larger.points) → \(scaled.points)")
        // Nothing holds it inside the widget.
        harness.resize(id, .bottomTrailing, by: CGSize(width: harness.size.width * 2, height: harness.size.height * 2))
        #expect((harness.frame(id)?.maxX ?? 0) > harness.size.width)
    }
}

/// Settings' Elements sizes (S, M, L) on a widget laid out freely: the element's rectangle grows or
/// shrinks about its middle, and comes back at M.
@MainActor @Suite(.serialized) struct CustomLayoutElementSizeTests {
    private func setSize(_ size: ElementSize, of id: ElementID, in harness: CanvasHarness) {
        guard let widgetID = harness.session.widget?.id else { return }
        harness.store.update(widgetID) { widget in
            let factor = Double(size.factor / widget.size(of: id).factor)
            LayoutEdit.scale(id, by: factor, in: &widget.style.layout.arrangement)
            widget.sizes[id] = size
        }
        harness.render()
    }

    @Test(arguments: ["batteryChart-5x2", "timer-12x3", "uptime-4x2"]) func aSizeScalesTheElementsRectangle(_ name: String) throws {
        let (kind, width, height) = try #require(LayoutDragTests.cases.first { "\($0.0.rawValue)-\($0.1)x\($0.2)" == name })
        let harness = CanvasHarness(kind, width, height)
        harness.session.setCustomLayout(true)
        harness.render()
        let sizable = kind.spec.elements.filter(\.isSizable).map(\.id)
        let id = try #require(harness.session.drawnLayout?.items.map(\.id).first { sizable.contains($0) }, "\(name): nothing sizable placed")
        let item = { harness.session.drawnLayout?.items.first { $0.id == id }?.rect }
        let start = try #require(item())
        let drawn = try #require(harness.frame(id))
        setSize(.small, of: id, in: harness)
        let small = try #require(item())
        let drawnSmall = try #require(harness.frame(id))
        #expect(drawnSmall.width < drawn.width - 1 || drawnSmall.height < drawn.height - 1,
                "\(name) \(id.rawValue): drawn \(drawn) → \(drawnSmall)")
        #expect(abs(small.width - start.width * 0.8) < 0.001 || small.width < start.width, "\(name) \(id.rawValue): \(start) → \(small)")
        #expect(abs((small.x + small.width / 2) - (start.x + start.width / 2)) < 0.001, "\(name): not about its middle")
        setSize(.medium, of: id, in: harness)
        let back = try #require(item())
        #expect(abs(back.width - start.width) < 0.001 && abs(back.height - start.height) < 0.001 && abs(back.x - start.x) < 0.001,
                "\(name) \(id.rawValue): back at \(back), was \(start)")
        let drawnBack = try #require(harness.frame(id))
        #expect(abs(drawnBack.width - drawn.width) < 1 && abs(drawnBack.height - drawn.height) < 1,
                "\(name) \(id.rawValue): drawn back at \(drawnBack), was \(drawn)")
    }
}
