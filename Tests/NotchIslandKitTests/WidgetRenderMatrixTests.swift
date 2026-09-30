import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

/// Every offered kind at each of its size presets, drawn on the editor's canvas as the island lays it
/// out: unlocked where its stacks drew it (the grid inside the widget), it draws the same picture,
/// every element where it was; and a fixed size set on a text element is drawn as set, a step
/// larger drawing larger, never past what its room gives it.
///
/// Some seconds of drawing on the main actor: they run with the snapshots, in a process of their own
/// (`Scripts/test.sh`), not beside the suites that time things on the main actor.
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["NI_SNAPSHOTS"] != nil,
                                        "run alone: Scripts/test.sh, or NI_SNAPSHOTS=verify"))
struct WidgetRenderMatrixTests {
    struct Drawing {
        var pixels: [UInt8]
        /// Read while the picture is still drawn: once its renderer goes, every element disappears
        /// from the probe.
        var frames: [ElementID: CGRect]
        var drawn: [ElementID: WidgetFrameProbe.Drawn]
        var plan: WidgetPlan
        var unlocked: LayoutConversion.Unlocked
        var size: CGSize
        var widget: IslandWidget
    }

    static func draw(_ item: WidgetSnapshotTests.Case, style: WidgetStyle = WidgetStyle(), model: AppModel) -> Drawing {
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard)
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(layout), grid: .standard)
        let rect = GridRect(column: 0, row: 0, width: item.size.width, height: item.size.height)
        let size = geometry.frame(for: rect).size
        let probe = WidgetFrameProbe()
        var widget = IslandWidget(kind: item.kind, frame: rect, options: item.kind.defaultOptions)
        widget.style = style
        let view = IslandWidgetView(widget: widget, size: size, thumbnails: ThumbnailCache())
            .frame(width: size.width, height: size.height)
            .coordinateSpace(.named(WidgetFrameProbe.space))
            .background(.black)
            .environment(model)
            .environment(\.widgetRenderMode, .canvas)
            .environment(\.widgetFrameProbe, probe)
            .environment(\.widgetDate, WidgetSnapshotTests.date)
            .environment(\.locale, Locale(identifier: "en_US@hours=h23"))
            .environment(\.timeZone, TimeZone(identifier: "Europe/Budapest")!)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let pixels = renderer.cgImage.map { WidgetSnapshotTests.pixels(WidgetSnapshotTests.png($0)) } ?? []
        return withExtendedLifetime(renderer) {
            Drawing(pixels: pixels, frames: probe.frames, drawn: probe.drawn, plan: probe.drawnPlan(),
                    unlocked: probe.unlock(size: size, padding: WidgetMetrics.padding(for: widget)), size: size, widget: widget)
        }
    }

    nonisolated static let customCases = WidgetSnapshotTests.cases.filter { item in
        guard item.kind.spec.supportsCustomLayout else { return false }
        // A control drawn as its lone button keeps it (`ControlFamily.allowsCustomLayout`).
        return !(item.kind.systemControl != nil && item.size == GridSize(width: 1, height: 1))
    }

    @Test(arguments: customCases) func unlockingKeepsEveryElementWhereItWas(_ item: WidgetSnapshotTests.Case) throws {
        let model = AppModel()
        let automatic = Self.draw(item, model: model)
        guard !automatic.frames.isEmpty else { return }
        let unlocked = automatic.unlocked
        var style = WidgetStyle()
        unlocked.apply(to: &style, size: automatic.size, scale: 1)
        let custom = Self.draw(item, style: style, model: model)
        for (id, frame) in automatic.frames {
            let placed = try #require(custom.frames[id], "\(item.name): \(id.rawValue) not drawn")
            // Text is centred on its measured frame, a line's height tall: its own glyph box.
            let tolerance: CGFloat = 1
            #expect(abs(placed.midX - frame.midX) <= tolerance && abs(placed.midY - frame.midY) <= tolerance,
                    "\(item.name): \(id.rawValue) \(frame) → \(placed)")
        }
        // The same picture, but for the shade of noise two pictures in one process may differ by while
        // other suites draw (`WidgetSnapshotTests`): never more than 1 in 255.
        let difference = zip(custom.pixels, automatic.pixels).map { max($0, $1) - min($0, $1) }.max() ?? 255
        #expect(custom.pixels.count == automatic.pixels.count && difference <= 1, "\(item.name): differs by \(difference)")
    }

    @Test(arguments: WidgetSnapshotTests.cases) func aFixedSizeIsDrawnAsSetWithinItsRoom(_ item: WidgetSnapshotTests.Case) {
        let model = AppModel()
        let automatic = Self.draw(item, model: model)
        for (id, drawn) in automatic.drawn {
            guard case .text(let type, _, let fit?) = drawn, fit.isFinite, fit > TextFit.minimumPoints + 1 else { continue }
            let lower = max(TextFit.minimumPoints, (fit / 2).rounded())
            var previous: CGFloat = 0
            for points in stride(from: lower, through: min(fit, TextFit.maximumPoints), by: max(0.5, ((fit - lower) / 4).rounded())) {
                var style = WidgetStyle()
                style.elements[id, default: ElementStyle()].text.points = Double(points)
                let styled = Self.draw(item, style: style, model: model)
                guard case .text(let set, _, _)? = styled.drawn[id] else {
                    Issue.record("\(item.name): \(id.rawValue) not drawn at \(points) pt (kind's \(type.points), room \(fit))")
                    break
                }
                #expect(abs(set.points - points) < 0.01, "\(item.name): \(id.rawValue) set \(points), drawn \(set.points)")
                #expect(set.points > previous, "\(item.name): \(id.rawValue) \(points) pt drawn no larger than \(previous)")
                previous = set.points
            }
            // Beyond the room: as large as the room gives it.
            var style = WidgetStyle()
            style.elements[id, default: ElementStyle()].text.points = Double(min(fit + 20, TextFit.maximumPoints))
            let clamped = Self.draw(item, style: style, model: model)
            if case .text(let set, _, _)? = clamped.drawn[id] {
                #expect(set.points <= fit + 0.01, "\(item.name): \(id.rawValue) drawn at \(set.points) past its room \(fit)")
            }
        }
    }
}
