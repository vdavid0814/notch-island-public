import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

/// The fitting engine: fonts measured as SwiftUI draws them, the largest type that fits, and plans
/// that keep fixed sizes, order S < M < L and never overflow.
@Suite struct WidgetFitTests {
    // MARK: - Typography

    /// SwiftUI's own layout of a line, at 2× like the Mac's display.
    private func drawn(_ text: String, _ font: Font, tracking: CGFloat = 0) -> CGSize {
        let renderer = ImageRenderer(content: Text(text).font(font).tracking(tracking).fixedSize())
        renderer.scale = 2
        return renderer.nsImage?.size ?? .zero
    }

    /// A remembered measurement is the measurement: the size that fits comes out exactly as
    /// measuring the text afresh gives it, the first time and again.
    @Test func aRememberedTextSizeIsTheMeasuredOne() {
        func measured(_ text: String, _ width: CGFloat, _ weight: NSFont.Weight, rounded: Bool, digits: Bool) -> CGFloat {
            var font = digits ? NSFont.monospacedDigitSystemFont(ofSize: 100, weight: weight) : NSFont.systemFont(ofSize: 100, weight: weight)
            if rounded, let descriptor = font.fontDescriptor.withDesign(.rounded) {
                font = NSFont(descriptor: descriptor, size: 100) ?? font
            }
            return 100 * width / (text as NSString).size(withAttributes: [.font: font]).width * 0.97
        }
        for text in ["5:00", "1:02:03", "Drop files here", "72%", "Midnight City"] {
            for (weight, rounded, digits) in [(NSFont.Weight.regular, true, true), (.semibold, false, false), (.medium, true, false)] {
                for width in [40.0, 97.5, 180] {
                    let expected = measured(text, width, weight, rounded: rounded, digits: digits)
                    for pass in ["first", "again"] {
                        let size = WidgetType.size(fitting: text, in: width, weight: weight, rounded: rounded, monospacedDigits: digits)
                        #expect(size == expected, "\(text) \(weight) \(rounded) \(digits) \(width), \(pass)")
                    }
                }
            }
        }
    }

