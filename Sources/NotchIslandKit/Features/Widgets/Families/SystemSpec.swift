import Foundation

/// The Mac's own readings (`SystemStatsWidget`).
nonisolated enum SystemSpecs {
    static let all: [IslandWidgetKind: WidgetKindSpec] = [
        .systemStats: WidgetKindSpec(
            title: "System",
            summary: "Processor and memory load, read only while shown.",
            symbol: "cpu.fill",
            iconColors: mint,
            category: .system, family: .system,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 3, height: 1),
            maximumSize: GridSize(width: 6, height: 3),
            elements: [
                ElementSpec(.cpuLoad, "Processor", symbol: "cpu", role: .chart, samples: ["CPU", "100%"], priority: 60),
                ElementSpec(.memoryLoad, "Memory", symbol: "memorychip", role: .chart, samples: ["Memory", "RAM", "100%"],
                            priority: 50),
            ]
        ),
        .network: reading("Network", "Download and upload speed, read only while shown.", symbol: "network",
                          samples: ["888 MB/s"]),
        .diskSpace: reading("Disk Space", "Free space on the startup disk.", symbol: "internaldrive.fill", samples: ["888 GB"]),
        .uptime: reading("Uptime", "How long since the Mac started, and how warm it runs.", symbol: "clock.arrow.circlepath",
                         samples: ["88d 88h"]),
    ]

    private static let mint: [IslandTheme.RGB] = [.rgb(0.36, 0.85, 0.62), .rgb(0.1, 0.62, 0.45)]

    private static func reading(_ title: String, _ summary: String, symbol: String, samples: [String]) -> WidgetKindSpec {
        WidgetKindSpec(
            title: title, summary: summary, symbol: symbol, iconColors: mint, category: .system, family: .system,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 3, height: 1),
            maximumSize: GridSize(width: 6, height: 3),
            elements: ElementSpec.reading(samples, caption: title),
            isImplemented: false
        )
    }
}
