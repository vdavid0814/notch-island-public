import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct WidgetFigureTests {
    private func widget() -> IslandWidget {
        IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                     options: IslandWidgetKind.nowPlaying.defaultOptions)
    }

    /// Shapes are stored with the widget, moved and sized like its parts, and read back in order.
    @Test func shapesAreStoredMovedAndSized() throws {
        var stored = widget()
        let ring = WidgetFigure.new(.ring), arrow = WidgetFigure.new(.twoWayArrow)
        stored.figures = [ring, arrow]
        stored.figures[1].color = .artwork
        stored.setOffset(ElementOffset(x: 20, y: -8), of: ring.id)
        stored.scales[arrow.id] = ElementScale(x: 2, y: 1.5)
        let read = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(stored))
        #expect(read.figures == stored.figures)
        #expect(read.offset(of: ring.id) == ElementOffset(x: 20, y: -8))
        #expect(read.scale(of: arrow.id) == ElementScale(x: 2, y: 1.5))
        #expect(read.movableElements.suffix(2) == [ring.id, arrow.id])
    }

    /// A line's ends and a square's corners, and a square solid, are stored; a shape saved before
    /// they existed reads back as it was drawn (a round line, a square a little rounded, empty).
    @Test func cornersAndFillAreStored() throws {
        var square = WidgetFigure.new(.square)
        square.corners = .sharp
        square.isFilled = true
        let read = try JSONDecoder().decode(WidgetFigure.self, from: JSONEncoder().encode(square))
        #expect(read.effectiveCorners == .sharp && read.isFilled)
        let old = try JSONDecoder().decode(WidgetFigure.self, from: Data(#"{"id":"figure.ab12cd34","kind":"line"}"#.utf8))
        #expect(old.effectiveCorners == .round && !old.isFilled && old.color == .automatic)
        #expect(WidgetFigure.new(.square).effectiveCorners == .rounded)
        #expect(WidgetFigure.Corners.round.radius(CGSize(width: 48, height: 4), line: true) == 2)
        #expect(WidgetFigure.Corners.sharp.radius(CGSize(width: 28, height: 28), line: false) == 0)
    }

    /// A shape's turn is stored, kept within -180…180, and none in a shape saved before turns.
    @Test func aTurnIsStoredWithinAHalfTurnEitherWay() throws {
        var arrow = WidgetFigure.new(.arrow)
        arrow.rotation = WidgetFigure.normalized(270)
        #expect(arrow.rotation == -90)
        #expect(WidgetFigure.normalized(-190) == 170 && WidgetFigure.normalized(.nan) == 0 && WidgetFigure.normalized(540) == 180)
        let read = try JSONDecoder().decode(WidgetFigure.self, from: JSONEncoder().encode(arrow))
        #expect(read.rotation == -90)
        let old = try JSONDecoder().decode(WidgetFigure.self, from: Data(#"{"id":"figure.ab12cd34","kind":"arrow"}"#.utf8))
        #expect(old.rotation == 0)
    }

    /// A shape taken off goes with where it was moved and its size; one too many, or one twice,
    /// is not kept.
    @Test func aShapeTakenOffLeavesNothing() {
        var stored = widget()
        let line = WidgetFigure.new(.line)
        stored.figures = [line, line] + (0..<WidgetFigure.limit).map { _ in WidgetFigure.new(.disc) }
        stored.setOffset(ElementOffset(x: 4, y: 4), of: line.id)
        stored.sanitize()
        #expect(stored.figures.count == WidgetFigure.limit)
        #expect(stored.figures.filter { $0.id == line.id }.count == 1)
        stored.removeFigure(line.id)
        #expect(stored.figure(line.id) == nil && stored.offsets[line.id] == nil)
    }

    /// Delete on picked parts: a shape goes, a part with a switch is switched off (a pair's by
    /// its pair's switch), one without stays.
    @Test func deleteTakesShapesOffAndSwitchesPartsOff() {
        var stored = widget()
        let ring = WidgetFigure.new(.ring)
        stored.figures = [ring]
        stored.options.insert(.seekButtons)
        stored.delete([ring.id, .nextButton, .seekBackButton, .artwork])
        #expect(stored.figures.isEmpty)
        #expect(!stored.shows(.skipButtons) && !stored.shows(.seekButtons) && !stored.shows(.artwork))
        #expect(stored.shows(.trackInfo) && stored.shows(.playbackButtons))
        #expect(stored.switchElement(for: .previousButton) == .skipButtons)
    }

    /// ⌘-click picks parts together and lets them go; one left is picked alone.
    @MainActor @Test func commandClickPicksTogether() {
        let editing = ElementEditing()
        editing.selected = .artwork
        editing.toggle(.nextButton)
        #expect(editing.group == [.artwork, .nextButton] && editing.selected == .nextButton)
        editing.toggle(.trackInfo)
        #expect(editing.picked == [.artwork, .nextButton, .trackInfo])
        editing.toggle(.trackInfo)
        editing.toggle(.nextButton)
        #expect(editing.group.isEmpty && editing.picked == [.artwork])
    }

    /// Back and forward are off in a new widget, jump 15 s unless set, and only as far as offered.
    @Test func backAndForwardAreOffAndJumpAsSet() throws {
        var stored = widget()
        #expect(!stored.shows(.seekButtons))
        #expect(stored.effectiveSeekSeconds == 15)
        stored.seekSeconds = 30
        #expect(try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(stored)).effectiveSeekSeconds == 30)
        stored.seekSeconds = 7
        stored.sanitize()
        #expect(stored.seekSeconds == nil)
        #expect(NowPlayingWidget.seekSymbol(back: true, seconds: 30) == "gobackward.30")
    }

    /// With back and forward the buttons get smaller until all five fit beside the cover; where
    /// they would be under 11 pt, back and forward give way. Without them nothing changes.
    @Test func backAndForwardFitTheRow() {
        var stored = widget()
        let inner = CGSize(width: 278, height: 116)
        #expect(NowPlayingWidget.controlRow(stored, inner: inner) == (20, false))
        stored.options.insert(.seekButtons)
        let row = NowPlayingWidget.controlRow(stored, inner: inner)
        #expect(row.showsSeek && row.points < 20 && row.points >= 11)
        #expect(!NowPlayingWidget.controlRow(stored, inner: CGSize(width: 120, height: 30)).showsSeek)
    }
}