    /// The kinds' default type draws the same through `Font(CTFont)` as through `Font.system`, so
    /// the default look keeps its pixels on the engine's fonts.
    @Test(arguments: [FontDesignChoice.standard, .rounded, .serif, .monospaced])
    func ctFontDrawsLikeTheSystemFont(_ design: FontDesignChoice) {
        let swiftDesign: Font.Design = switch design {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
        for weight in [FontWeightChoice.regular, .semibold, .bold] {
            let swiftWeight: Font.Weight = weight == .regular ? .regular : weight == .semibold ? .semibold : .bold
            for points in [9.0, 11, 13, 15, 17, 22, 34] as [CGFloat] {
                let spec = TypeSpec(points: points, design: design, weight: weight)
                for text in ["Unknown Title", "100%", "88:88"] {
                    let engine = drawn(text, WidgetTypography.font(spec))
                    let system = drawn(text, .system(size: points, weight: swiftWeight, design: swiftDesign))
                    #expect(engine == system, "\(design) \(weight) \(points) \(text): \(engine) vs \(system)")
                }
            }
        }
    }

    /// What is measured is never less than what SwiftUI draws, and not much more.
    @Test func measuresWhatSwiftUIDraws() {
        for design in FontDesignChoice.allCases {
            for spec in [TypeSpec(points: 0, design: design), TypeSpec(points: 0, design: design, weight: .bold, italic: true),
                         TypeSpec(points: 0, design: design, width: .condensed, tracking: 1.5, textCase: .uppercase)] {
                for points in stride(from: CGFloat(6.0), through: 60, by: 3.5) {
                    let spec = spec.at(points)
                    for text in ["Nothing Playing", "88h 88m left", "-88.8 W"] {
                        let size = drawn(spec.cased(text), WidgetTypography.font(spec), tracking: spec.tracking)
                        let width = WidgetTypography.width(text, spec, scale: 2)
                        let height = WidgetTypography.lineHeight(spec)
                        #expect(width >= size.width && width <= size.width + 1.5, "\(spec) \(text): \(width) vs \(size.width)")
                        #expect(height >= size.height && height <= size.height + 2, "\(spec) \(text): \(height) vs \(size.height)")
                    }
                }
            }
        }
    }

    @Test func fontsCarryEveryChoice() {
        let regular = TypeSpec(points: 20, italic: true)
        var bold = regular
        bold.weight = .bold
        #expect(WidgetTypography.nsFont(regular).fontDescriptor.symbolicTraits.contains(.italic))
        #expect(WidgetTypography.width("Nothing Playing", bold, scale: 2) > WidgetTypography.width("Nothing Playing", regular, scale: 2))
        var condensed = regular
        condensed.width = .condensed
        #expect(WidgetTypography.width("Nothing Playing", condensed, scale: 2) < WidgetTypography.width("Nothing Playing", regular, scale: 2))
        let digits = TypeSpec(points: 20, monospacedDigits: true)
        #expect(WidgetTypography.width("1111", digits, scale: 2) == WidgetTypography.width("8888", digits, scale: 2))
        #expect(WidgetTypography.width("1111", TypeSpec(points: 20), scale: 2) < WidgetTypography.width("8888", TypeSpec(points: 20), scale: 2))
        var tracked = TypeSpec(points: 20)
        tracked.tracking = 4
        #expect(WidgetTypography.width("abc", tracked, scale: 2) > WidgetTypography.width("abc", TypeSpec(points: 20), scale: 2) + 8)
        var upper = TypeSpec(points: 20)
        upper.textCase = .uppercase
        #expect(WidgetTypography.width("abc", upper, scale: 2) == WidgetTypography.width("ABC", TypeSpec(points: 20), scale: 2))
    }

    @Test func theCacheKeepsTheLast256() {
        var cache = MeasureCache<Int, Int>()
        for key in 0..<300 { cache[key] = key * 2 }
        #expect(cache.count == 256)
        #expect(cache[0] == nil && cache[43] == nil)
        #expect(cache[44] == 88 && cache[299] == 598)
        cache[299] = 1
        #expect(cache.count == 256 && cache[299] == 1 && cache[44] == 88)
    }

    // MARK: - Limits

    /// A quarter point more never fits, on one line or wrapped (wrapped text used to stop a step
    /// short: its estimate leaves out the spaces a line break swallows).
    @Test func maxPointsIsTheLargestThatFits() {
        for design in FontDesignChoice.allCases {
            for weight in [FontWeightChoice.regular, .semibold] {
                let spec = TypeSpec(points: 0, design: design, weight: weight)
                for width in [30, 37, 54, 71, 90, 150, 210, 270, 330] as [CGFloat] {
                    for height in [14.0, 33, 60, 120] as [CGFloat] {
                        for lines in 1...3 {
                            let room = CGSize(width: width, height: height)
                            for samples in [["Unknown Title", "Nothing Playing"], ["Nothing Playing", "88:88", "Wj"]] {
                                let note = "\(design) \(weight) \(room) \(lines) lines \(samples)"
                                guard let points = TextFit.maxPoints(samples: samples, spec: spec, room: room, lines: lines, scale: 2) else {
                                    #expect(!TextFit.fits(samples, spec.at(TextFit.minimumPoints), room: room, lines: lines, scale: 2), "\(note)")
                                    continue
                                }
                                #expect(TextFit.fits(samples, spec.at(points), room: room, lines: lines, scale: 2), "\(note)")
                                if points + TextFit.step <= TextFit.maximumPoints {
                                    #expect(!TextFit.fits(samples, spec.at(points + TextFit.step), room: room, lines: lines, scale: 2),
                                            "\(note): \(points)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func wrappedTextFitsItsLines() {
        let spec = TypeSpec(points: 0)
        let samples = ["Music you play appears here."]
        let room = CGSize(width: 90, height: 60)
        let one = TextFit.maxPoints(samples: samples, spec: spec, room: room, lines: 1, scale: 2)!
        let two = TextFit.maxPoints(samples: samples, spec: spec, room: room, lines: 2, scale: 2)!
        #expect(two > one)
        #expect(WidgetTypography.lineCount(samples[0], spec.at(two), width: room.width - 0.5) <= 2)
    }

    /// A frame is as tall as SwiftUI's lines (whole points), and its inverse is the largest quarter
    /// point size that frame takes, so a stored size comes back no smaller than it was.
    @Test func frameHeightIsWholeLinesAndItsInverseTheLargestThatFits() {
        for design in FontDesignChoice.allCases {
            for weight in FontWeightChoice.allCases {
                let spec = TypeSpec(points: 0, design: design, weight: weight)
                for lines in 1...3 {
                    var previous: CGFloat = 0
                    for points in stride(from: CGFloat(6.0), through: 60, by: 0.5) {
                        let note = "\(design) \(weight) \(points) \(lines) lines"
                        let height = TextFit.frameHeight(points: points, lines: lines, spec: spec)
                        #expect(height == CGFloat(lines) * WidgetTypography.lineHeight(spec.at(points)), "\(note)")
                        #expect(height >= previous, "\(note)")
                        previous = height
                        let back = TextFit.points(forFrameHeight: height, lines: lines, spec: spec)
                        #expect(back >= points && TextFit.frameHeight(points: back, lines: lines, spec: spec) <= height, "\(note): \(back)")
                        #expect(TextFit.frameHeight(points: back + TextFit.step, lines: lines, spec: spec) > height, "\(note): \(back)")
                    }
                }
            }
        }
    }

    /// Text sized from its frame is drawn inside the frame, on one line and wrapped.
    @MainActor @Test func textSizedFromItsFrameIsDrawnInsideIt() {
        for design in FontDesignChoice.allCases {
            for points in [9.0, 11, 13, 15, 17, 22, 30] as [CGFloat] {
                for lines in 1...3 {
                    let spec = TypeSpec(points: 0, design: design)
                    let frame = TextFit.frameHeight(points: points, lines: lines, spec: spec)
                    let sized = spec.at(TextFit.points(forFrameHeight: frame, lines: lines, spec: spec))
                    let text = Array(repeating: "Nothing Playing", count: lines).joined(separator: " ")
                    let host = NSHostingController(rootView: Text(text).font(WidgetTypography.font(sized)).lineLimit(lines))
                    let drawn = host.sizeThatFits(in: CGSize(width: points * 9, height: 10_000))
                    #expect(drawn.height <= frame, "\(design) \(points) \(lines) lines: \(drawn.height) in \(frame)")
                }
            }
        }
    }

    @Test func symbolsFitTheirRoom() {
        for room in [CGSize(width: 20, height: 20), CGSize(width: 60, height: 24), CGSize(width: 18, height: 50)] {
            let points = SymbolFit.maxPoints("battery.75percent", weight: .regular, room: room, scale: 2)!
            let size = SymbolFit.size("battery.75percent", points: points, weight: .regular, scale: 2)
            #expect(size.width <= room.width && size.height <= room.height)
            let larger = SymbolFit.size("battery.75percent", points: points + 1, weight: .regular, scale: 2)
            #expect(larger.width > room.width || larger.height > room.height)
        }
        #expect(SymbolFit.maxPoints("no.such.symbol.anywhere", weight: .regular, room: CGSize(width: 50, height: 50), scale: 2) == nil)
    }

    // MARK: - Plans

    private static let grids = [BoardGrid.standard, BoardGrid(columns: 8, rows: 2, gap: 10), BoardGrid(columns: 16, rows: 4, gap: 6)]
    private static let board = CGSize(width: 640, height: 150)

    /// Every kind at its smallest, default and largest size on each grid.
    private static func sizes(_ kind: IslandWidgetKind) -> [CGSize] {
        grids.flatMap { grid in
            let geometry = WidgetBoardGeometry(size: board, grid: grid)
            return [grid.minimum(for: kind), grid.defaultSize(for: kind), grid.maximum(for: kind)].map {
                geometry.frame(for: GridRect(column: 0, row: 0, width: $0.width, height: $0.height)).size
            }
        }
    }

    private func input(_ kind: IslandWidgetKind, _ size: CGSize, _ style: WidgetStyle = WidgetStyle(),
                       shown: Set<ElementID>? = nil) -> PlanInput {
        PlanInput(spec: kind.spec, size: size, style: style, shown: shown ?? Set(kind.spec.elements.map(\.id)))
    }

    /// Nothing planned is larger than the widget's room, across or along.
    private func expectInside(_ plan: WidgetPlan, _ input: PlanInput, _ note: String) {
        let inner = input.inner
        let vertical = (input.style.layout.axis ?? (inner.width >= inner.height * 2.5 ? .horizontal : .vertical)) == .vertical
        let spacing = CGFloat(input.style.layout.spacing ?? 4) * input.scale * CGFloat(max(plan.elements.count - 1, 0))
        let along = plan.elements.values.reduce(spacing) { $0 + (vertical ? $1.size.height : $1.size.width) }
        #expect(along <= (vertical ? inner.height : inner.width) + 0.01, "\(note): \(along) along")
        for (id, element) in plan.elements {
            #expect((vertical ? element.size.width : element.size.height) <= (vertical ? inner.width : inner.height) + 0.01,
                    "\(note): \(id.rawValue) across")
        }
    }

    @Test func autoPlansFitEveryKindAtEverySize() {
        for kind in IslandWidgetKind.allCases {
            for size in Self.sizes(kind) {
                let input = input(kind, size)
                let plan = DefaultWidgetPlanner().plan(input)
                #expect(Set(plan.elements.keys).union(plan.hidden.keys) == Set(kind.spec.elements.map(\.id)))
                #expect(plan.elements.values.allSatisfy { !$0.isClamped })
                expectInside(plan, input, "\(kind) \(size)")
            }
        }
    }

    /// A title allowed two or three lines wraps into them instead of being left out for want of
    /// room on one.
    @Test(arguments: [2, 3])
    func wrappedTextIsPlannedWrapped(_ lines: Int) {
        var style = WidgetStyle()
        var title = ElementStyle()
        title.text.lineLimit = lines
        style.elements[.trackInfo] = title
        let samples: [ElementID: [String]] = [.trackInfo: ["Music you play appears here."]]
        for size in [CGSize(width: 100, height: 88), CGSize(width: 110, height: 120)] {
            let input = PlanInput(spec: IslandWidgetKind.nowPlaying.spec, size: size, style: style, samples: samples, shown: [.trackInfo])
            let plan = DefaultWidgetPlanner().plan(input)
            #expect(plan.elements[.trackInfo] != nil, "\(size): \(plan.hidden)")
            if let element = plan.elements[.trackInfo] {
                #expect(TextFit.fits(samples[.trackInfo]!, TypeSpec(points: element.points), room: element.size, lines: lines, scale: 2),
                        "\(size): \(element)")
            }
            expectInside(plan, input, "\(size) \(lines) lines")
        }
    }

    /// A fixed size is drawn exactly, or flagged: never silently smaller.
    @Test(arguments: [9.0, 16, 30, 60])
    func fixedSizesAreKeptOrFlagged(_ fixed: Double) {
        var (kept, clamped) = (0, 0)
        for kind in IslandWidgetKind.allCases {
            var style = WidgetStyle()
            for element in kind.spec.elements where element.role == .text || element.role == .symbol {
                var elementStyle = ElementStyle()
                elementStyle.text.points = fixed
                elementStyle.symbol.points = fixed
                style.elements[element.id] = elementStyle
            }
            for size in Self.sizes(kind) {
                let input = input(kind, size, style)
                let plan = DefaultWidgetPlanner().plan(input)
                for (id, element) in plan.elements where kind.spec.element(id)!.role != .image && element.points > 0 {
                    if element.isClamped {
                        clamped += 1
                        #expect(element.points < CGFloat(fixed), "\(kind) \(size) \(id.rawValue)")
                    } else {
                        kept += 1
                        #expect(element.points == CGFloat(fixed), "\(kind) \(size) \(id.rawValue): \(element.points)")
                    }
                }
                expectInside(plan, input, "\(kind) \(size) fixed \(fixed)")
            }
        }
        if fixed <= 16 { #expect(kept > 50) }
        if fixed >= 30 { #expect(clamped > 20) }
    }

    /// With room, a fixed size stays while the auto elements around it shrink or go.
    @Test func fixedIsReservedBeforeAutoShrinks() {
        let size = CGSize(width: 330, height: 90)
        var style = WidgetStyle()
        var title = ElementStyle()
        title.text.points = 26
        style.elements[.trackInfo] = title
        let automatic = DefaultWidgetPlanner().plan(input(.nowPlaying, size))
        let plan = DefaultWidgetPlanner().plan(input(.nowPlaying, size, style))
        #expect(plan.elements[.trackInfo]?.points == 26)
        #expect(plan.elements[.trackInfo]?.isClamped == false)
        let artist = plan.elements[.artist]?.points ?? 0, automaticArtist = automatic.elements[.artist]?.points ?? 0
        #expect(artist < automaticArtist || plan.hidden[.artist] == .noRoom)
    }

    @Test func smallMediumAndLargeAlwaysDiffer() {
        var compared = 0
        for kind in IslandWidgetKind.allCases {
            guard let element = kind.spec.elements.first(where: { $0.role == .text && !$0.samples.isEmpty && $0.minRoom == nil }) else { continue }
            for size in Self.sizes(kind) {
                let points = ElementSize.allCases.map { elementSize in
                    let input = PlanInput(spec: kind.spec, size: size, shown: [element.id], sizes: [element.id: elementSize])
                    return DefaultWidgetPlanner().plan(input).elements[element.id]?.points
                }
                guard let small = points[0], let medium = points[1], let large = points[2] else { continue }
                compared += 1
                #expect(small < medium && medium < large, "\(kind) \(size): \(points)")
            }
        }
        #expect(compared > 200)
    }

    @Test func rangesGrowWithTheWidget() {
        var checked = 0
        for kind in [IslandWidgetKind.nowPlaying, .battery, .timer, .dateTime] {
            guard let element = kind.spec.elements.first(where: { $0.role == .text && $0.minRoom == nil }) else { continue }
            var previous: CGFloat = 0
            for width in stride(from: CGFloat(60.0), through: 400, by: 20) {
                let input = PlanInput(spec: kind.spec, size: CGSize(width: width, height: 88), shown: [element.id])
                guard let plan = DefaultWidgetPlanner().plan(input).elements[element.id] else { continue }
                #expect(plan.range.contains(plan.points), "\(kind) \(width)")
                #expect(plan.range.upperBound >= previous, "\(kind) \(width)")
                previous = plan.range.upperBound
                checked += 1
            }
        }
        #expect(checked > 40)
    }

    @Test func switchedOffAndCrowdedOutSayWhy() {
        let kind = IslandWidgetKind.nowPlaying
        let plan = DefaultWidgetPlanner().plan(input(kind, CGSize(width: 90, height: 40), shown: [.trackInfo, .artist, .artwork]))
        #expect(plan.hidden[.progress] == .switchedOff)
        #expect(plan.hidden[.artwork] == .noRoom)
        #expect(plan.elements[.trackInfo] != nil)
    }
}
