import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

/// A family that draws its elements one by one, as every family will: a symbol, a reading and its
/// caption in a column, sized by the stack planner.
private struct SyntheticFamily: View, WidgetFamilyElements {
    let input: PlanInput

    @Environment(\.widgetFrameProbe) private var probe

    static let order: [ElementID] = [.symbol, .value, .label]
    static let valueType = TypeSpec(points: 0, design: .rounded, weight: .semibold, monospacedDigits: true)
    static let labelType = TypeSpec(points: 0, weight: .medium)

    func demands(_ input: PlanInput) -> [ElementDemand] {
        [ElementDemand(id: .symbol, content: .symbol(name: "star.fill", weight: .semibold), design: 18,
                       size: input.textSize(.symbol), priority: 60),
         ElementDemand(id: .value, content: .text(samples: ["72%"], type: Self.valueType, lines: 1), design: 22,
                       size: input.textSize(.value), priority: 90),
         ElementDemand(id: .label, content: .text(samples: ["Caption"], type: Self.labelType, lines: 1), design: 13,
                       size: input.textSize(.label), priority: 40)]
    }

    var automaticPlan: WidgetPlan {
        StackPlanner(axis: .vertical, room: input.inner, spacing: 4, displayScale: 2).plan(demands(input))
    }

    var body: some View {
        let plan = automaticPlan
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Self.order.filter { plan.elements[$0] != nil }) { id in
                element(id).editorElement(id, in: probe)
            }
        }
        .frame(width: input.inner.width, height: input.inner.height, alignment: .topLeading)
        .environment(\.widgetPlan, plan)
    }

    func element(_ id: ElementID) -> SyntheticElement { SyntheticElement(id: id) }
}

private struct SyntheticElement: View {
    let id: ElementID

    @Environment(\.widgetPlan) private var plan
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let points = plan?.elements[id]?.points ?? 0
        switch id {
        case .symbol: Image(systemName: "star.fill").widgetSymbol(.symbol, points: points, weight: .semibold, in: style)
        case .value: Text("72%").widgetText(.value, SyntheticFamily.valueType.at(points), in: style)
        default: Text("Caption").widgetText(.label, SyntheticFamily.labelType.at(points), in: style)
        }
    }
}

@MainActor @Suite struct CustomLayoutRenderTests {
    static let size = CGSize(width: 175, height: 86)

    /// The widget as `IslandWidgetView` lays a family out, on the canvas: its picture and each
    /// element's frame.
    private static func render(_ widget: IslandWidget, size: CGSize = size) -> (pixels: [UInt8], frames: [ElementID: CGRect]) {
        let padding = WidgetMetrics.padding(for: widget)
        let inner = CGSize(width: size.width - 2 * padding, height: size.height - 2 * padding)
        let probe = WidgetFrameProbe()
        let family = SyntheticFamily(input: PlanInput(widget: widget, size: size, scale: 1))
        let view = ArrangedFamily(family: family, widget: widget, size: inner)
            .frame(width: inner.width, height: inner.height)
            .padding(padding)
            .frame(width: size.width, height: size.height)
            .coordinateSpace(.named(WidgetFrameProbe.space))
            .background(.black)
            .environment(\.widgetStyle, ResolvedWidgetStyle.resolve(widget.style))
            .environment(\.widgetRenderMode, .canvas)
            .environment(\.widgetFrameProbe, probe)
            .environment(\.colorScheme, .dark)
            .environment(AppModel())
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let png = WidgetSnapshotTests.png(renderer.cgImage!)
        return (WidgetSnapshotTests.pixels(png), probe.frames)
    }

    private static func widget() -> IslandWidget {
        IslandWidget(kind: .dateTime, frame: GridRect(column: 0, row: 0, width: 2, height: 1), options: [])
    }

