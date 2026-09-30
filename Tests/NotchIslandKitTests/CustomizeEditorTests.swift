import AppKit
import Foundation
import QuartzCore
import Testing
@testable import NotchIslandKit

/// Where the Customize editor's panes are and where the widget lands on its canvas: what the
/// transition flies the widget into before the editor exists.
@MainActor @Suite struct HeroGeometryTests {
    private let placement = SettingsPlacement(outerRadius: 24, leading: 12, gap: 10)
    /// This Mac's notch among the cases.
    private let notches = [CGSize(width: 156, height: 29), CGSize(width: 185, height: 32)]

    @Test func thePanesFillThePageAreaWithoutOverlapping() {
        for size in [CGSize(width: 820, height: 560), CGSize(width: 1000, height: 640), CGSize(width: 1220, height: 760)] {
            let layout = CustomizeLayout(size: size, placement: placement)
            #expect(layout.isNarrow == (size.width < 1000))
            #expect(layout.outline.width == (layout.isNarrow ? 180 : SettingsPlacement.sidebarWidth))
            #expect(layout.inspector.width == (layout.isNarrow ? InspectorLayout.narrowWidth : InspectorLayout.width))
            // The outline where the sidebar floats, the inspector as far from the other side.
            #expect(layout.outline.minX == placement.leading)
            #expect(layout.inspector.maxX == size.width - placement.leading)
            #expect(layout.outline.maxY == size.height - placement.gap)
            #expect(layout.outline.maxX + CustomizeLayout.gap == layout.canvasPane.minX)
            #expect(layout.canvasPane.maxX + CustomizeLayout.gap == layout.inspector.minX)
            #expect(layout.canvasPane.width >= 300)
            #expect(layout.canvasArea.minY == layout.canvasPane.minY + CustomizeLayout.toolbarHeight)
            #expect(layout.canvasArea.maxY == layout.canvasPane.maxY)
        }
    }

    @Test func theWidgetLandsWholeCentredAndOnWholePoints() {
        for notch in notches {
            for scale in IslandScale.allCases {
                let layout = IslandLayout(notch: notch, scale: scale)
                for area in [CGSize(width: 300, height: 450), CGSize(width: 640, height: 600)] {
                    for kind in IslandWidgetKind.allCases where kind.spec.isImplemented {
                        for size in kind.sizePresets {
                            let widget = IslandWidget(kind: kind, frame: GridRect(column: 0, row: 0, width: size.width, height: size.height),
                                                      options: kind.defaultOptions)
                            let geometry = CanvasGeometry(area: area, widget: widget, canvasSize: .onIsland, layout: layout, grid: .standard)
                            #expect(geometry.zoom <= CanvasGeometry.maximumZoom)
                            #expect(geometry.zoom >= 0.5)
                            let scaled = geometry.scaledWidget
                            #expect(scaled.minX == scaled.minX.rounded() && scaled.minY == scaled.minY.rounded())
                            #expect(scaled.width == scaled.width.rounded() && scaled.height == scaled.height.rounded())
                            #expect(abs(scaled.midX - area.width / 2) <= 0.5)
                            #expect(abs(scaled.midY - area.height / 2) <= 0.5)
                            // Inside the canvas whenever the magnification was free to fit it.
                            if geometry.zoom > 0.5 {
                                #expect(CGRect(origin: .zero, size: area).contains(geometry.slab))
                            }
                            #expect(geometry.slabRadius == WidgetMetrics.cornerRadius * geometry.zoom + 16)
                        }
                    }
                }
            }
        }
    }

