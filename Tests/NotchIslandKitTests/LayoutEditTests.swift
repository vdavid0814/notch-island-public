import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

/// The commands of the grid inside a widget: each a pure change of the layout.
@Suite struct LayoutEditTests {
    private let a = ElementID(rawValue: "a"), b = ElementID(rawValue: "b"), c = ElementID(rawValue: "c")

    private func layout(_ rects: [(ElementID, UnitRect)]) -> CustomLayout {
        CustomLayout(authoredSize: CGSize(width: 200, height: 100), grid: InnerGrid(columns: 25, rows: 12),
                     items: rects.map { ElementFrame(id: $0.0, rect: $0.1) })
    }

    private func rect(_ layout: CustomLayout, _ id: ElementID) -> UnitRect { layout.items.first { $0.id == id }!.rect }

    /// An element may be made as large as wanted and reach past the widget's edges; some of it
    /// always stays over the widget.
    @Test func rectanglesAreNotHeldInsideTheWidget() {
        let large = UnitRect(x: -0.5, y: -0.2, width: 3, height: 2).clamped
        #expect(large.width == 3 && large.height == 2 && large.x == -0.5 && large.y == -0.2)
        let away = UnitRect(x: 5, y: -9, width: 0.2, height: 0.2).clamped
        #expect(away.x == 1 - UnitRect.visible && away.y == UnitRect.visible - 0.2)
    }

