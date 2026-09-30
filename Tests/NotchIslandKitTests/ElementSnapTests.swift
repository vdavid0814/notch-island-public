import CoreGraphics
import Testing
@testable import NotchIslandKit

/// Dragging elements inside a widget: the grid, guides, the zoom's threshold, ⌘, minimums, aspect,
/// the safe rect and the overlap rule.
@Suite struct ElementSnapTests {
    /// 200 × 100 with a 10 × 5 grid (a line every 20 pt) and a 6 pt padding.
    private func snapper(items: [InnerSnapper.Item] = [], zoom: CGFloat = 1) -> InnerSnapper {
        InnerSnapper(size: CGSize(width: 200, height: 100), grid: InnerGrid(columns: 10, rows: 5), padding: 6, items: items, zoom: zoom)
    }

    private let everywhere = CGRect(x: 0, y: 0, width: 200, height: 100)

    private func move(_ snapper: InnerSnapper, _ rect: CGRect, bounds: CGRect? = nil, interactive: Bool = false,
                      snapping: Bool = true) -> InnerSnapper.Placement {
        snapper.move([.trackInfo], to: rect, bounds: bounds ?? everywhere, isInteractive: interactive, snapping: snapping)
    }

    @Test func landsOnTheNearestGridLine() {
        let placed = move(snapper(), CGRect(x: 21.5, y: 61, width: 30, height: 15))
        #expect(placed.rect == CGRect(x: 20, y: 60, width: 30, height: 15))
        #expect(placed.guides.isEmpty)
    }

    @Test func guidesWinOverTheGridOnTies() {
        let item = InnerSnapper.Item(id: .artwork, rect: CGRect(x: 43, y: 70, width: 20, height: 20), isInteractive: false)
        let tie = move(snapper(items: [item]), CGRect(x: 41.5, y: 21, width: 10, height: 10))
        #expect(tie.rect.minX == 43)
        #expect(tie.guides.contains(SnapGuide(axis: .vertical, position: 43, kind: .itemEdge)))
        // A nearer grid line still wins.
        #expect(move(snapper(items: [item]), CGRect(x: 40.5, y: 21, width: 10, height: 10)).rect.minX == 40)
    }

    @Test func snapsToTheCentreEdgesAndPaddingLine() {
        let centred = move(snapper(), CGRect(x: 83.2, y: 23, width: 30, height: 10))
        #expect(centred.rect.midX == 100)
        #expect(centred.guides.contains(SnapGuide(axis: .vertical, position: 100, kind: .centre)))
        let padded = move(snapper(), CGRect(x: 7.5, y: 23, width: 30, height: 10))
        #expect(padded.rect.minX == 6)
        #expect(padded.guides.contains(SnapGuide(axis: .vertical, position: 6, kind: .padding)))
    }

    @Test func theThresholdIsFourScreenPoints() {
        let proposed = CGRect(x: 23, y: 63, width: 10, height: 10)
        #expect(snapper(zoom: 1).threshold == 4)
        #expect(move(snapper(zoom: 1), proposed).rect.minX == 20)
        // Magnified 3×: 3 pt of the widget is 9 on screen, too far.
        #expect(snapper(zoom: 3).threshold == 4.0 / 3)
        #expect(move(snapper(zoom: 3), proposed).rect == proposed)
    }

    @Test func commandTurnsSnappingOff() {
        let proposed = CGRect(x: 21.5, y: 61, width: 30, height: 15)
        let placed = move(snapper(), proposed, snapping: false)
        #expect(placed.rect == proposed && placed.guides.isEmpty)
    }

    @Test func textStaysInsideThePaddingAndImagesMayBleed() {
        let safe = ElementLayoutGeometry.bounds(mayBleed: false, in: CGSize(width: 200, height: 100), padding: 6)
        let text = move(snapper(), CGRect(x: -20, y: 90, width: 50, height: 20), bounds: safe)
        #expect(text.rect == CGRect(x: 6, y: 74, width: 50, height: 20))
        let bleed = ElementLayoutGeometry.bounds(mayBleed: true, in: CGSize(width: 200, height: 100), padding: 6)
        #expect(move(snapper(), CGRect(x: -20, y: 90, width: 50, height: 20), bounds: bleed).rect == CGRect(x: 0, y: 80, width: 50, height: 20))
    }

    @Test func resizeSnapsOnlyTheDraggedEdge() {
        let original = CGRect(x: 20, y: 20, width: 30, height: 20)
        let placed = snapper().resize(.trackInfo, from: original, to: CGRect(x: 20, y: 20, width: 38.5, height: 21.5), edges: [.maxX],
                                      minimum: .zero, keepsAspect: false, bounds: everywhere, isInteractive: false)
        #expect(placed.rect == CGRect(x: 20, y: 20, width: 40, height: 20))
        let leading = snapper().resize(.trackInfo, from: original, to: CGRect(x: 1.5, y: 20, width: 48.5, height: 20), edges: [.minX],
                                       minimum: .zero, keepsAspect: false, bounds: everywhere, isInteractive: false)
        #expect(leading.rect == CGRect(x: 0, y: 20, width: 50, height: 20))
    }

