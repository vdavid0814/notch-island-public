import Foundation

/// The battery and, from 0.6, a widget for each of its figures (`BatteryWidget`).
nonisolated enum BatterySpecs {
    static let all: [IslandWidgetKind: WidgetKindSpec] = [
        .battery: WidgetKindSpec(
            title: "Battery",
            summary: "Charge level and time remaining.",
            symbol: "battery.75percent",
            iconColors: green,
            category: .battery, family: .battery,
            minimumSize: GridSize(width: 1, height: 1), defaultSize: GridSize(width: 3, height: 1),
            maximumSize: GridSize(width: 6, height: 3),
            elements: [
                ElementSpec(.batteryGlyph, "Battery", symbol: "battery.75percent", role: .symbol, priority: 90),
                // In a ring, the percentage from a 40-pt ring.
                ElementSpec(.percentage, "Percentage", symbol: "percent", role: .text, samples: ["100%"], priority: 100),
                // Beside the battery, from a widget 110 pt wide (or 70 tall).
                ElementSpec(.timeRemaining, "Time remaining", symbol: "hourglass", role: .text,
                            samples: ["Charging", "88h 88m left"], priority: 40, minRoom: MinRoom(width: 110)),
            ],
            layouts: [.automatic, .glyph, .ring],
            canMirror: true
        ),
        .batteryTime: figure("Battery Time", "Time left on the battery, or until it is charged.", symbol: "hourglass",
                             samples: ["88:88", "Charged"]),
        .batteryHealth: figure("Battery Health", "The battery's maximum capacity and condition.", symbol: "heart.fill",
                               samples: ["100%", "Normal"]),
        .batteryCycles: figure("Charge Cycles", "How many charge cycles the battery has been through.",
                               symbol: "arrow.triangle.2.circlepath", samples: ["8888"]),
        .batteryPower: figure("Power", "What the Mac draws, or what the charger gives it.", symbol: "bolt.fill",
                              samples: ["-88.8 W"]),
        .batteryTemperature: figure("Temperature", "How warm the battery is.", symbol: "thermometer.medium",
                                    samples: ["88 °C"], isAvailable: { BatteryAvailability.hasTemperature }),
        .charger: figure("Charger", "The charger's power and whether it is charging.", symbol: "powerplug.fill",
                         samples: ["888 W", "Not Charging"]),
        .batteryLastCharge: figure("Last Charge", "The level the battery was last charged to, and when.",
                                   symbol: "battery.100percent.bolt", samples: ["100%", "Yesterday, 18:30"]),
        .batteryUsage: WidgetKindSpec(
            title: "Daily Usage", summary: "How much battery each of the last days used, like the iPhone's Battery Usage.",
            symbol: "chart.bar.xaxis", iconColors: green, category: .battery, family: .battery,
            minimumSize: GridSize(width: 3, height: 2), defaultSize: GridSize(width: 4, height: 3),
            maximumSize: GridSize(width: 8, height: 3),
            elements: [
                ElementSpec(.label, "Title", symbol: "textformat", role: .text, samples: ["Daily Usage"], priority: 40,
                            isSizable: false, acceptsLabel: true),
                ElementSpec(.value, "Percentage", symbol: "percent", role: .text, samples: ["100%"], priority: 90, isSizable: false),
                ElementSpec(.chart, "Chart", symbol: "chart.bar", role: .chart, priority: 100, isSizable: false, isBlock: true),
            ],
            isAvailable: { BatteryAvailability.hasBattery },
            supportsCustomLayout: false
        ),
        .batteryScreenTime: WidgetKindSpec(
            title: "Screen Activity", summary: "How long the displays were on and off today (or the day picked on Daily Usage).",
            symbol: "display", iconColors: green, category: .battery, family: .battery,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 4, height: 1),
            maximumSize: GridSize(width: 8, height: 2),
            elements: [ElementSpec(.chart, "Times", symbol: "clock", role: .feature, priority: 100, isSizable: false, isBlock: true,
                                   isRequired: true)],
            isAvailable: { BatteryAvailability.hasBattery },
            supportsCustomLayout: false
        ),
        .batteryChart: WidgetKindSpec(
            title: "Battery Chart", summary: "Today's charge level, like the iPhone's battery chart.",
            symbol: "chart.bar.fill", iconColors: green, category: .battery, family: .battery,
            minimumSize: GridSize(width: 3, height: 1), defaultSize: GridSize(width: 4, height: 2),
            maximumSize: GridSize(width: 12, height: 3),
            elements: [ElementSpec(.chart, "Chart", symbol: "chart.bar", role: .chart, priority: 100, isSizable: false, isBlock: true)]
                + ElementSpec.reading(["100%"], caption: "Today").filter { $0.id != .symbol },
            isAvailable: { BatteryAvailability.hasBattery }
        ),
    ]

    private static let green: [IslandTheme.RGB] = [.rgb(0.4, 0.9, 0.45), .rgb(0.16, 0.7, 0.3)]

    private static func figure(_ title: String, _ summary: String, symbol: String, samples: [String],
                               isAvailable: @escaping @Sendable () -> Bool = { BatteryAvailability.hasBattery }) -> WidgetKindSpec {
        WidgetKindSpec(
            title: title, summary: summary, symbol: symbol, iconColors: green, category: .battery, family: .battery,
            minimumSize: GridSize(width: 1, height: 1), defaultSize: GridSize(width: 2, height: 1),
            maximumSize: GridSize(width: 4, height: 2),
            elements: ElementSpec.reading(samples, caption: title),
            isAvailable: isAvailable,
            stacksElements: true
        )
    }
}

/// What this Mac's battery offers, read once (the gallery asks for every kind): a desktop Mac has
/// no battery widgets, and the temperature's only where the system shows the sensor to apps.
nonisolated enum BatteryAvailability {
    private static let details: BatteryDetails? = BatteryDetails.read(power: PowerMonitor.readIOKit())

    static var hasBattery: Bool { details != nil }
    static var hasTemperature: Bool { details?.temperature != nil }
}