    @Test func aPointOfTheCanvasAndARectOfTheWidgetConvertBothWays() {
        let layout = IslandLayout(notch: notches[0], scale: .standard)
        let widget = IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3), options: IslandWidgetKind.nowPlaying.defaultOptions)
        let geometry = CanvasGeometry(area: CGSize(width: 700, height: 600), widget: widget, canvasSize: .onIsland, layout: layout, grid: .standard)
        let rect = CGRect(x: 12, y: 8, width: 60, height: 20)
        let onCanvas = geometry.canvasRect(rect)
        #expect(onCanvas.width == rect.width * geometry.zoom)
        let back = geometry.widgetPoint(CGPoint(x: onCanvas.minX, y: onCanvas.minY))
        #expect(abs(back.x - rect.minX) < 1e-9 && abs(back.y - rect.minY) < 1e-9)
    }

    @Test func aPresetIsLookedAtFromTheBoardsCorner() {
        let layout = IslandLayout(notch: notches[0], scale: .standard)
        let widget = IslandWidget(kind: .nowPlaying, frame: GridRect(column: 3, row: 0, width: 7, height: 3), options: IslandWidgetKind.nowPlaying.defaultOptions)
        let onIsland = CanvasGeometry(area: CGSize(width: 700, height: 600), widget: widget, canvasSize: .onIsland, layout: layout, grid: .standard)
        #expect(onIsland.widgetFrame == widget.frame)
        let preset = CanvasGeometry(area: CGSize(width: 700, height: 600), widget: widget, canvasSize: .preset(GridSize(width: 4, height: 2)),
                                    layout: layout, grid: .standard)
        #expect(preset.widgetFrame == GridRect(column: 0, row: 0, width: 4, height: 2))
        #expect(preset.widgetSize.width < onIsland.widgetSize.width)
        // Never larger than the board.
        let huge = CanvasGeometry(area: CGSize(width: 700, height: 600), widget: widget, canvasSize: .preset(GridSize(width: 40, height: 9)),
                                  layout: layout, grid: .standard)
        #expect(huge.widgetFrame.width == BoardGrid.standard.columns && huge.widgetFrame.height == BoardGrid.standard.rows)
    }

    /// The flier is laid at its landing place and transformed onto its place on the stage.
    @Test func theFliersTransformPutsTheLandingRectOnTheSource() {
        let landing = CGRect(x: 400, y: 300, width: 600, height: 270)
        let source = CGRect(x: 520, y: 40, width: 200, height: 90)
        let transform = SettingsSurfaceView.transform(from: landing, to: source)
        // A layer's transform is about its centre.
        let affine = CATransform3DGetAffineTransform(transform)
        func apply(_ point: CGPoint) -> CGPoint {
            let local = CGPoint(x: point.x - landing.midX, y: point.y - landing.midY).applying(affine)
            return CGPoint(x: local.x + landing.midX, y: local.y + landing.midY)
        }
        let topLeft = apply(CGPoint(x: landing.minX, y: landing.minY))
        let bottomRight = apply(CGPoint(x: landing.maxX, y: landing.maxY))
        #expect(abs(topLeft.x - source.minX) < 1e-9 && abs(topLeft.y - source.minY) < 1e-9)
        #expect(abs(bottomRight.x - source.maxX) < 1e-9 && abs(bottomRight.y - source.maxY) < 1e-9)
        #expect(CATransform3DIsIdentity(SettingsSurfaceView.transform(from: landing, to: landing)))
    }

    /// The editor starts to fade in while the widget is in the air, and is there before it lands.
    @Test func theEditorIsInBeforeTheWidgetLands() {
        #expect(SettingsSurfaceView.editorDelay + SettingsSurfaceView.editorIn < SettingsSurfaceView.settleTime)
        #expect(SettingsSurfaceView.pagesOut < SettingsSurfaceView.settleTime)
        #expect(SettingsSurfaceView.editorOut < SettingsSurfaceView.pagesBack)
    }
}

/// Copy Style / Paste Style and the resets.
@MainActor @Suite struct EditorStyleTests {
    private func store() -> (WidgetStore, String) {
        let name = "notchisland.tests.\(UUID().uuidString)"
        return (WidgetStore(defaults: UserDefaults(suiteName: name)!), name)
    }

    @Test func aCopiedStyleGoesToTheElementsOfTheSameRoleInOrder() {
        var source = IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                                  options: IslandWidgetKind.nowPlaying.defaultOptions)
        let texts = IslandWidgetKind.nowPlaying.spec.elements.filter { $0.role == .text }.map(\.id)
        #expect(texts.count >= 2)
        source.style.elements[texts[0], default: ElementStyle()].text.weight = .black
        source.style.elements[texts[1], default: ElementStyle()].text.italic = true
        source.style.layout.padding = 14
        source.style.surface.borderWidth = 2
        source.tint = .red