    /// In front: over everything it overlaps; behind: under it.
    @Test func anElementsLayerIsWhetherItLiesOverWhatItOverlaps() {
        var layout = layout([(a, UnitRect(x: 0, y: 0, width: 0.5, height: 1)), (b, UnitRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)),
                             (c, UnitRect(x: 0.7, y: 0, width: 0.2, height: 0.2))])
        #expect(LayoutEdit.layer(of: b, in: layout) == .front)
        #expect(LayoutEdit.layer(of: a, in: layout) == .behind)
        // Overlapping nothing, it is in front.
        #expect(LayoutEdit.layer(of: c, in: layout) == .front)
        LayoutEdit.setLayer(.front, [a], in: &layout)
        #expect(LayoutEdit.layer(of: a, in: layout) == .front && LayoutEdit.layer(of: b, in: layout) == .behind)
        LayoutEdit.setLayer(.behind, [a], in: &layout)
        #expect(layout.items.first?.id == a)
    }

    /// An element's switch keeps a custom layout in step: off, it goes to the tray in every size's
    /// layout; on, it is back on the widget, even one never laid out there.
    @Test func anElementsSwitchPutsItOnTheWidgetOrInTheTray() {
        var small = layout([(.artwork, UnitRect(x: 0, y: 0, width: 0.4, height: 1))])
        small.parked = [.trackInfo]
        let large = layout([(.artwork, UnitRect(x: 0, y: 0, width: 0.5, height: 1))])
        let short = LayoutClass(height: .short, aspect: .wide), tall = LayoutClass(height: .tall, aspect: .wide)
        var arrangement: ElementArrangement? = .custom(CustomLayouts(authored: short, variants: [short: .custom(small), tall: .custom(large), LayoutClass(height: .medium, aspect: .wide): .automatic]))
        func layouts() -> [CustomLayout] {
            guard case .custom(let all)? = arrangement else { return [] }
            return all.variants.values.compactMap { if case .custom(let layout) = $0 { layout } else { nil } }
        }

        LayoutEdit.setShown(.trackInfo, true, role: .text, in: &arrangement)
        #expect(layouts().count == 2)
        #expect(layouts().allSatisfy { $0.items.contains { $0.id == .trackInfo } && !$0.parked.contains(.trackInfo) })
        LayoutEdit.setShown(.artwork, false, role: .image, in: &arrangement)
        #expect(layouts().allSatisfy { !$0.items.contains { $0.id == .artwork } && $0.parked.contains(.artwork) })
        // The kind's own stacks: nothing to keep in step.
        var automatic: ElementArrangement? = nil
        LayoutEdit.setShown(.trackInfo, true, role: .text, in: &automatic)
        #expect(automatic == nil)
    }

    /// Shown again, an element goes where nothing is: not on the readout across the middle.
    @Test func anElementShownAgainGoesWhereNothingIs() {
        let readout = UnitRect(x: 0.1, y: 0.3, width: 0.8, height: 0.4)
        let free = LayoutEdit.freeSpot(width: 0.35, height: 0.35, in: layout([(a, readout)]))
        let w = min(free.x + free.width, readout.x + readout.width) - max(free.x, readout.x)
        let h = min(free.y + free.height, readout.y + readout.height) - max(free.y, readout.y)
        #expect(w <= 1e-9 || h <= 1e-9)
        #expect(free.x >= 0 && free.y >= 0 && free.x + free.width <= 1 + 1e-9 && free.y + free.height <= 1 + 1e-9)
        // Nothing placed: the middle.
        let middle = LayoutEdit.freeSpot(width: 0.5, height: 0.22, in: layout([]))
        #expect(near(middle.x, 0.25) && near(middle.y, 0.39))
    }

    /// An element laid out as its parts (Now Playing's previous and next) is switched as its parts:
    /// both to the tray, both back, side by side rather than one on the other.
    @Test func anElementOfPartsIsSwitchedAsItsParts() {
        let previous = ElementID.skipButtons.part("previous"), next = ElementID.skipButtons.part("next")
        let size = LayoutClass(height: .short, aspect: .wide)
        var arrangement: ElementArrangement? = .custom(CustomLayouts(authored: size, variants: [size: .custom(layout([
            (previous, UnitRect(x: 0.1, y: 0.6, width: 0.2, height: 0.3)), (next, UnitRect(x: 0.7, y: 0.6, width: 0.2, height: 0.3)),
        ]))]))
        func current() -> CustomLayout? {
            guard case .custom(let all)? = arrangement, case .custom(let layout)? = all.variants[size] else { return nil }
            return layout
        }
        LayoutEdit.setShown(.skipButtons, false, role: .button, parts: [previous, next], in: &arrangement)
        #expect(current()?.items.isEmpty == true)
        #expect(Set(current()?.parked ?? []) == [previous, next])
        LayoutEdit.setShown(.skipButtons, true, role: .button, parts: [previous, next], in: &arrangement)
        let items = current()?.items ?? []
        #expect(Set(items.map(\.id)) == [previous, next])
        #expect(!items.contains { $0.id == .skipButtons })
        if items.count == 2 {
            let a = items[0].rect, b = items[1].rect
            #expect(a.x + a.width <= b.x + 1e-9 || b.x + b.width <= a.x + 1e-9 || a.y + a.height <= b.y + 1e-9 || b.y + b.height <= a.y + 1e-9)
        }
    }

    private func near(_ x: Double, _ y: Double) -> Bool { abs(x - y) < 1e-9 }

    @Test func oneAloneAlignsToTheWidgetSeveralToTheRectangleAroundThem() {
        var one = layout([(a, UnitRect(x: 0.2, y: 0.3, width: 0.2, height: 0.2))])
        LayoutEdit.align([a], .right, in: &one)
        #expect(near(rect(one, a).x, 0.8))
        LayoutEdit.align([a], .centerY, in: &one)
        #expect(near(rect(one, a).y, 0.4))

        var several = layout([(a, UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), (b, UnitRect(x: 0.5, y: 0.4, width: 0.3, height: 0.4)),
                              (c, UnitRect(x: 0.7, y: 0.0, width: 0.1, height: 0.1))])
        LayoutEdit.align([a, b], .left, in: &several)
        #expect(near(rect(several, a).x, 0.1) && near(rect(several, b).x, 0.1))
        LayoutEdit.align([a, b], .bottom, in: &several)
        #expect(near(rect(several, a).y, 0.6) && near(rect(several, b).y, 0.4))
        LayoutEdit.align([a, b], .centerX, in: &several)
        #expect(near(rect(several, a).x + 0.1, rect(several, b).x + 0.15))
        // What was not picked stays.
        #expect(rect(several, c) == UnitRect(x: 0.7, y: 0.0, width: 0.1, height: 0.1))
    }

    @Test func distributingGivesEqualGapsAndKeepsTheOuterTwo() {
        var row = layout([(a, UnitRect(x: 0.0, y: 0.1, width: 0.1, height: 0.2)), (b, UnitRect(x: 0.15, y: 0.1, width: 0.2, height: 0.2)),
                          (c, UnitRect(x: 0.8, y: 0.1, width: 0.2, height: 0.2))])
        LayoutEdit.distribute([a, b, c], .horizontal, in: &row)
        #expect(near(rect(row, a).x, 0) && near(rect(row, c).x, 0.8))
        let gap1 = rect(row, b).x - (rect(row, a).x + rect(row, a).width)
        let gap2 = rect(row, c).x - (rect(row, b).x + rect(row, b).width)
        #expect(near(gap1, gap2) && near(gap1, 0.25))
        // Two are not distributed.
        var two = layout([(a, UnitRect(x: 0.0, y: 0, width: 0.1, height: 0.1)), (b, UnitRect(x: 0.5, y: 0, width: 0.1, height: 0.1))])
        let before = two
        LayoutEdit.distribute([a, b], .horizontal, in: &two)
        #expect(two == before)
        // Down the other axis.
        var column = layout([(a, UnitRect(x: 0, y: 0.0, width: 0.1, height: 0.1)), (b, UnitRect(x: 0, y: 0.2, width: 0.1, height: 0.1)),
                             (c, UnitRect(x: 0, y: 0.9, width: 0.1, height: 0.1))])
        LayoutEdit.distribute([a, b, c], .vertical, in: &column)
        #expect(near(rect(column, b).y, 0.45))
    }

    @Test func orderMovesThePickedAndKeepsTheirOwnOrder() {
        let d = ElementID(rawValue: "d")
        let base = layout([a, b, c, d].map { ($0, UnitRect(x: 0, y: 0, width: 0.1, height: 0.1)) })
        func order(_ ids: Set<ElementID>, _ order: LayoutEdit.Order) -> [ElementID] {
            var layout = base
            LayoutEdit.reorder(ids, order, in: &layout)
            return layout.items.map(\.id)
        }
        #expect(order([a], .front) == [b, c, d, a])
        #expect(order([d], .back) == [d, a, b, c])
        #expect(order([a], .forward) == [b, a, c, d])
        #expect(order([d], .backward) == [a, b, d, c])
        #expect(order([a, b], .forward) == [c, a, b, d])
        #expect(order([c, d], .backward) == [a, c, d, b])
        #expect(order([a, c], .front) == [b, d, a, c])
        // Already there: nothing moves.
        #expect(order([d], .forward) == [a, b, c, d] && order([a], .backward) == [a, b, c, d])
    }

    /// Moved together by the same, past the widget's edge if wanted; some of each stays over it.
    @Test func movingKeepsThePickedTogether() {
        var layout = layout([(a, UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)), (b, UnitRect(x: 0.6, y: 0.5, width: 0.3, height: 0.3))])
        LayoutEdit.move([a, b], dx: 0.2, dy: 0.1, in: &layout)
        #expect(near(rect(layout, b).x, 0.8) && near(rect(layout, a).x, 0.3))
        #expect(near(rect(layout, b).y, 0.6) && near(rect(layout, a).y, 0.2))
        LayoutEdit.move([a], dx: -5, dy: -5, in: &layout)
        #expect(near(rect(layout, a).x, UnitRect.visible - 0.2) && near(rect(layout, a).y, UnitRect.visible - 0.2))
    }

    @Test func hidingParksTheKindsOwnAndRemovesADecoration() {
        var layout = layout([(a, UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))])
        let label = LayoutEdit.add(.label("Hi"), at: UnitRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), in: &layout)
        #expect(layout.items.map(\.id) == [a, label] && layout.decorations[label] == .label("Hi"))
        LayoutEdit.hide([a, label], in: &layout)
        #expect(layout.items.isEmpty)
        #expect(layout.parked == [a])
        #expect(layout.decorations.isEmpty)
        // Back from the tray, in front.
        LayoutEdit.place(a, at: UnitRect(x: 0.9, y: 0.9, width: 0.3, height: 0.3), in: &layout)
        #expect(layout.parked.isEmpty && layout.items.map(\.id) == [a])
        // Where it was put: it may reach past the widget's edge.
        #expect(near(rect(layout, a).x, 0.9) && near(rect(layout, a).y, 0.9))
        LayoutEdit.place(a, at: UnitRect(x: 0, y: 0, width: 0.1, height: 0.1), in: &layout)
        #expect(layout.items.count == 1)
    }

    @Test func onlyDecorationsAreDuplicated() {
        var layout = layout([(a, UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))])
        let shape = LayoutEdit.add(.shape(.circle), at: UnitRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), in: &layout)
        LayoutEdit.setLocked(true, [shape], in: &layout)
        let copies = LayoutEdit.duplicate([a, shape], in: &layout)
        #expect(copies.count == 1 && copies[shape] != nil && copies[a] == nil)
        let copy = copies[shape]!
        #expect(copy.isCustom && copy != shape)
        #expect(layout.decorations[copy] == .shape(.circle))
        #expect(layout.items.last?.id == copy)
        #expect(near(rect(layout, copy).x, 0.44) && near(rect(layout, copy).y, 0.44))
        // A copy can be moved at once, and keeps the original's shape.
        #expect(layout.items.last?.locked == false && layout.items.last?.keepsAspect == true)
    }

    @Test func aDividerStretchesAlongItsLine() {
        var layout = layout([])
        let across = LayoutEdit.add(.divider(.horizontal), at: UnitRect(x: 0.1, y: 0.5, width: 0.8, height: 0.02), in: &layout)
        let down = LayoutEdit.add(.divider(.vertical), at: UnitRect(x: 0.5, y: 0.1, width: 0.02, height: 0.8), in: &layout)
        #expect(layout.items.first { $0.id == across }?.pinX == .stretch)
        #expect(layout.items.first { $0.id == down }?.pinY == .stretch)
    }

    @Test func flippingMirrorsEveryElementAndItsPin() {
        var layout = layout([(a, UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.2))])
        LayoutEdit.setPins(x: .leading, y: .trailing, [a], in: &layout)
        LayoutEdit.flipHorizontally(&layout)
        #expect(near(rect(layout, a).x, 0.6) && near(rect(layout, a).y, 0.2))
        #expect(layout.items[0].pinX == .trailing && layout.items[0].pinY == .trailing)
        LayoutEdit.flipHorizontally(&layout)
        #expect(near(rect(layout, a).x, 0.1) && layout.items[0].pinX == .leading)
    }

    /// The grid is an aid: another density moves nothing.
    @Test func theGridsDensityMovesNothing() {
        var layout = layout([(a, UnitRect(x: 0.13, y: 0.27, width: 0.31, height: 0.22))])
        let items = layout.items
        for density in LayoutEdit.Density.allCases {
            LayoutEdit.setDensity(density, in: &layout)
            #expect(layout.items == items)
            #expect(LayoutEdit.density(of: layout) == density)
            #expect(layout.grid.columns <= density.limit.columns && layout.grid.rows <= density.limit.rows)
            #expect(layout.grid == density.grid(for: layout.authoredSize))
        }
    }

    /// Laid out again for the size it is drawn at, every element is where it was drawn, and a
    /// layout already authored there is untouched.
    @Test func bakingKeepsEveryElementWhereItIsDrawn() {
        var layout = layout([(a, UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)), (b, UnitRect(x: 0.6, y: 0.1, width: 0.3, height: 0.2))])
        layout.authoredPadding = 6
        LayoutEdit.setPins(x: .trailing, y: .center, [b], in: &layout)
        #expect(LayoutEdit.baked(layout, size: CGSize(width: 200, height: 100), padding: 6, scale: 1) == layout)
        for size in [CGSize(width: 320, height: 100), CGSize(width: 150, height: 180), CGSize(width: 90, height: 60)] {
            for scale in [CGFloat(0.85), 1, 1.15] {
                for contentScale in [CGFloat(1), 0.8] {
                    let drawn = ElementLayoutGeometry.reflow(layout, to: size, padding: 6, contentScale: contentScale)
                    let baked = LayoutEdit.baked(layout, size: size, padding: 6, scale: scale, contentScale: contentScale)
                    #expect(baked.authoredSize == CGSize(width: size.width / scale, height: size.height / scale))
                    let again = ElementLayoutGeometry.reflow(baked, to: size, padding: 6)
                    for (before, after) in zip(drawn, again) {
                        #expect(before.id == after.id)
                        #expect(abs(before.frame.minX - after.frame.minX) < 0.01 && abs(before.frame.minY - after.frame.minY) < 0.01)
                        #expect(abs(before.frame.width - after.frame.width) < 0.01 && abs(before.frame.height - after.frame.height) < 0.01)
                    }
                    #expect(baked.items.map(\.pinX) == layout.items.map(\.pinX))
                }
            }
        }
    }

    /// What an element draws at a size of its own is drawn at that size wherever the layout is baked:
    /// its natural size follows the scale the whole layout is drawn at.
    @Test func bakingKeepsTheSizeAnElementDrawsAt() {
        var layout = layout([(a, UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))])
        layout.authoredPadding = 6
        layout.items[0].natural = CGSize(width: 60, height: 40)
        for size in [CGSize(width: 320, height: 100), CGSize(width: 150, height: 180)] {
            for scale in [CGFloat(0.85), 1] {
                let drawnNatural = ResolvedArrangement.resolve(layout, size: size, padding: 6).items[0].natural
                let baked = LayoutEdit.baked(layout, size: size, padding: 6, scale: scale)
                let again = ResolvedArrangement.resolve(baked, size: size, padding: 6).items[0].natural
                #expect(drawnNatural != nil && again != nil)
                #expect(abs((drawnNatural?.width ?? 0) - (again?.width ?? 1)) < 0.01 && abs((drawnNatural?.height ?? 0) - (again?.height ?? 1)) < 0.01)
            }
        }
    }

    @Test func theSpacesAroundAnElementAreToWhatLiesInItsWay() {
        let size = CGSize(width: 200, height: 100)
        let rect = CGRect(x: 80, y: 40, width: 40, height: 20)
        // Alone: to the widget's edges.
        let alone = SpacingGaps(rect: rect, others: [], size: size)
        #expect(alone.marks.map(\.length).sorted() == [40, 40, 80, 80])
        // A neighbour on its row on the left, one above that does not overlap it (ignored).
        let gaps = SpacingGaps(rect: rect, others: [CGRect(x: 10, y: 45, width: 50, height: 10), CGRect(x: 0, y: 0, width: 30, height: 10)], size: size)
        #expect(gaps.marks.contains { $0.length == 20 && $0.to.x == 80 })
        #expect(gaps.marks.contains { $0.length == 40 && $0.to.y == 40 })
        // Touching: no mark.
        let touching = SpacingGaps(rect: rect, others: [CGRect(x: 120, y: 40, width: 20, height: 20)], size: size)
        #expect(!touching.marks.contains { $0.from.x == 120 })
    }
}
