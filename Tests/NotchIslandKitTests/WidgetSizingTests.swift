import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

/// S, M and L must always look different: the room a widget gives an element caps it, and that
/// cap used to make Large (and often Medium) the same size.
@Suite struct WidgetSizingTests {
    @Test func fittedOrdersSmallMediumLargeWhateverTheRoom() {
        for design in stride(from: CGFloat(8), through: 48, by: 2) {
            for fit in stride(from: CGFloat(0), through: 120, by: 3) {
                let s = WidgetType.fitted(design, fit: fit, .small)
                let m = WidgetType.fitted(design, fit: fit, .medium)
                let l = WidgetType.fitted(design, fit: fit, .large)
                #expect(s < m && m < l, "design \(design), fit \(fit): \(s) \(m) \(l)")
            }
        }
    }

    @Test func withRoomEachSizeIsItsFactorOfTheDesign() {
        #expect(WidgetType.fitted(20, fit: 500, .small) == 16)
        #expect(WidgetType.fitted(20, fit: 500, .medium) == 20)
        #expect(WidgetType.fitted(20, fit: 500, .large) == 25)
    }

    @Test func largeNeverExceedsTheRoomAboveTheFloor() {
        for fit in stride(from: CGFloat(10), through: 60, by: 1) {
            #expect(WidgetType.fitted(40, fit: fit, .large) <= fit + 0.25)
        }
    }

    @Test func textFitsWhereItWasMeasured() {
        let size = WidgetType.size(fitting: "12:34", in: 80, weight: .semibold, rounded: true, monospacedDigits: true)
        #expect(size > 10 && size < 60)
        let width = WidgetType.textWidth("12:34", size: size)
        #expect(width <= 80 && width > 70)
        #expect(WidgetType.size(fitting: "", in: 80) == .greatestFiniteMagnitude)
        #expect(WidgetType.size(fitting: "a", in: 0) == 0)
    }

    /// Keep Awake, Bluetooth, Do Not Disturb… in the tiles the board gives them.
    @Test(arguments: [
        CGSize(width: 90, height: 40), CGSize(width: 138, height: 40), CGSize(width: 186, height: 40),
        CGSize(width: 90, height: 88), CGSize(width: 186, height: 88),
    ])
    func controlLabelsGrowFromSmallToLarge(_ tile: CGSize) {
        for (title, status) in [("Keep Awake", "Off"), ("Bluetooth", "On"), ("Do Not Disturb", "Off"), ("Wi-Fi", "On")] {
            let tall = tile.width < tile.height * 1.6 && tile.height >= ControlWidget.tallTileHeight
            let diameter = tall ? min(tile.width * 0.5, tile.height * 0.5, 44) : min(tile.height, max(20, tile.width * 0.32), 44)
            let width = tall ? tile.width : tile.width - diameter - max(4, diameter * 0.2)
            let lineRoom = tall ? tile.height - diameter - 4 : tile.height
            let room = tall ? tile.width : tile.height * 1.4
            let names = ElementSize.allCases.map { size in
                ControlLabelLayout.choose(title: title, status: status, longestStatus: status, showsName: true, showsStatus: true,
                                          nameDesign: WidgetType.points(room, ratio: 0.26, min: 10, max: 15),
                                          statusDesign: WidgetType.points(room, ratio: 0.22, min: 9, max: 13),
                                          width: width - 2, height: lineRoom, nameSize: size, statusSize: size,
                                          minimum: ControlWidget.minimumLabelSize)
            }
            let shown = names.filter { $0.arrangement != .none }
            // Where a label shows at all, each size is larger than the one before.
            if shown.count == 3 {
                #expect(names[0].name < names[1].name && names[1].name < names[2].name,
                        "\(title) in \(tile): \(names.map(\.name))")
            }
            // And it fits what it was given.
            for layout in shown {
                #expect(layout.fitsWithoutFloor(width: width - 2, height: lineRoom, title: title), "\(title) in \(tile): \(layout)")
            }
        }
    }
}

/// Renders every widget at a few sizes with all its elements Small, Medium and Large, into
/// `$NI_RENDER_WIDGETS/<kind>.png`, for looking at. Skipped unless that variable is set.
@MainActor @Suite struct WidgetSizingRenders {
    @Test func renderContactSheets() throws {
        guard let directory = ProcessInfo.processInfo.environment["NI_RENDER_WIDGETS"] else { return }
        let model = AppModel()
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard)
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(layout), gap: WidgetMetrics.gap)
        let kinds: [IslandWidgetKind] = [.nowPlaying, .timer, .stopwatch, .shelf, .battery, .volume, .assistant, .dateTime,
                                         .systemStats, .keepAwake, .bluetooth]
        for kind in kinds {
            let frames = [kind.minimumSize, kind.defaultSize, GridSize(width: min(kind.maximumSize.width, kind.defaultSize.width + 2),
                                                                         height: min(kind.maximumSize.height, kind.defaultSize.height + 1))]
            let sheet = VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, grid in
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(ElementSize.allCases) { element in
                            let rect = geometry.frame(for: GridRect(column: 0, row: 0, width: grid.width, height: grid.height))
                            VStack(spacing: 2) {
                                Text("\(grid.width)×\(grid.height) \(element.title)").font(.caption2).foregroundStyle(.secondary)
                                IslandWidgetView(widget: Self.widget(kind, grid: grid, element: element), size: rect.size,
                                                 thumbnails: ThumbnailCache())
                                    .frame(width: rect.width, height: rect.height)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(.black)
            .environment(model)
            .environment(\.isWidgetPreview, true)
            .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 2
            guard let image = renderer.cgImage else { continue }
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(kind.rawValue).png")
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            try data?.write(to: url)
        }
    }

    static func widget(_ kind: IslandWidgetKind, grid: GridSize, element: ElementSize) -> IslandWidget {
        var widget = IslandWidget(kind: kind, frame: GridRect(column: 0, row: 0, width: grid.width, height: grid.height),
                                  options: kind.defaultOptions)
        for option in kind.options where option.isSizable { widget.sizes[option] = element }
        return widget
    }
}
