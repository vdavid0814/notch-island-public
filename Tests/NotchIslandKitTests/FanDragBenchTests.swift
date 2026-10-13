import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

/// What a turn of the fan's dial costs: Fan Control at its widest (both dials and the graph) in a
/// window, live, with simulated fans, and the dial dragged round its arc by real mouse events.
/// Prints the main thread's CPU milliseconds a step (the event, the update it causes and the
/// drawing). A benchmark, not a check: only with NI_BENCH=1 and NI_DEMO_FANS=1.
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["NI_BENCH"] == "1" && FanSensors.isSimulated,
                                        "a benchmark: NI_BENCH=1 NI_DEMO_FANS=1"))
struct FanDragBenchTests {
    @Test func turningTheDial() async throws {
        let model = AppModel()
        model.fans.onRead = { [weak model] in model?.thermals.record(speed: $0, maximum: $1) }
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard)
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(layout), grid: .standard)
        let rect = GridRect(column: 0, row: 0, width: 12, height: 3)
        let size = geometry.frame(for: rect).size
        let widget = IslandWidget(kind: .fanControl, frame: rect, options: IslandWidgetKind.fanControl.defaultOptions)
        let host = NSHostingView(rootView: IslandWidgetView(widget: widget, size: size)
            .frame(width: size.width, height: size.height)
            .background(.black)
            .environment(model)
            .environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: size.width, height: size.height), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        // A few readings first: the graphs have lines to draw.
        try await Task.sleep(for: .seconds(4))

        let padding = WidgetMetrics.padding(for: widget)
        let inner = CGSize(width: size.width - 2 * padding, height: size.height - 2 * padding)
        let dial = FanControlWidget.layout(widget, inner: inner).dial
        // The dial's middle in the window (y up): the row starts at the widget's leading edge.
        let middle = CGPoint(x: padding + dial / 2, y: size.height / 2)
        func send(_ type: NSEvent.EventType, degrees: Double) {
            let angle = degrees * .pi / 180
            let point = CGPoint(x: middle.x + cos(angle) * dial * 0.45, y: middle.y - sin(angle) * dial * 0.45)
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
            RunLoop.main.run(mode: .default, before: Date())
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            CATransaction.flush()
        }
        let before = model.fans.heldFraction
        send(.leftMouseDown, degrees: 150)
        let steps = 240
        let (cpu, wall) = (clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID), clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
        for step in 1...steps {
            // Back and forth along the arc, a degree a step.
            let along = Double(step <= steps / 2 ? step : steps - step)
            send(.leftMouseDragged, degrees: 150 + along)
        }
        let cpuMs = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpu) / 1e6 / Double(steps)
        let wallMs = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - wall) / 1e6 / Double(steps)
        send(.leftMouseUp, degrees: 150)
        window.orderOut(nil)
        #expect(model.fans.heldFraction != before, "the drag did not reach the dial")
        print("FAN DRAG: \(String(format: "%.2f", cpuMs)) ms CPU a step, \(String(format: "%.2f", wallMs)) ms wall (\(steps) steps, dial \(Int(dial)) pt)")
    }
}
