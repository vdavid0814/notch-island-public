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
        .worldClock: reserved("World Clock", "The time in another city.", symbol: "globe", samples: ["88:88"],
                              sizes: (GridSize(width: 2, height: 1), GridSize(width: 3, height: 1), GridSize(width: 6, height: 3))),
        .analogClock: reserved("Analog Clock", "A clock face, with a seconds hand if you like.", symbol: "clock",
                               samples: ["12"],
                               sizes: (GridSize(width: 1, height: 1), GridSize(width: 2, height: 2), GridSize(width: 4, height: 3))),
        .monthCalendar: reserved("Calendar", "This month at a glance.", symbol: "calendar", samples: ["88"],
                                 sizes: (GridSize(width: 3, height: 2), GridSize(width: 4, height: 3), GridSize(width: 6, height: 3))),
        .upNext: reserved("Up Next", "Your next event, from Calendar.", symbol: "list.bullet.rectangle.fill",
                          samples: ["88:88", "Design review"],
                          sizes: (GridSize(width: 3, height: 1), GridSize(width: 4, height: 2), GridSize(width: 12, height: 3)),
                          permission: .calendars),
        .countdown: reserved("Countdown", "Days to go until a date.", symbol: "hourglass.bottomhalf.filled", samples: ["888 days"],
                             sizes: (GridSize(width: 2, height: 1), GridSize(width: 3, height: 1), GridSize(width: 6, height: 3))),
    ]

    private static let red: [IslandTheme.RGB] = [.rgb(1.0, 0.4, 0.36), .rgb(0.95, 0.2, 0.22)]

    private static func reserved(_ title: String, _ summary: String, symbol: String, samples: [String],
                                 sizes: (minimum: GridSize, standard: GridSize, maximum: GridSize),
                                 permission: WidgetPermission? = nil) -> WidgetKindSpec {
        WidgetKindSpec(
            title: title, summary: summary, symbol: symbol, iconColors: red, category: .time, family: .time,
            minimumSize: sizes.minimum, defaultSize: sizes.standard, maximumSize: sizes.maximum,
            elements: ElementSpec.reading(samples, caption: title),
            permission: permission,
            isImplemented: false
        )
    }
}
