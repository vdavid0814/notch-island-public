import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import NotchIslandKit

@Suite struct ElementDragTests {
    /// A 20 × 10 part at (10, 10) in a 200 × 100 widget, another part's edges at x 60 and 100.
    private func drag(release: CGFloat = 4) -> ElementDrag {
        ElementDrag(id: .artwork, base: CGRect(x: 10, y: 10, width: 20, height: 10), start: .zero,
                    others: [CGRect(x: 60, y: 70, width: 40, height: 20)], bounds: CGSize(width: 200, height: 100),
                    release: release)
    }

    @Test func movesAWholePointAtATime() {
        var drag = drag()
        #expect(drag.move(by: CGSize(width: 0.4, height: 0)) == .none)
        #expect(drag.move(by: CGSize(width: 0.6, height: 0)) == .moved)
        #expect(drag.offset == ElementOffset(x: 1, y: 0))
        #expect(drag.move(by: CGSize(width: 3.3, height: 2.7)) == .moved)
        #expect(drag.offset == ElementOffset(x: 3, y: 3))
    }

    @Test func anEdgeIsCaughtAndHeldUntilThePointerGoesPastTheRelease() {
        var drag = drag()
        // Its right edge (30) reaches the other part's left edge (60) at 30.
        #expect(drag.move(by: CGSize(width: 29, height: 0)) == .moved)
        #expect(drag.move(by: CGSize(width: 30.2, height: 0)) == .snapped)
        #expect(drag.frame.maxX == 60)
        // Held while within 4 points past it.
        #expect(drag.move(by: CGSize(width: 33.5, height: 0)) == .none)
        #expect(drag.frame.maxX == 60)
        // Let go beyond.
        #expect(drag.move(by: CGSize(width: 34.4, height: 0)) == .moved)
        #expect(drag.offset.x == 34)
        #expect(drag.stuckX == nil)
    }

    @Test func aLineJumpedOverIsCaught() {
        var drag = drag()
        // From 0 to 40 in one move: the right edge goes from 30 to 70, over 60.
        #expect(drag.move(by: CGSize(width: 40, height: 0)) == .snapped)
        #expect(drag.frame.maxX == 60)
    }

    @Test func centresSnapToCentresAndTheWidgetsCentre() {
        var drag = drag()
        // The other part's centre is at x 80: the part's centre (20) gets there at 60.
        drag.move(by: CGSize(width: 59.8, height: 0))
        #expect(drag.frame.midX == 80)
        #expect(drag.stuckX?.feature == .centre)
        #expect(drag.nearCentres().x == [80])
        // The widget's centre on y (50): the part's centre (15) gets there at 35.
        drag.move(by: CGSize(width: 59.8, height: 35.2))
        #expect(drag.frame.midY == 50)
    }

    @Test func staysInsideTheWidget() {
        var drag = drag()
        drag.move(by: CGSize(width: -50, height: -50))
        #expect(drag.frame.origin == .zero)
        // One leap catches the lines it jumps over; the next move lets go of them.
        drag.move(by: CGSize(width: 500, height: 500))
        drag.move(by: CGSize(width: 501, height: 501))
        #expect(drag.frame.maxX == 200)
        #expect(drag.frame.maxY == 100)
    }

    @Test func offsetsAreStoredAndDecoded() throws {
        var widget = IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                                  options: IslandWidgetKind.nowPlaying.defaultOptions)
        widget.setOffset(ElementOffset(x: 3, y: -2), of: .previousButton)
        widget.setOffset(ElementOffset(x: 1, y: 1), of: .artwork)
        widget.setOffset(.zero, of: .artwork)
        #expect(widget.offsets == [.previousButton: ElementOffset(x: 3, y: -2)])
        let decoded = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(widget))
        #expect(decoded == widget)
    }

    @Test func offsetsOfPartsAKindDoesNotHaveAreDropped() {
        var widget = IslandWidget(kind: .wifi, frame: GridRect(column: 0, row: 0, width: 2, height: 1), options: [])
        widget.offsets[.artwork] = ElementOffset(x: 4, y: 4)
        widget.sanitize()
        #expect(widget.offsets.isEmpty)
    }
}

@Suite struct ElementInkTests {
    /// A 40 × 20 picture at scale 2 (a 20 × 10 widget) with a dot from (10, 6) to (13, 9) pixels.
    private func picture() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        // Core Graphics counts from the bottom: rows 6…9 from the top are 10…13 from the bottom.
        context.fill(CGRect(x: 10, y: 10, width: 4, height: 4))
        return try #require(context.makeImage())
    }

    @Test func aPartIsWhereItsPixelsAre() throws {
        let ink = ElementInk.bounds(in: try picture(), scale: 2, boxes: [.artwork: CGRect(x: 0, y: 0, width: 10, height: 10)])
        #expect(ink[.artwork] == CGRect(x: 5, y: 3, width: 2, height: 2))
    }

    @Test func aPartWithNothingDrawnKeepsItsBox() throws {
        let box = CGRect(x: 12, y: 0, width: 8, height: 10)
        #expect(ElementInk.bounds(in: try picture(), scale: 2, boxes: [.artist: box])[.artist] == box)
    }
}

