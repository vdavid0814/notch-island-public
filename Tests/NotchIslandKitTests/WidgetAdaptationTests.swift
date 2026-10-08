import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct WidgetAdaptationTests {
    /// Now Playing placed at its own size (7 × 3): the title moved and in a box, the line's time moved.
    private func placed(width: Int, height: Int) -> IslandWidget {
        var widget = IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: width, height: height),
                                  options: IslandWidgetKind.nowPlaying.defaultOptions)
        widget.offsets[.trackInfo] = ElementOffset(x: 14, y: 12)
        widget.offsets[.playbackButtons] = ElementOffset(x: 7, y: -6)
        var style = TextStyle()
        style.overflow = .shrink
        style.box = TextStyle.BoxSize(width: 150, height: 30)
        style.maximumSize = 18
        style.isBold = true
        widget.setTextStyle(style, of: .trackInfo)
        var line = ProgressLook()
        line.elapsedOffset = ElementOffset(x: 0, y: 6)
        widget.setProgressLook(line, of: .progress)
        return widget
    }

    /// The design size is stored with the widget and read back.
    @Test func theDesignSizeIsStored() throws {
        var widget = placed(width: 7, height: 3)
        widget.designSize = GridSize(width: 6, height: 2)
        let read = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(widget))
        #expect(read.designSize == GridSize(width: 6, height: 2))
        #expect(placed(width: 7, height: 3).effectiveDesignSize == IslandWidgetKind.nowPlaying.defaultSize)
    }

    /// At its own size nothing changes.
    @Test func atItsOwnSizeNothingChanges() {
        let widget = placed(width: 7, height: 3)
        #expect(widget.adapted(keepsPlacement: true) == widget)
    }

    /// Smaller, laid out alike: moves and boxes go as far as the widget (the texts as their room)
    /// shrinks, the letters as much as the smaller of the two; the looks stay.
    @Test func smallerItShrinksAsOne() {
        var widget = placed(width: 7, height: 3)
        widget.frame.height = 2
        let adapted = widget.adapted(keepsPlacement: true, textWidth: 0.5)
        #expect(adapted.designSize == GridSize(width: 7, height: 2))
        #expect(adapted.offset(of: .trackInfo) == ElementOffset(x: 7, y: 8))
        #expect(adapted.offset(of: .playbackButtons) == ElementOffset(x: 7, y: -4))
        let style = adapted.textStyle(of: .trackInfo)
        #expect(style.box == TextStyle.BoxSize(width: 75, height: 20))
        #expect(style.maximumSize == 9)
        #expect(style.isBold)
        #expect(adapted.progressLook(of: .progress).elapsedOffset == ElementOffset(x: 0, y: 4))
    }

    /// Laid out another way (one row), where the parts were placed means nothing there: they are
    /// where the layout puts them, their looks kept.
    @Test func laidOutAnotherWayThePlacingGoes() {
        var widget = placed(width: 7, height: 3)
        widget.frame.height = 1
        let adapted = widget.adapted(keepsPlacement: false)
        #expect(adapted.offsets.isEmpty)
        let style = adapted.textStyle(of: .trackInfo)
        #expect(style.box == nil && style.maximumSize == nil)
        #expect(style.isBold && style.overflow == .shrink)
        #expect(adapted.progressLook(of: .progress).elapsedOffset == .zero)
    }

    /// The cover beside the texts while they keep 110 pt (on one row from 150 pt wide), the line
    /// from 84 pt tall and never on one row, previous and next from 170 pt wide.
    @Test func whatHasRoom() {
        #expect(NowPlayingWidget.hasRoom(for: .artwork, inner: CGSize(width: 260, height: 110)))
        #expect(!NowPlayingWidget.hasRoom(for: .artwork, inner: CGSize(width: 200, height: 110)))
        #expect(NowPlayingWidget.hasRoom(for: .artwork, inner: CGSize(width: 150, height: 30)))
        #expect(!NowPlayingWidget.hasRoom(for: .progress, inner: CGSize(width: 260, height: 70)))
        #expect(NowPlayingWidget.hasRoom(for: .progress, inner: CGSize(width: 260, height: 90)))
        #expect(!NowPlayingWidget.hasRoom(for: .skipButtons, inner: CGSize(width: 160, height: 90)))
        #expect(NowPlayingWidget.hasRoom(for: .trackInfo, inner: CGSize(width: 40, height: 20)))
    }
}
