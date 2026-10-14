import Foundation
import Testing
@testable import NotchIslandKit

/// System: the graphics processor's share, which layout a size gets (lines, rings, the graph with
/// dials), the dials' texts, the graph's drawing, and widgets saved before the graph.
@MainActor @Suite struct SystemStatsTests {
    private func widget(_ width: Int, _ height: Int, _ options: Set<ElementID> = IslandWidgetKind.systemStats.defaultOptions) -> IslandWidget {
        IslandWidget(kind: .systemStats, frame: GridRect(column: 0, row: 0, width: width, height: height), options: options)
    }

    @Test func graphicsShareFromTheAcceleratorsStatistics() {
        #expect(GPUStats.utilization(in: ["Device Utilization %": 35, "Renderer Utilization %": 20]) == 0.35)
        // The renderer's where the device's is missing; held within 0…1.
        #expect(GPUStats.utilization(in: ["Renderer Utilization %": 20]) == 0.2)
        #expect(GPUStats.utilization(in: ["Device Utilization %": 140]) == 1)
        #expect(GPUStats.utilization(in: ["Alloc system memory": 2_120_646_656]) == nil)
    }

    /// Lines a row tall, rings two rows tall but narrow, the graph from four columns; the dials
    /// beside it where switched on, the graph left out where they leave it no room.
    @Test func theLayoutFollowsTheSize() {
        let small = widget(3, 1)
        #expect(SystemStatsWidget.layout(small, inner: CGSize(width: 124, height: 28)).style == .bars)
        #expect(SystemStatsWidget.layout(small, inner: CGSize(width: 124, height: 76)).style == .rings)
        let large = SystemStatsWidget.layout(small, inner: CGSize(width: 220, height: 76))
        #expect(large.style == .large && large.showsGraph && large.dials.isEmpty)
        // Graph off: rings again.
        #expect(SystemStatsWidget.layout(widget(5, 2, [.cpuLoad, .memoryLoad]), inner: CGSize(width: 220, height: 76)).style == .rings)
        // Dials: all three loads, the graph only where it still has room.
        let all: Set<ElementID> = [.cpuLoad, .gpuLoad, .memoryLoad, .statsGraph, .statsDials]
        let crowded = SystemStatsWidget.layout(widget(5, 2, all), inner: CGSize(width: 220, height: 76))
        #expect(crowded.dials == [.cpuLoad, .gpuLoad, .memoryLoad] && !crowded.showsGraph)
        let wide = SystemStatsWidget.layout(widget(12, 2, all), inner: CGSize(width: 556, height: 76))
        #expect(wide.dials.count == 3 && wide.showsGraph && wide.graphWidth >= SystemStatsWidget.Layout.minimumGraph)
        #expect(wide.dial * 3 + wide.gap * 3 + wide.graphWidth <= 556.5)
        // Customize: the graph has no room in a row, the dials none under two rows.
        #expect(!SystemStatsWidget.hasRoom(for: .statsGraph, in: small, inner: CGSize(width: 124, height: 76)))
        #expect(!SystemStatsWidget.hasRoom(for: .statsDials, in: small, inner: CGSize(width: 300, height: 28)))
    }

    @Test func theDialsTexts() {
        #expect(SystemStatsWidget.percentNumber(0.234) == "23")
        #expect(SystemStatsWidget.percentNumber(1.4) == "100")
        // Gigabytes as Activity Monitor counts them, two decimals in the locale's way.
        let bytes = UInt64(16.12 * 1_073_741_824)
        #expect(SystemStatsWidget.gigabytes(bytes, locale: Locale(identifier: "en_US")) == "16.12")
        #expect(SystemStatsWidget.gigabytes(bytes, locale: Locale(identifier: "hu_HU")) == "16,12")
        #expect(SystemStatsWidget.memoryWord(physical: 17_179_869_184).contains("16"))
        #expect(SystemStatsWidget.word(0.05) != SystemStatsWidget.word(0.9))
    }

    /// The graph: 100 % at its top, 0 % at its floor, texts from 56 pt; the processor's line drawn
    /// last (on top).
    @Test func theGraphsDrawing() {
        let layout = LoadGraph.layout(CGSize(width: 240, height: 80), caption: 12, column: 30)
        #expect(layout.showsTexts && layout.plot == 210 && layout.top < layout.floor && layout.floor < layout.key)
        #expect(!LoadGraph.layout(CGSize(width: 240, height: 40), caption: 12, column: 30).showsTexts)
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let history = SystemStatsWidget.sampleHistory(now: now)
        let series = [ElementID.cpuLoad, .memoryLoad].map {
            LoadGraph.Series(id: $0, name: SystemStatsWidget.title($0), samples: history[$0] ?? [], tint: LoadGraph.cpuTint)
        }
        let graph = LoadGraph(series: series, now: now, window: 600, percentages: [0, 50, 100], size: CGSize(width: 240, height: 80))
        #expect(graph.y(1, layout: layout) == layout.top && graph.y(0, layout: layout) == layout.floor)
        #expect(graph.y(2, layout: layout) == layout.top)
        #expect(ChartLook.plain.percentages == [0, 50, 100])
    }

    @Test func historyKeepsTenMinutes() {
        var series: [SensorSample] = []
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for second in stride(from: 0, through: 900, by: 15) {
            SensorSample.append(SensorSample(date: start.addingTimeInterval(TimeInterval(second)), value: 0.5), to: &series, window: 600)
        }
        #expect(series.first.map { start.addingTimeInterval(900).timeIntervalSince($0.date) <= 605 } == true)
        // At most one a second.
        let count = series.count
        SensorSample.append(SensorSample(date: start.addingTimeInterval(900.3), value: 0.5), to: &series, window: 600)
        #expect(series.count == count)
    }

    /// A System widget saved before the graph shows it as a new one does; Graphics and Dials stay off.
    @Test func aWidgetSavedBeforeTheGraphGetsIt() throws {
        let json = #"{"version":4,"kind":"systemStats","frame":{"column":0,"row":0,"width":5,"height":2},"options":["cpuLoad","memoryLoad"]}"#
        let old = try JSONDecoder().decode(IslandWidget.self, from: Data(json.utf8))
        #expect(old.options == [.cpuLoad, .memoryLoad, .statsGraph])
        let saved = try JSONDecoder().decode(IslandWidget.self, from: JSONEncoder().encode(widget(5, 2, [.cpuLoad])))
        #expect(saved.options == [.cpuLoad])
        #expect(!IslandWidgetKind.systemStats.defaultOptions.contains(.gpuLoad))
        #expect(!IslandWidgetKind.systemStats.defaultOptions.contains(.statsDials))
    }
}
