import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

/// The editor's canvas (`WidgetRenderMode.canvas`): every element it tags lies inside its widget,
/// and it lays out exactly as the island, so what the editor measures there is where the elements
/// are on the island.
@MainActor @Suite struct WidgetCanvasTests {
    /// Each element's frame in the widget, in `style`, as `mode` lays the widget out: live as a
    /// picture (`preview`, Settings' gallery) or as the island draws it.
    static func frames(_ item: WidgetSnapshotTests.Case, mode: WidgetRenderMode, preview: Bool = true, style: WidgetStyle = WidgetStyle(),
                       model: AppModel = AppModel()) -> (frames: [ElementID: CGRect], size: CGSize) {
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard)
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(layout), grid: .standard)
        let rect = GridRect(column: 0, row: 0, width: item.size.width, height: item.size.height)
        let size = geometry.frame(for: rect).size
        let probe = WidgetFrameProbe()
        var widget = IslandWidget(kind: item.kind, frame: rect, options: item.kind.defaultOptions)
        widget.style = style
        let view = IslandWidgetView(widget: widget, size: size, thumbnails: ThumbnailCache())
            .frame(width: size.width, height: size.height)
            // The island names no space: the same one, outside the widget.
            .coordinateSpace(.named(WidgetFrameProbe.space))
            .environment(model)
            .environment(\.widgetRenderMode, mode)
            // A picture reads nothing from the system (a control would start observing Bluetooth);
            // as the island, nothing starts observing either: its panel counts as hidden.
            .environment(\.isWidgetPreview, preview)
            .environment(\.isIslandPanelHidden, !preview)
            .environment(\.widgetFrameProbe, probe)
            .environment(\.widgetDate, WidgetSnapshotTests.date)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        _ = renderer.cgImage
        return (probe.frames, size)
    }

    @Test(arguments: WidgetSnapshotTests.cases) func everyElementIsInsideItsWidget(_ item: WidgetSnapshotTests.Case) {
        let (frames, size) = Self.frames(item, mode: .canvas)
        // A button alone (a control, Siri) or a slider alone has no element of its own to tag.
        #expect(Set(frames.keys).isSubset(of: item.kind.spec.elementIDs), "\(item.name): \(frames.keys)")
        let widget = CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5)
        for (id, frame) in frames {
            #expect(widget.contains(frame), "\(item.name): \(id.rawValue) at \(frame) outside \(size)")
        }
    }

    /// Now Playing on one line (one row tall) draws its title in its style too: alone, and sharing
    /// the line with the artist.
    @Test func oneLineTitlesTakeTheirStyle() {
        var style = WidgetStyle()
        style.elements[.trackInfo, default: ElementStyle()].text.points = 18
        for width in [3, 12] {
            let item = WidgetSnapshotTests.Case(kind: .nowPlaying, size: GridSize(width: width, height: 1))
            let plain = Self.frames(item, mode: .canvas).frames[.trackInfo]?.height ?? .infinity
            let styled = Self.frames(item, mode: .canvas, style: style).frames[.trackInfo]?.height ?? 0
            #expect(styled > plain, "\(item.name): \(styled) against \(plain)")
        }
    }

    /// Against the picture Settings draws (bordered buttons in the glass buttons' room).
    @Test(arguments: WidgetSnapshotTests.cases) func canvasLaysOutAsTheIsland(_ item: WidgetSnapshotTests.Case) {
        // One model, the picture first: what it reads (the keyboard's backlight) the canvas shows.
        let model = AppModel()
        let live = Self.frames(item, mode: .live, model: model).frames
        Self.expectSameFrames(Self.frames(item, mode: .canvas, model: model).frames, live, item)
    }

    /// Against the island as it draws: glass buttons, the model's readings. The keyboard's backlight
    /// is read once, as the island reads it. Controls are left out: a switch shows its state on the
    /// island and "on" on the canvas, which changes its wording, not its layout (they have no glass;
    /// the test above compares them). Frames only: glass drawn off screen is not the island's glass.
    @Test(arguments: WidgetSnapshotTests.cases.filter { $0.kind.spec.family != .controls })
    func canvasLaysOutAsTheGlassIsland(_ item: WidgetSnapshotTests.Case) {
        let model = AppModel()
        model.controls.refresh()
        let island = Self.frames(item, mode: .live, preview: false, model: model).frames
        Self.expectSameFrames(Self.frames(item, mode: .canvas, model: model).frames, island, item)
    }

    static func expectSameFrames(_ canvas: [ElementID: CGRect], _ island: [ElementID: CGRect], _ item: WidgetSnapshotTests.Case) {
        #expect(Set(canvas.keys) == Set(island.keys), "\(item.name)")
        for (id, frame) in canvas {
            guard let live = island[id] else { continue }
            #expect(abs(frame.minX - live.minX) < 0.01 && abs(frame.minY - live.minY) < 0.01
                        && abs(frame.width - live.width) < 0.01 && abs(frame.height - live.height) < 0.01,
                    "\(item.name): \(id.rawValue) canvas \(frame), island \(live)")
        }
    }

    /// The drawing of a glass button takes the glass button's room, at every control size, in both
    /// shapes, prominent or not, with a symbol, a title or both: in a window, and rendered off
    /// screen (where no font comes from the control size).
    @Test func glassPicturesTakeTheGlassButtonsRoom() {
        let window = NSWindow(contentRect: CGRect(x: -5000, y: -5000, width: 400, height: 200), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        func size(_ view: some View) -> [CGSize] { Self.size(view, in: window) }
        for controlSize in [ControlSize.mini, .small, .regular, .large] {
            for shape in [IslandButtonShape.circle, .capsule] {
                for prominent in [false, true] {
                    for title in ["Start Timer", "+1", ""] {
                        let button = Button {} label: {
                            if title.isEmpty { Label("Play", systemImage: "play.fill") } else { Text(title) }
                        }
                        .islandButton(shape, prominent: prominent)
                        .controlSize(controlSize)
                        .fixedSize()
                        let glass = size(button)
                        let picture = size(button.environment(\.widgetRenderMode, .canvas))
                        #expect(glass == picture, "\(controlSize) \(shape) prominent \(prominent) \"\(title)\": \(glass) vs \(picture)")
                    }
                }
            }
        }
    }

    /// The same for a button in a style's look (Customize: glass or prominent, in each shape) and in a
    /// Now Playing button's own glass (`transportGlass`), which only draw while a track is loaded.
    @Test func styledGlassPicturesTakeTheirButtonsRoom() {
        let window = NSWindow(contentRect: CGRect(x: -5000, y: -5000, width: 400, height: 200), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        func expectSameRoom(_ button: (WidgetRenderMode) -> some View, _ description: String) {
            let glass = Self.size(button(.live), in: window)
            let picture = Self.size(button(.canvas).environment(\.widgetRenderMode, .canvas), in: window)
            #expect(glass == picture, "\(description): \(glass) vs \(picture)")
        }
        for controlSize in [ControlSize.mini, .small, .regular, .large] {
            for look in [ButtonLookChoice.glass, .prominent] {
                for shape in ButtonShapeChoice.allCases {
                    var style = WidgetStyle()
                    style.elements[.playbackButtons, default: ElementStyle()].button.look = look
                    style.elements[.playbackButtons]?.button.shape = shape
                    let button = Button {} label: { Label("Play", systemImage: "play.fill") }
                        .widgetButton(.playbackButtons, in: ResolvedWidgetStyle.resolve(style))
                        .islandButton(.circle)
                        .controlSize(controlSize)
                        .fixedSize()
                    expectSameRoom({ _ in button }, "\(controlSize) \(look) \(shape)")
                }
            }
            expectSameRoom({ mode in
                Button {} label: { Label("Next", systemImage: "forward.fill").imageScale(.small) }
                    .transportGlass(ButtonLook(), on: mode)
                    .islandButton(.circle)
                    .controlSize(controlSize)
                    .fixedSize()
            }, "\(controlSize) transport")
        }
    }

    /// A view's room: laid out in a window (the island's glass), and its frame drawn off screen.
    static func size(_ view: some View, in window: NSWindow) -> [CGSize] {
        let host = NSHostingView(rootView: view)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let probe = WidgetFrameProbe()
        let renderer = ImageRenderer(content: view.editorElement(.readout, in: probe).coordinateSpace(.named(WidgetFrameProbe.space)))
        renderer.scale = 2
        _ = renderer.cgImage
        return [host.fittingSize, probe.frames[.readout]?.size ?? .zero]
    }

    /// Nothing on the canvas answers a click: one that works a button or a slider on the island does
    /// nothing there (no volume set, no media command sent, no switch flipped). Clicked in a window
    /// off screen: SwiftUI takes clicks only in a window that is ordered in.
    @Test func clicksOnTheCanvasDoNothing() {
        final class Calls { var count = 0 }
        let window = NSWindow(contentRect: CGRect(x: -5000, y: -5000, width: 240, height: 60), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        func calls(_ mode: WidgetRenderMode) -> Int {
            let calls = Calls()
            let view = HStack(spacing: 0) {
                Button { calls.count += 1 } label: { Color.clear.frame(width: 120, height: 60).contentShape(.rect) }
                    .buttonStyle(.plain)
                SliderPicture(value: 0.5, set: { _ in calls.count += 1 }, onEditingChanged: { _ in calls.count += 1 })
                    .frame(width: 120, height: 60)
            }
            .canvasPicture(mode == .canvas)
            .environment(\.widgetRenderMode, mode)
            let host = NSHostingView(rootView: view)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            // A click on the button, a drag along the slider.
            for x in [60.0, 180.0] {
                for (type, dx) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseDragged, 5), (.leftMouseUp, 10)] {
                    window.sendEvent(NSEvent.mouseEvent(with: type, location: NSPoint(x: x + dx, y: 30), modifierFlags: [],
                                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
                }
            }
            return calls.count
        }
        // The same clicks work them on the island (the button once, the slider's edit and values).
        #expect(calls(.live) == 5)
        #expect(calls(.canvas) == 0)
    }

    @Test func sliderPicturesAreAsTallAsTheNativeSlider() {
        let window = NSWindow(contentRect: CGRect(x: -5000, y: -5000, width: 400, height: 200), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        for controlSize in [ControlSize.mini, .small, .regular, .large] {
            let host = NSHostingView(rootView: Slider(value: .constant(0.5)).controlSize(controlSize).frame(width: 100).fixedSize())
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            #expect(SliderPicture.nativeHeight(controlSize) == host.fittingSize.height, "\(controlSize)")
        }
    }
}