    /// Unlocked where the stacks drew it, the widget draws the same pixels, each element on the
    /// frame it was measured at.
    @Test(arguments: [CGSize(width: 175, height: 86), CGSize(width: 175, height: 187), CGSize(width: 366, height: 86),
                      CGSize(width: 87, height: 86)])
    func unlockingKeepsEveryPixel(_ size: CGSize) throws {
        var widget = Self.widget()
        let automatic = Self.render(widget, size: size)
        let plan = SyntheticFamily(input: PlanInput(widget: widget, size: size, scale: 1)).automaticPlan
        #expect(!automatic.frames.isEmpty && Set(automatic.frames.keys) == Set(plan.elements.keys))
        let unlocked = LayoutConversion.unlock(plan: plan, probed: automatic.frames, size: size,
                                               padding: WidgetMetrics.padding(for: widget))
        unlocked.apply(to: &widget.style, size: size, scale: 1)
        guard case .custom = widget.style.layout.arrangement else { Issue.record("not unlocked"); return }
        let custom = Self.render(widget, size: size)
        for (id, frame) in automatic.frames {
            let placed = try #require(custom.frames[id], "\(id.rawValue) not drawn")
            #expect(abs(placed.minX - frame.minX) < 0.001 && abs(placed.minY - frame.minY) < 0.001
                        && abs(placed.width - frame.width) < 0.001 && abs(placed.height - frame.height) < 0.001,
                    "\(id.rawValue): \(frame) → \(placed)")
        }
        // The same, but for the shade of noise two pictures in one process may differ by while other
        // suites draw (`WidgetSnapshotTests`): never more than 1 in 255.
        let difference = zip(custom.pixels, automatic.pixels).map { max($0, $1) - min($0, $1) }.max() ?? 255
        #expect(custom.pixels.count == automatic.pixels.count && difference <= 1, "\(size): differs by \(difference)")
    }

    /// Every text size comes back from its frame: stored where the frame alone gives another one.
    @Test func unlockedTextKeepsItsSize() {
        let widget = Self.widget()
        let plan = SyntheticFamily(input: PlanInput(widget: widget, size: Self.size, scale: 1)).automaticPlan
        let frames = Self.render(widget).frames
        let unlocked = LayoutConversion.unlock(plan: plan, probed: frames, size: Self.size, padding: WidgetMetrics.padding(for: widget))
        var style = WidgetStyle()
        unlocked.apply(to: &style, size: Self.size, scale: 1)
        let input = PlanInput(spec: widget.kind.spec, size: Self.size, style: style, shown: [])
        let arrangement = ResolvedArrangement.resolve(unlocked.layout, size: Self.size, padding: WidgetMetrics.padding(for: widget))
        let replanned = CustomLayoutPlanner(arrangement: arrangement, displayScale: 2).plan(SyntheticFamily(input: input).demands(input))
        for id in [ElementID.value, .label] {
            #expect(replanned.elements[id]?.points == plan.elements[id]?.points, "\(id.rawValue)")
            #expect(replanned.elements[id]?.isClamped == false)
        }
    }

    /// Hidden for lack of room, an element goes to the tray.
    @Test func elementsWithoutRoomAreParked() {
        let plan = WidgetPlan(elements: [.value: ElementPlan(points: 20, range: 6...20, size: CGSize(width: 40, height: 24),
                                                             variant: 0, isClamped: false)],
                              hidden: [.label: .noRoom, .symbol: .switchedOff])
        let unlocked = LayoutConversion.unlock(plan: plan, probed: [.value: CGRect(x: 6, y: 6, width: 40, height: 24)],
                                               size: Self.size, padding: 6)
        #expect(unlocked.layout.parked == [.label])
        #expect(unlocked.layout.items.map(\.id) == [.value])
        #expect(unlocked.layout.authoredPadding == 6)
    }

    /// A fixed size its frame cannot take is drawn as large as fits, and flagged.
    @Test func fixedTextTooTallForItsFrameIsClampedAndFlagged() {
        let arrangement = ResolvedArrangement(items: [.init(id: .value, frame: CGRect(x: 6, y: 6, width: 120, height: 20))])
        let demand = ElementDemand(id: .value, content: .text(samples: ["72%"], type: TypeSpec(points: 0), lines: 1), design: 20,
                                   size: .fixed(40), priority: 90)
        let plan = CustomLayoutPlanner(arrangement: arrangement, displayScale: 2).plan([demand, ElementDemand(id: .label, content: .box(.zero),
                                                                                               design: 0, size: .auto(.medium), priority: 1)])
        let value = plan.elements[.value]
        #expect(value?.isClamped == true && (value?.points ?? 99) < 40)
        #expect(TextFit.frameHeight(points: value?.points ?? 0, spec: TypeSpec(points: 0)) <= 20)
        #expect(plan.hidden[.label] == .noRoom)
    }

    /// The same layout at the same size is laid out once.
    @Test func arrangementsAreSnappedAndStable() {
        let layout = CustomLayout(authoredSize: Self.size, grid: InnerGrid(columns: 8, rows: 4),
                                  items: [ElementFrame(id: .value, rect: UnitRect(x: 1 / 3, y: 0.1, width: 1 / 7, height: 0.3))],
                                  authoredPadding: 6)
        let first = ResolvedArrangement.resolve(layout, size: Self.size, padding: 6)
        #expect(first == ResolvedArrangement.resolve(layout, size: Self.size, padding: 6))
        let frame = first.items[0].frame
        #expect(frame.minX * 1024 == (frame.minX * 1024).rounded())
    }
}