        var target = IslandWidget(kind: .timer, frame: GridRect(column: 0, row: 0, width: 5, height: 2),
                                  options: IslandWidgetKind.timer.defaultOptions)
        let before = target
        CopiedStyle(source).apply(to: &target)

        let timerTexts = IslandWidgetKind.timer.spec.elements.filter { $0.role == .text }.map(\.id)
        #expect(target.style.elements[timerTexts[0]]?.text.weight == .black)
        // The timer has one text: the second copied one has nowhere to go.
        #expect(timerTexts.count == 1 || target.style.elements[timerTexts[1]]?.text.italic == true)
        #expect(target.style.layout.padding == 14)
        #expect(target.style.surface.borderWidth == 2)
        #expect(target.tint == .red)
        // Where it is, what it is and what it shows stay.
        #expect(target.id == before.id && target.kind == before.kind && target.frame == before.frame)
        #expect(target.options == before.options && target.config == before.config)
        // Elements of other roles, untouched by the copy, keep the kind's own look.
        for element in IslandWidgetKind.timer.spec.elements where element.role != .text {
            #expect(target.style.elements[element.id] == nil)
        }
    }

    @Test func aCopiedStyleSurvivesThePasteboardsCoding() throws {
        var widget = IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                                  options: IslandWidgetKind.nowPlaying.defaultOptions)
        widget.style.elements[.trackInfo, default: ElementStyle()].text.points = 17
        widget.style.format.percentDecimals = 1
        let data = try JSONEncoder().encode(CopiedStyle(widget))
        let decoded = try JSONDecoder().decode(CopiedStyle.self, from: data)
        var other = IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                                 options: IslandWidgetKind.nowPlaying.defaultOptions)
        decoded.apply(to: &other)
        #expect(other.style == widget.style)
    }

    @Test func resettingAnElementLeavesTheOthersAndIsOneUndoStep() {
        let (store, name) = store()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let id = WidgetID.legacy(.nowPlaying)
        let session = EditorSession(widget: id, store: store)
        let texts = IslandWidgetKind.nowPlaying.spec.elements.filter { $0.role == .text }.map(\.id)
        var bold = ElementStyle(), light = ElementStyle()
        bold.text.weight = .bold
        light.text.weight = .light
        session.set(\.elements[texts[0]], to: bold)
        session.set(\.elements[texts[1]], to: light)
        let steps = session.history.undoStack.count

        session.resetElement(texts[0])
        #expect(store.board.widget(id)?.style.elements[texts[0]] == nil)
        #expect(store.board.widget(id)?.style.elements[texts[1]]?.text.weight == .light)
        #expect(session.history.undoStack.count == steps + 1)
        session.undo()
        #expect(store.board.widget(id)?.style.elements[texts[0]]?.text.weight == .bold)
    }

    @Test func resettingTheWidgetKeepsItsPlaceItsElementsAndWhatItShows() {
        let (store, name) = store()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let id = WidgetID.legacy(.nowPlaying)
        let session = EditorSession(widget: id, store: store)
        let before = store.board.widget(id)!
        session.set(\.surface.borderWidth, to: 2)
        session.change(\IslandWidget.tint) { $0.tint = .green }
        #expect(store.board.widget(id) != before)

        session.resetWidget()
        let after = store.board.widget(id)!
        #expect(after.style.isEmpty && after.tint == .automatic)
        #expect(after.frame == before.frame && after.options == before.options && after.config == before.config)
        session.undo()
        #expect(store.board.widget(id)?.tint == .green)
    }

    /// An edit never moves the widget, nor makes it another widget.
    @Test func anEditCannotChangeWhatOrWhereTheWidgetIs() {
        let (store, name) = store()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let id = WidgetID.legacy(.nowPlaying)
        let session = EditorSession(widget: id, store: store)
        let before = store.board.widget(id)!
        session.change(\IslandWidget.self) { widget in
            widget.id = WidgetID()
            widget.kind = .timer
            widget.frame = GridRect(column: 0, row: 0, width: 1, height: 1)
            widget.tint = .blue
        }
        let after = store.board.widget(id)
        #expect(after?.kind == before.kind && after?.frame == before.frame)
        #expect(after?.tint == .blue)
    }
}
