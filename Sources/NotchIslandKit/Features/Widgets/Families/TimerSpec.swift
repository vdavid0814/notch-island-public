import Foundation

/// The timer and the stopwatch (`TimerWidget`, `StopwatchWidget`).
nonisolated enum TimerSpecs {
    static let all: [IslandWidgetKind: WidgetKindSpec] = [
        .timer: WidgetKindSpec(
            title: "Timer",
            summary: "Scroll the ruler to a length and start it.",
            symbol: "timer",
            iconColors: [.rgb(1.0, 0.66, 0.2), .rgb(1.0, 0.45, 0.08)],
            category: .time, family: .timers,
            minimumSize: GridSize(width: 3, height: 1), defaultSize: GridSize(width: 5, height: 2),
            maximumSize: GridSize(width: 12, height: 3),
            elements: [
                // Its ticks and marker need 18 pt over the button row (`TimerWidget.minimumRulerSpace`).
                ElementSpec(.ruler, "Ruler", symbol: "ruler", role: .feature, priority: 60, minRoom: MinRoom(height: 18),
                            isBlock: true),
                ElementSpec(.readout, "Time", symbol: "clock", role: .text, samples: ["88:88", "8:88:88"], priority: 100),
                ElementSpec(.addMinute, "+1 minute button", symbol: "plus.circle", role: .button, priority: 40,
                            defaultVisible: false, isSizable: false),
                ElementSpec(.timerSeconds, "Set seconds", symbol: "s.circle", role: .feature, defaultVisible: false,
                            isSizable: false),
                ElementSpec(.timerHours, "Set hours", symbol: "h.circle", role: .feature, defaultVisible: false,
                            isSizable: false),
            ],
            canMirror: true
        ),
        .stopwatch: WidgetKindSpec(
            title: "Stopwatch",
            summary: "Start, pause and reset a stopwatch.",
            symbol: "stopwatch.fill",
            iconColors: [.rgb(1.0, 0.82, 0.25), .rgb(1.0, 0.6, 0.1)],
            category: .time, family: .timers,
            minimumSize: GridSize(width: 3, height: 1), defaultSize: GridSize(width: 4, height: 1),
            maximumSize: GridSize(width: 12, height: 2),
            elements: [
                ElementSpec(.readout, "Time", symbol: "clock", role: .text, samples: ["00:00", "0:00:00"], priority: 100),
                ElementSpec(.resetButton, "Reset button", symbol: "arrow.counterclockwise", role: .button, priority: 40,
                            isSizable: false),
            ],
            canMirror: true
        ),
    ]
}