/// The style as elements draw it.
@Suite struct ResolvedWidgetStyleTests {
    @Test func stylesThatDrawAlikeResolveAlike() {
        #expect(ResolvedWidgetStyle.resolve(WidgetStyle()) == .empty)
        var style = WidgetStyle()
        style.elements[.trackInfo] = ElementStyle()                         // empty: draws nothing new
        style.behaviour.haptic = true                                        // not drawn
        #expect(ResolvedWidgetStyle.resolve(style) == .empty)
        style.elements[.trackInfo]?.text.weight = .bold
        let bold = ResolvedWidgetStyle.resolve(style)
        #expect(bold != .empty && bold.element(.trackInfo)?.text.weight == .bold)
        #expect(bold.element(.artist) == nil)
        // Memoised: resolving again gives the same, and another style its own.
        #expect(ResolvedWidgetStyle.resolve(style) == bold)
        style.elements[.trackInfo]?.text.weight = .light
        #expect(ResolvedWidgetStyle.resolve(style) != bold)
    }

    @Test func artworkIsReadOnlyWhenAColourFollowsIt() {
        var style = WidgetStyle()
        style.elements[.trackInfo, default: ElementStyle()].colors[.primary] = .theme
        #expect(!ResolvedWidgetStyle.resolve(style).usesArtwork)
        style.surface.fillEnd = .artwork
        #expect(ResolvedWidgetStyle.resolve(style).usesArtwork)
    }

    /// The cover is concentric inside the real padding (14 without a plate, 10 on one), and a
    /// widget in the panel's bottom corner is concentric with the panel.
    @Test func cornersFollowThePaddingAndThePanel() {
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard)
        var widget = IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3), options: [])
        let outer = ConcentricGeometry.outer(for: widget.frame, grid: .standard, size: CGSize(width: 300, height: 140),
                                             boardCorner: ConcentricGeometry.boardCornerRadius(layout))
        #expect(outer.topLeading == 16 && outer.bottomLeading == 22 && outer.bottomTrailing == 16)
        #expect(WidgetCorners(outer: outer, padding: WidgetMetrics.padding(for: widget)).inner.topLeading == 10)
        widget.background = .none
        #expect(WidgetCorners(outer: outer, padding: WidgetMetrics.padding(for: widget)).inner.topLeading == 14)
        #expect(WidgetCorners(outer: outer, padding: WidgetMetrics.padding(for: widget)).inner.bottomLeading == 20)
    }

    /// A radius of the style's own is every corner of the widget — its background's, and those the
    /// cover and plates inside are concentric with — at most half a side, and never on a circle.
    @Test @MainActor func aRadiusOfItsOwnIsEveryCorner() {
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard)
        let board = WidgetBoardShape(grid: .standard, cornerRadius: ConcentricGeometry.boardCornerRadius(layout))
        var widget = IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3), options: [])
        let size = CGSize(width: 300, height: 140)
        #expect(IslandWidgetView.outerCorners(widget, size: size, board: board).bottomLeading == 22)
        widget.style.surface.cornerRadius = 8
        let corners = WidgetCorners(outer: IslandWidgetView.outerCorners(widget, size: size, board: board),
                                    padding: WidgetMetrics.padding(for: widget))
        #expect(corners.outer == .uniform(8) && corners.inner == .uniform(ConcentricGeometry.minimumInnerRadius))
        widget.style.surface.cornerRadius = 30
        #expect(IslandWidgetView.outerCorners(widget, size: size, board: board).uniformRadius == 30)
        #expect(IslandWidgetView.outerCorners(widget, size: CGSize(width: 300, height: 40), board: board).uniformRadius == 20)
        widget.frame = GridRect(column: 0, row: 0, width: 1, height: 1)
        #expect(IslandWidgetView.outerCorners(widget, size: CGSize(width: 44, height: 44), board: board).uniformRadius == 22)
    }
}