@Suite struct ElementGapTests {
    @Test func theNearestFacingNeighbourOnEachSide() {
        // Previous, play, next on a row; the title above, facing play; a far part below, not facing.
        let play = CGRect(x: 50, y: 50, width: 10, height: 10)
        let gaps = ElementGap.around(play, among: [
            CGRect(x: 20, y: 52, width: 20, height: 8),
            CGRect(x: 0, y: 50, width: 10, height: 10),
            CGRect(x: 70, y: 48, width: 20, height: 14),
            CGRect(x: 40, y: 10, width: 40, height: 20),
            CGRect(x: 200, y: 90, width: 10, height: 10),
        ])
        #expect(gaps == [
            ElementGap(axis: .horizontal, start: 40, end: 50, across: 56, isEven: true),
            ElementGap(axis: .horizontal, start: 60, end: 70, across: 55, isEven: true),
            ElementGap(axis: .vertical, start: 30, end: 50, across: 55),
        ])
    }
}

@Suite struct EvenSpacingSnapTests {
    @Test func theCentreSticksWhereBothGapsAreEven() {
        // Neighbours end at 40 and start at 100: even at a centre of 70 (offset 15 for a part at 50…60).
        var drag = ElementDrag(id: .playbackButtons, base: CGRect(x: 50, y: 50, width: 10, height: 10), start: .zero,
                               others: [CGRect(x: 20, y: 50, width: 20, height: 10), CGRect(x: 100, y: 50, width: 20, height: 10)],
                               bounds: CGSize(width: 300, height: 120))
        drag.move(by: CGSize(width: 14, height: 0))
        #expect(drag.move(by: CGSize(width: 15.2, height: 0)) == .snapped)
        #expect(drag.frame.midX == 70)
        let gaps = ElementGap.around(drag.frame, among: drag.others)
        let horizontal = gaps.filter { $0.axis == .horizontal }
        #expect(horizontal.count == 2 && horizontal.allSatisfy { $0.isEven })
    }
}

@Suite struct ElementLayerTests {
    private func widget() -> IslandWidget {
        IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                     options: IslandWidgetKind.nowPlaying.defaultOptions)
    }

    @Test func laterPartsAreOnTopUntilALayerSaysOtherwise() throws {
        var widget = widget()
        #expect(widget.isDrawn(.previousButton, over: .artwork))
        widget.layers[.previousButton] = -1
        #expect(widget.isDrawn(.artwork, over: .previousButton))
        // A row goes over or under as its part furthest from 0 does.
        #expect(widget.layer(ofGroup: NowPlayingWidget.buttonParts) == -1)
        widget.layers[.nextButton] = 2
        #expect(widget.layer(ofGroup: NowPlayingWidget.buttonParts) == 2)
        let decoded = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(widget))
        #expect(decoded.layers == [.previousButton: -1, .nextButton: 2])
    }

    @MainActor @Test func undoAndRedoWalkTheHistory() {
        let editing = ElementEditing()
        let first = widget()
        var second = first
        second.setOffset(ElementOffset(x: 4, y: 0), of: .artwork)
        editing.record(first, second)
        #expect(editing.undo(from: second) == first)
        // Putting it back is not recorded as a change of its own.
        editing.record(second, first)
        #expect(editing.redoStack.count == 1)
        #expect(editing.redo(from: first) == second)
        editing.record(first, second)
        #expect(editing.undoStack == [first])
    }
}

@Suite struct ElementResizeTests {
    /// A 20 × 10 part at (10, 10) in a 200 × 100 widget; another part's left edge at x 60.
    private func resize(_ horizontal: Int, _ vertical: Int) -> ElementResize {
        ElementResize(id: .artwork, horizontal: horizontal, vertical: vertical, start: CGRect(x: 10, y: 10, width: 20, height: 10),
                      others: [CGRect(x: 60, y: 70, width: 40, height: 20)], bounds: CGSize(width: 200, height: 100))
    }

    @Test func aSideMovesOnlyItsOwnAxis() {
        var right = resize(1, 0)
        right.move(by: CGSize(width: 7.4, height: 25))
        #expect(right.frame == CGRect(x: 10, y: 10, width: 27, height: 10))
        var top = resize(0, -1)
        top.move(by: CGSize(width: 30, height: -4.2))
        #expect(top.frame == CGRect(x: 10, y: 6, width: 20, height: 14))
    }

    @Test func aCornerMovesItsTwoSidesAndTheOppositeOnesStay() {
        var topRight = resize(1, -1)
        topRight.move(by: CGSize(width: 5, height: -3))
        #expect(topRight.frame == CGRect(x: 10, y: 7, width: 25, height: 13))
        var bottomLeft = resize(-1, 1)
        bottomLeft.move(by: CGSize(width: -4, height: 6))
        #expect(bottomLeft.frame == CGRect(x: 6, y: 10, width: 24, height: 16))
    }