    @Test func resizeKeepsTheMinimumForTheRole() {
        let button = InnerSnapper.minimumSize(.button)
        #expect(button == CGSize(width: 20, height: 20))
        let original = CGRect(x: 40, y: 40, width: 40, height: 40)
        let placed = snapper().resize(.playbackButtons, from: original, to: CGRect(x: 40, y: 40, width: 3, height: 3), edges: [.maxX, .maxY],
                                      minimum: button, keepsAspect: false, bounds: everywhere, isInteractive: true, snapping: false)
        #expect(placed.rect == CGRect(x: 40, y: 40, width: 20, height: 20))
        let text = InnerSnapper.minimumSize(.text)
        #expect(text.height == TextFit.frameHeight(points: 6, spec: TypeSpec(points: 6)))
        #expect(InnerSnapper.minimumSize(.divider(.horizontal)).height == 1)
    }

    @Test func aspectFollowsTheLargerChange() {
        let original = CGRect(x: 20, y: 20, width: 40, height: 20)
        let corner = snapper().resize(.artwork, from: original, to: CGRect(x: 20, y: 20, width: 80, height: 30), edges: [.maxX, .maxY],
                                      minimum: .zero, keepsAspect: true, bounds: everywhere, isInteractive: false, snapping: false)
        #expect(corner.rect == CGRect(x: 20, y: 20, width: 80, height: 40))
        // A side handle grows the other side about its centre.
        let side = snapper().resize(.artwork, from: original, to: CGRect(x: 20, y: 20, width: 60, height: 20), edges: [.maxX],
                                    minimum: .zero, keepsAspect: true, bounds: everywhere, isInteractive: false, snapping: false)
        #expect(side.rect == CGRect(x: 20, y: 15, width: 60, height: 30))
        // Held inside the bounds, still at its aspect.
        let bounded = snapper().resize(.artwork, from: original, to: CGRect(x: 20, y: 20, width: 400, height: 20), edges: [.maxX, .maxY],
                                       minimum: .zero, keepsAspect: true, bounds: everywhere, isInteractive: false, snapping: false)
        let expected = CGRect(x: 20, y: 20, width: 160, height: 80)
        #expect(abs(bounded.rect.width - expected.width) < 1e-9 && abs(bounded.rect.height - expected.height) < 1e-9
            && bounded.rect.origin == expected.origin)
    }

    /// Dragged past the held edge, an element keeping its aspect stops at its minimum rather than
    /// collapsing to nothing.
    @Test func anInvertedAspectResizeStopsAtTheMinimum() {
        let original = CGRect(x: 50, y: 20, width: 40, height: 40)
        let minimum = CGSize(width: 16, height: 16)
        for proposed in [CGRect(x: 50, y: 20, width: 0, height: 40), CGRect(x: 20, y: 20, width: 20, height: 40)] {
            let side = snapper().resize(.artwork, from: original, to: proposed, edges: [.maxX], minimum: minimum, keepsAspect: true,
                                        bounds: everywhere, isInteractive: false, snapping: false)
            #expect(side.rect == CGRect(x: 50, y: 32, width: 16, height: 16), "\(proposed)")
        }
        let corner = snapper().resize(.artwork, from: original, to: CGRect(x: 10, y: 5, width: 0, height: 0), edges: [.maxX, .maxY],
                                      minimum: minimum, keepsAspect: true, bounds: everywhere, isInteractive: false, snapping: false)
        #expect(corner.rect == CGRect(x: 50, y: 20, width: 16, height: 16))
    }

    @Test func interactiveElementsNeverOverlap() {
        let play = InnerSnapper.Item(id: .playbackButtons, rect: CGRect(x: 100, y: 20, width: 30, height: 30), isInteractive: true)
        let cover = InnerSnapper.Item(id: .artwork, rect: CGRect(x: 0, y: 0, width: 60, height: 100), isInteractive: false)
        let snapper = snapper(items: [play, cover])
        #expect(move(snapper, CGRect(x: 110, y: 30, width: 30, height: 30), interactive: true, snapping: false).isRefused)
        // Touching is fine, and so is layering over the cover.
        #expect(!move(snapper, CGRect(x: 130, y: 20, width: 30, height: 30), interactive: true, snapping: false).isRefused)
        #expect(!move(snapper, CGRect(x: 10, y: 10, width: 30, height: 30), interactive: true, snapping: false).isRefused)
        // Text over a button is layering, not refused.
        #expect(!move(snapper, CGRect(x: 110, y: 30, width: 30, height: 30), interactive: false, snapping: false).isRefused)
        let grown = snapper.resize(.skipButtons, from: CGRect(x: 140, y: 20, width: 30, height: 30),
                                   to: CGRect(x: 120, y: 20, width: 50, height: 30), edges: [.minX], minimum: .zero, keepsAspect: false,
                                   bounds: everywhere, isInteractive: true, snapping: false)
        #expect(grown.isRefused)
        #expect(InnerSnapper.isInteractive(IslandWidgetKind.nowPlaying.spec.element(.progress)!))
        #expect(!InnerSnapper.isInteractive(IslandWidgetKind.nowPlaying.spec.element(.trackInfo)!))
    }

    @Test func aPointSnapsLikeAnEdge() {
        let snapper = snapper()
        let targets = snapper.targets(excluding: [])
        let point = snapper.snap(CGPoint(x: 98.5, y: 41), targets: targets, threshold: 4)
        #expect(point.value == CGPoint(x: 100, y: 40))
        #expect(point.guides == [SnapGuide(axis: .vertical, position: 100, kind: .centre)])
    }
}
