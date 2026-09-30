import CoreGraphics
import Testing
@testable import NotchIslandKit

/// A custom layout drawn at other sizes: exact scaling, pins, nothing ever leaving the widget, size
/// classes and the editing grid.
@Suite struct ElementLayoutTests {
    private func layout(_ items: [ElementFrame], authored: CGSize = CGSize(width: 200, height: 100)) -> CustomLayout {
        CustomLayout(authoredSize: authored, grid: InnerGrid(authoredSize: authored), items: items)
    }

    private func frame(_ layout: CustomLayout, _ size: CGSize, padding: CGFloat = 0, contentScale: CGFloat = 1) -> CGRect {
        ElementLayoutGeometry.reflow(layout, to: size, padding: padding, contentScale: contentScale)[0].frame
    }

    private func expectClose(_ a: CGRect, _ b: CGRect, _ note: String = "") {
        let close = abs(a.minX - b.minX) < 1e-9 && abs(a.minY - b.minY) < 1e-9 && abs(a.width - b.width) < 1e-9
            && abs(a.height - b.height) < 1e-9
        #expect(close, "\(note) \(a) vs \(b)")
    }

    @Test func scalesExactlyAtTheAuthoredAspect() {
        let rect = UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.5)
        for pin in Pin.allCases {
            let layout = layout([ElementFrame(id: .artwork, rect: rect, pinX: pin, pinY: pin)])
            for k in [0.5, 1, 1.5, 3] as [CGFloat] {
                expectClose(frame(layout, CGSize(width: 200 * k, height: 100 * k)),
                            CGRect(x: 20 * k, y: 20 * k, width: 60 * k, height: 50 * k), "\(pin) ×\(k)")
            }
        }
    }

    /// Twice as wide: 200 pt more room across, spent as each pin says.
    @Test func pinsSpendTheLeftover() {
        let rect = UnitRect(x: 0.25, y: 0, width: 0.25, height: 1)
        let size = CGSize(width: 400, height: 100)
        let expected: [Pin: CGRect] = [
            .leading: CGRect(x: 50, y: 0, width: 50, height: 100),
            .trailing: CGRect(x: 250, y: 0, width: 50, height: 100),
            .center: CGRect(x: 150, y: 0, width: 50, height: 100),
            .stretch: CGRect(x: 50, y: 0, width: 250, height: 100),
            .scale: CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        for pin in Pin.allCases {
            expectClose(frame(layout([ElementFrame(id: .artwork, rect: rect, pinX: pin)]), size), expected[pin]!, "\(pin)")
        }
    }

    @Test func contentScaleShrinksAndNeverGrows() {
        let layout = layout([ElementFrame(id: .artwork, rect: UnitRect(x: 0, y: 0, width: 1, height: 1), pinX: .leading, pinY: .leading)])
        expectClose(frame(layout, CGSize(width: 200, height: 100), contentScale: 0.5), CGRect(x: 0, y: 0, width: 100, height: 50))
        expectClose(frame(layout, CGSize(width: 200, height: 100), contentScale: 1.5), CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    /// Every pin keeps the content scale: a scaled element grows with its axis and is then drawn at
    /// the content scale, centred in what that leaves.
    @Test func contentScaleHoldsForEveryPin() {
        let rect = UnitRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let expected: [CGSize: [Pin: CGRect]] = [
            CGSize(width: 200, height: 100): [
                .leading: CGRect(x: 25, y: 12.5, width: 50, height: 25),
                .trailing: CGRect(x: 125, y: 62.5, width: 50, height: 25),
                .center: CGRect(x: 75, y: 37.5, width: 50, height: 25),
                .stretch: CGRect(x: 25, y: 12.5, width: 150, height: 75),
                .scale: CGRect(x: 75, y: 37.5, width: 50, height: 25),
            ],
            // Twice as wide: a scaled element twice as wide as a held one.
            CGSize(width: 400, height: 100): [
                .leading: CGRect(x: 25, y: 12.5, width: 50, height: 25),
                .trailing: CGRect(x: 325, y: 62.5, width: 50, height: 25),
                .center: CGRect(x: 175, y: 37.5, width: 50, height: 25),
                .stretch: CGRect(x: 25, y: 12.5, width: 350, height: 75),
                .scale: CGRect(x: 150, y: 37.5, width: 100, height: 25),
            ],
        ]
        for (size, frames) in expected {
            for pin in Pin.allCases {
                expectClose(frame(layout([ElementFrame(id: .artwork, rect: rect, pinX: pin, pinY: pin)]), size, contentScale: 0.5),
                            frames[pin]!, "\(pin) \(size)")
            }
        }
    }

    /// The padding band keeps its width: an element on the padding line stays on it, one on the edge
    /// stays on the edge.
    @Test func thePaddingLineHolds() {
        let padding: CGFloat = 6
        let authored = CGSize(width: 200, height: 100)
        let inside = UnitRect(CGRect(x: 6, y: 6, width: 60, height: 88), in: authored)
        let bleeding = UnitRect(CGRect(x: 0, y: 0, width: 80, height: 100), in: authored)
        for size in [CGSize(width: 120, height: 44), CGSize(width: 300, height: 140), CGSize(width: 90, height: 90)] {
            for pin in Pin.allCases {
                let text = frame(layout([ElementFrame(id: .trackInfo, rect: inside, pinX: pin, pinY: pin)]), size, padding: padding)
                #expect(ElementLayoutGeometry.safeRect(in: size, padding: padding).insetBy(dx: -1e-9, dy: -1e-9).contains(text))
                let cover = frame(layout([ElementFrame(id: .artwork, rect: bleeding, pinX: .leading, pinY: .stretch)]), size, padding: padding)
                #expect(abs(cover.minX) < 1e-9 && abs(cover.minY) < 1e-9 && abs(cover.maxY - size.height) < 1e-9)
            }
        }
    }

    /// Laid out with one padding and drawn with another: the authored band maps onto the drawn one,
    /// so what sat on the padding line sits on the new line, and the inside scales from line to line.
    @Test func theAuthoredPaddingMapsOntoTheDrawnOne() {
        let authored = CGSize(width: 200, height: 100)
        var layout = layout([
            ElementFrame(id: .trackInfo, rect: UnitRect(CGRect(x: 6, y: 6, width: 94, height: 88), in: authored), pinX: .leading, pinY: .leading),
            ElementFrame(id: .artwork, rect: UnitRect(CGRect(x: 3, y: 0, width: 50, height: 100), in: authored), pinX: .leading, pinY: .leading),
        ], authored: authored)
        layout.authoredPadding = 6
        let placed = ElementLayoutGeometry.reflow(layout, to: authored, padding: 2)
        // The inside, 188 × 88 authored, is 196 × 96 drawn: u = min(196/188, 96/88).
        let u = min(196.0 / 188, 96.0 / 88)
        expectClose(placed[0].frame, CGRect(x: 2, y: 2, width: 94 * u, height: 88 * u), "text")
        // Halfway into the authored band is halfway into the drawn one.
        #expect(abs(placed[1].frame.minX - 1) < 1e-9 && abs(placed[1].frame.minY) < 1e-9, "\(placed[1].frame)")
    }

    /// 500 random layouts at random sizes, pins and paddings: every element inside the widget stays
    /// inside it, and every one inside the padding stays inside that.
    @Test func nothingEverLeavesTheWidget() {
        var random = SeededRandom(seed: 0x5EED_0006)
        for index in 0..<500 {
            let authored = CGSize(width: random.next(in: 20...400), height: random.next(in: 20...200))
            let size = CGSize(width: random.next(in: 10...600), height: random.next(in: 10...300))
            // A widget is never smaller than twice its padding; the one it was laid out with may differ.
            let padding = CGFloat(random.next(in: 0...Double(min(12, size.width / 2, size.height / 2))))
            let authoredPadding = index.isMultiple(of: 3) ? padding
                : CGFloat(random.next(in: 0...Double(min(12, authored.width / 2, authored.height / 2))))
            let items = (0..<Int(random.next(in: 1...8))).map { item -> ElementFrame in
                let width = random.next(in: UnitRect.minimumSide...1), height = random.next(in: UnitRect.minimumSide...1)
                let rect = UnitRect(x: random.next(in: 0...(1 - width)), y: random.next(in: 0...(1 - height)), width: width, height: height)
                return ElementFrame(id: ElementID(rawValue: "e\(item)"), rect: rect, pinX: Pin.allCases[Int(random.next(in: 0...4.999))],
                                    pinY: Pin.allCases[Int(random.next(in: 0...4.999))], keepsAspect: random.next(in: 0...1) < 0.3)
            }
            let layout = CustomLayout(authoredSize: authored, grid: InnerGrid(authoredSize: authored), items: items,
                                      authoredPadding: authoredPadding)
            let contentScale = CGFloat(random.next(in: 0.5...1.5))
            let widget = CGRect(origin: .zero, size: size).insetBy(dx: -1e-9, dy: -1e-9)
            let safeAuthored = ElementLayoutGeometry.safeRect(in: authored, padding: authoredPadding)
            let safe = ElementLayoutGeometry.safeRect(in: size, padding: padding).insetBy(dx: -1e-9, dy: -1e-9)
            for (item, placed) in zip(items, ElementLayoutGeometry.reflow(layout, to: size, padding: padding, contentScale: contentScale)) {
                #expect(placed.frame.width >= 0 && placed.frame.height >= 0, "layout \(index)")
                #expect(widget.contains(placed.frame), "layout \(index): \(placed.frame) outside \(size)")
                if safeAuthored.insetBy(dx: -1e-9, dy: -1e-9).contains(item.rect.rect(in: authored)) {
                    #expect(safe.contains(placed.frame), "layout \(index): \(placed.frame) outside the padding of \(size)")
                }
            }
        }
    }

    @Test func keepsAspectInsideItsReflowedRect() {
        let layout = layout([ElementFrame(id: .artwork, rect: UnitRect(x: 0, y: 0, width: 0.5, height: 1), pinX: .scale, pinY: .scale,
                                          keepsAspect: true)])
        // Authored 100 × 100: a square, drawn in the 200 × 100 its pins give it.
        expectClose(frame(layout, CGSize(width: 400, height: 100)), CGRect(x: 50, y: 0, width: 100, height: 100))
    }

    // MARK: - Size classes

    @Test func sizeClassesFollowTheWidgetsShape() {
        #expect(LayoutClass(size: CGSize(width: 138, height: 42), scale: 1) == LayoutClass(height: .short, aspect: .wide))
        #expect(LayoutClass(size: CGSize(width: 90, height: 92), scale: 1) == LayoutClass(height: .medium, aspect: .balanced))
        #expect(LayoutClass(size: CGSize(width: 42, height: 144), scale: 1) == LayoutClass(height: .tall, aspect: .narrow))
        // At a larger island the same widget is the same class.
        #expect(LayoutClass(size: CGSize(width: 90 * 1.3, height: 92 * 1.3), scale: 1.3) == LayoutClass(height: .medium, aspect: .balanced))
        let name = LayoutClass(height: .tall, aspect: .wide).name
        #expect(LayoutClass(name: name) == LayoutClass(height: .tall, aspect: .wide))
    }

    @Test func aClassWithoutItsOwnLayoutReflowsTheNearest() {
        let authored = LayoutClass(height: .medium, aspect: .wide)
        let other = LayoutClass(height: .short, aspect: .balanced)
        let a = layout([ElementFrame(id: .artwork, rect: UnitRect(x: 0, y: 0, width: 0.5, height: 1))])
        let b = layout([ElementFrame(id: .trackInfo, rect: UnitRect(x: 0, y: 0, width: 1, height: 0.5))])
        let automaticHere = LayoutClass(height: .tall, aspect: .narrow)
        let layouts = CustomLayouts(authored: authored, variants: [authored: .custom(a), other: .custom(b), automaticHere: .automatic])
        #expect(layouts.resolve(authored) == .custom(a, source: authored))
        #expect(layouts.resolve(automaticHere) == .automatic)
        // One step from each: the authored one wins the tie.
        #expect(layouts.resolve(LayoutClass(height: .short, aspect: .wide)) == .custom(a, source: authored))
        #expect(layouts.resolve(LayoutClass(height: .short, aspect: .narrow)) == .custom(b, source: other))
        #expect(CustomLayouts(authored: authored, variants: [:]).resolve(authored) == .automatic)
    }

    // MARK: - The editing grid

    @Test func theDefaultGridIsEightPointCells() {
        #expect(InnerGrid(authoredSize: CGSize(width: 200, height: 100)) == InnerGrid(columns: 24, rows: 12))
        #expect(InnerGrid(authoredSize: CGSize(width: 96, height: 44)) == InnerGrid(columns: 12, rows: 6))
        #expect(InnerGrid(authoredSize: CGSize(width: 10, height: 4)) == InnerGrid(columns: 2, rows: 1))
    }

    @Test func unitsAndCellsRoundTrip() {
        var random = SeededRandom(seed: 42)
        for _ in 0..<200 {
            let grid = InnerGrid(columns: Int(random.next(in: 2...24)), rows: Int(random.next(in: 1...12)))
            let rect = UnitRect(x: random.next(in: 0...0.5), y: random.next(in: 0...0.5), width: random.next(in: 0.02...0.5),
                                height: random.next(in: 0.02...0.5))
            let back = grid.unit(grid.cells(rect))
            #expect(abs(back.x - rect.x) < 1e-12 && abs(back.y - rect.y) < 1e-12 && abs(back.width - rect.width) < 1e-12
                && abs(back.height - rect.height) < 1e-12)
            let size = CGSize(width: random.next(in: 20...400), height: random.next(in: 20...200))
            let points = UnitRect(rect.rect(in: size), in: size)
            #expect(abs(points.x - rect.x) < 1e-12 && abs(points.width - rect.width) < 1e-12)
        }
        let grid = InnerGrid(columns: 4, rows: 2)
        #expect(grid.cells(UnitRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5)) == CellRect(column: 1, row: 1, width: 2, height: 1))
        #expect(grid.columnLines == [0, 0.25, 0.5, 0.75, 1])
    }

    @Test func onlyImagesLinesDividersAndShapesBleed() {
        #expect(ElementRole.allCases.filter(\.mayBleed) == [.image, .line])
        #expect(Decoration.divider(.horizontal).mayBleed && Decoration.shape(.circle).mayBleed)
        #expect(!Decoration.label("Hi").mayBleed && !Decoration.symbol("star").mayBleed)
        let size = CGSize(width: 100, height: 50)
        #expect(ElementLayoutGeometry.bounds(mayBleed: true, in: size, padding: 6) == CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(ElementLayoutGeometry.bounds(mayBleed: false, in: size, padding: 6) == CGRect(x: 6, y: 6, width: 88, height: 38))
    }
}

/// A small deterministic generator (SplitMix64), so a failing fuzz case can be replayed.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextBits() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(nextBits() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}
