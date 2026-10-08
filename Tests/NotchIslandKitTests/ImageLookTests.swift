import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

@Suite struct ImageLookTests {
    private func widget(_ look: ImageLook) -> IslandWidget {
        var widget = IslandWidget(kind: .nowPlaying, frame: GridRect(column: 0, row: 0, width: 7, height: 3),
                                  options: IslandWidgetKind.nowPlaying.defaultOptions)
        widget.setImageLook(look, of: .artwork)
        return widget
    }

    /// A look is stored with the widget and read back; the plain one, or one on a part that is not
    /// a picture, is not stored at all.
    @Test func aLookIsStoredAndReadBack() throws {
        var stored = widget(ImageLook(keepsShape: true, fit: .fill))
        stored.imageLooks[.trackInfo] = ImageLook(fit: .edges)
        let data = try JSONEncoder().encode(stored)
        let read = try JSONDecoder().decode(IslandWidget.self, from: data)
        #expect(read.imageLook(of: .artwork) == ImageLook(keepsShape: true, fit: .fill))
        #expect(read.imageLooks[.trackInfo] == nil)
        let plain = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(widget(.plain)))
        #expect(plain.imageLooks.isEmpty)
    }

    /// To Edges: as tall as the widget, from its leading edge; Fill: as wide as the widget, centred
    /// on it. The cover is laid out as tall as the inside, `padding` in from the widget's corner.
    @Test func theCoverGrowsToTheEdgesOrOverTheWidget() {
        let inner = CGSize(width: 300, height: 80), padding: CGFloat = 10
        let edges = NowPlayingWidget.placingArtwork(widget(ImageLook(fit: .edges)), inner: inner, padding: padding)
        #expect(edges.scale(of: .artwork) == ElementScale(x: 100.0 / 80, y: 100.0 / 80))
        #expect(edges.offset(of: .artwork) == ElementOffset(x: -10, y: -10))
        let fill = NowPlayingWidget.placingArtwork(widget(ImageLook(fit: .fill)), inner: inner, padding: padding)
        #expect(fill.scale(of: .artwork) == ElementScale(x: 320.0 / 80, y: 320.0 / 80))
        #expect(fill.offset(of: .artwork) == ElementOffset(x: -10, y: -10 + (100 - 320) / 2))
        let own = NowPlayingWidget.placingArtwork(widget(ImageLook(keepsShape: true)), inner: inner, padding: padding)
        #expect(own.scales[.artwork] == nil && own.offsets[.artwork] == nil)
    }

    /// Moved or resized by hand, a grown cover stays where it was drawn, at its own size from then on.
    @Test func aGrownCoverMovedByHandKeepsWhereItWasDrawn() {
        var stored = widget(ImageLook(keepsShape: true, fit: .edges))
        let drawn = NowPlayingWidget.placingArtwork(stored, inner: CGSize(width: 300, height: 80), padding: 10)
        stored.adoptDrawn(.artwork, from: drawn)
        #expect(stored.imageLook(of: .artwork) == ImageLook(keepsShape: true, fit: .own))
        #expect(stored.scales[.artwork] == drawn.scales[.artwork])
        #expect(stored.offsets[.artwork] == drawn.offsets[.artwork])
    }

    /// A cover is cut to the widget only where it reaches past its edges: one grown over it and then
    /// moved by hand (at its own size since) is, one inside the widget is not.
    @Test func aCoverIsCutOnlyWhereItReachesPastTheWidget() {
        let inner = CGSize(width: 300, height: 80), padding: CGFloat = 10
        var stored = widget(ImageLook(fit: .fill))
        stored.adoptDrawn(.artwork, from: NowPlayingWidget.placingArtwork(stored, inner: inner, padding: padding))
        stored.offsets[.artwork]?.x += 40
        #expect(NowPlayingWidget.artworkReachesPast(stored, inner: inner, padding: padding))
        #expect(!NowPlayingWidget.artworkReachesPast(widget(.plain), inner: inner, padding: padding))
        var moved = widget(.plain)
        moved.offsets[.artwork] = ElementOffset(x: 200, y: 0)
        #expect(!NowPlayingWidget.artworkReachesPast(moved, inner: inner, padding: padding))
        moved.offsets[.artwork] = ElementOffset(x: 240, y: 0)
        #expect(NowPlayingWidget.artworkReachesPast(moved, inner: inner, padding: padding))
    }

    /// Keeping its shape, a part resized by a side grows on the other axis too, about its middle.
    @Test func aSideKeepsTheShapeAboutItsMiddle() {
        var resize = ElementResize(id: .artwork, horizontal: 1, vertical: 0, start: CGRect(x: 10, y: 10, width: 40, height: 40),
                                   others: [], bounds: CGSize(width: 400, height: 200), release: 0)
        resize.move(by: CGSize(width: 20, height: 0), keepsRatio: true)
        #expect(resize.frame == CGRect(x: 10, y: 0, width: 60, height: 60))
        var free = ElementResize(id: .artwork, horizontal: 1, vertical: 0, start: CGRect(x: 10, y: 10, width: 40, height: 40),
                                 others: [], bounds: CGSize(width: 400, height: 200), release: 0)
        free.move(by: CGSize(width: 20, height: 0))
        #expect(free.frame == CGRect(x: 10, y: 10, width: 60, height: 40))
    }
}