    @Test func neverSmallerThanTheMinimumNorOutsideTheWidget() {
        var left = resize(-1, 0)
        left.move(by: CGSize(width: 50, height: 0))
        #expect(left.frame.width == ElementResize.minimum)
        var bottom = resize(0, 1)
        bottom.move(by: CGSize(width: 0, height: 500))
        bottom.move(by: CGSize(width: 0, height: 501))
        #expect(bottom.frame.maxY == 100)
    }

    @Test func anEdgeSticksToAnotherPartsEdge() {
        var right = resize(1, 0)
        // The right edge (30) reaches the other part's left edge (60) at 30.
        #expect(right.move(by: CGSize(width: 30.3, height: 0)) == .snapped)
        #expect(right.frame.maxX == 60)
    }

    @Test func shiftKeepsTheProportions() {
        var corner = resize(1, 1)
        corner.move(by: CGSize(width: 20, height: 1), keepsRatio: true)
        #expect(corner.frame == CGRect(x: 10, y: 10, width: 40, height: 20))
    }

    @Test func theNewSizeIsAScaleAndAnOffset() {
        let ink = CGRect(x: 12, y: 14, width: 20, height: 10), box = CGRect(x: 10, y: 10, width: 30, height: 20)
        let target = CGRect(x: 5, y: 8, width: 30, height: 25)
        let transform = ElementResize.transform(for: target, ink: ink, box: box)
        #expect(transform.scale == ElementScale(x: 1.5, y: 2.5))
        let drawn = transform.scale.applied(to: ink, in: box).offsetBy(dx: transform.offset.x, dy: transform.offset.y)
        #expect(abs(drawn.minX - target.minX) < 0.001 && abs(drawn.maxY - target.maxY) < 0.001)
    }
}

@Suite struct TextStyleTests {
    private func widget() -> IslandWidget {
        IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                     options: IslandWidgetKind.nowPlaying.defaultOptions)
    }

    @Test func aStyleIsStoredAndDecoded() throws {
        var widget = widget()
        var style = TextStyle()
        style.size = 22
        style.isItalic = true
        style.maxLines = 3
        style.alignment = .justified
        style.color = .custom(IslandTheme.RGB(red: 1, green: 0.5, blue: 0))
        style.background = ElementBackground(kind: .colour, color: IslandTheme.RGB(red: 0, green: 0, blue: 1), opacity: 0.6, corners: .capsule)
        style.box = TextStyle.BoxSize(width: 120, height: 40)
        widget.setTextStyle(style, of: .trackInfo)
        let decoded = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(widget))
        #expect(decoded.textStyle(of: .trackInfo) == style)
    }

    @Test func onlyTextPartsAreStyledAndValuesStayInRange() {
        var widget = widget()
        var style = TextStyle()
        style.size = 400
        style.maxLines = 50
        style.background = ElementBackground(opacity: 3)
        widget.textStyles[.artist] = style
        widget.textStyles[.artwork] = style
        widget.scales[.artist] = ElementScale(x: 2, y: 2)
        widget.sanitize()
        #expect(widget.textStyles[.artwork] == nil)
        // A text part is never stretched.
        #expect(widget.scales[.artist] == nil)
        let kept = widget.textStyle(of: .artist)
        #expect(kept.size == TextStyle.sizes.upperBound)
        #expect(kept.maxLines == TextStyle.lines.upperBound)
        #expect(kept.background?.opacity == 1)
        // The plain style is no style at all.
        widget.setTextStyle(.plain, of: .artist)
        #expect(widget.textStyles.isEmpty)
    }
}

@MainActor @Suite struct ElementBackgroundCornerTests {
    private let widget = WidgetShape(size: CGSize(width: 300, height: 140),
                                     corners: RectangleCornerRadii(topLeading: 20, bottomLeading: 30, bottomTrailing: 40, topTrailing: 50))

    @Test func aBackgroundInTheWidgetsCornerTakesItsCorner() {
        let radii = WidgetLabel<EmptyView>.radii(of: CGRect(x: 200, y: 0, width: 100, height: 30), own: 6, in: widget)
        #expect(radii == RectangleCornerRadii(topLeading: 6, bottomLeading: 6, bottomTrailing: 6, topTrailing: 50))
    }

    @Test func alongOneEdgeOnlyItKeepsItsOwn() {
        let radii = WidgetLabel<EmptyView>.radii(of: CGRect(x: 100, y: 0, width: 100, height: 30), own: 6, in: widget)
        #expect(radii == .uniform(6))
    }

    @Test func aStyleStoredBeforeOverflowExistedDecodes() throws {
        let data = Data(#"{"isBold":true,"maxLines":2}"#.utf8)
        let style = try JSONDecoder().decode(TextStyle.self, from: data)
        #expect(style.isBold && style.maxLines == 2 && style.overflow == .truncate && style.alignment == .leading)
    }
}
