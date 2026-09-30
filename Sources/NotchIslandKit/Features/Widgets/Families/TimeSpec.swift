import Foundation

/// The time and the calendar (`DateTimeWidget`).
nonisolated enum TimeSpecs {
    static let all: [IslandWidgetKind: WidgetKindSpec] = [
        .dateTime: WidgetKindSpec(
            title: "Date & Time",
            summary: "The time and today's date.",
            symbol: "calendar.badge.clock",
            iconColors: red,
            category: .time, family: .time,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 3, height: 1),
            maximumSize: GridSize(width: 6, height: 3),
            elements: [
                ElementSpec(.readout, "Time", symbol: "clock", role: .text, samples: ["88:88"], priority: 100),
                ElementSpec(.dateLine, "Date", symbol: "calendar", role: .text,
                            samples: ["Wednesday, 30 September", "Wed, 30 Sep", "Wed 30", "30"], priority: 60),
            ]
        ),
        .worldClock: kind("World Clock", "The time in another city.", symbol: "globe",
                          elements: ElementSpec.reading(["88:88"], caption: "Cupertino"),
                          sizes: (GridSize(width: 2, height: 1), GridSize(width: 3, height: 1), GridSize(width: 6, height: 3)),
                          stacks: true),
        .analogClock: kind("Clock Face", "An analog clock, with a seconds hand if you like.", symbol: "clock",
                           elements: [ElementSpec(.face, "Clock face", symbol: "clock", role: .feature, priority: 100, isBlock: true,
                                                  isRequired: true)],
                           sizes: (GridSize(width: 1, height: 1), GridSize(width: 2, height: 2), GridSize(width: 4, height: 3)),
                           customLayout: false),
        .monthCalendar: kind("Calendar", "This month at a glance.", symbol: "calendar",
                             elements: [ElementSpec(.label, "Month", symbol: "textformat", role: .text, samples: ["September 2026"], priority: 60),
                                        ElementSpec(.monthGrid, "Days", symbol: "calendar", role: .feature, priority: 100, isBlock: true,
                                                    isRequired: true)],
                             sizes: (GridSize(width: 3, height: 2), GridSize(width: 4, height: 3), GridSize(width: 6, height: 3))),
        .upNext: kind("Up Next", "Your next events, from Calendar.", symbol: "list.bullet.rectangle.fill",
                      elements: [ElementSpec(.eventList, "Events", symbol: "list.bullet", role: .feature, priority: 100, isBlock: true,
                                             isRequired: true)],
                      sizes: (GridSize(width: 3, height: 1), GridSize(width: 4, height: 2), GridSize(width: 12, height: 3)),
                      config: { $0.count = 2 }, permission: .calendars, customLayout: false),
        .countdown: kind("Countdown", "Days to go until a date.", symbol: "hourglass.bottomhalf.filled",
                         elements: ElementSpec.reading(["888 days"], caption: "Countdown"),
                         sizes: (GridSize(width: 2, height: 1), GridSize(width: 3, height: 1), GridSize(width: 6, height: 3)),
                         stacks: true),
    ]

    private static let red: [IslandTheme.RGB] = [.rgb(1.0, 0.4, 0.36), .rgb(0.95, 0.2, 0.22)]

    private static func kind(_ title: String, _ summary: String, symbol: String, elements: [ElementSpec],
                             sizes: (minimum: GridSize, standard: GridSize, maximum: GridSize),
                             config: (inout WidgetConfig) -> Void = { _ in }, permission: WidgetPermission? = nil,
                             customLayout: Bool = true, stacks: Bool = false) -> WidgetKindSpec {
        var defaults = WidgetConfig()
        config(&defaults)
        return WidgetKindSpec(
            title: title, summary: summary, symbol: symbol, iconColors: red, category: .time, family: .time,
            minimumSize: sizes.minimum, defaultSize: sizes.standard, maximumSize: sizes.maximum,
            elements: elements,
            defaultConfig: defaults,
            permission: permission,
            supportsCustomLayout: customLayout,
            stacksElements: stacks
        )
    }
}
