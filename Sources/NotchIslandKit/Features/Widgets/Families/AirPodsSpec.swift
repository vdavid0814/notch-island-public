import Foundation

/// The AirPods' batteries, as last reported.
nonisolated enum AirPodsSpecs {
    static let all: [IslandWidgetKind: WidgetKindSpec] = [
        .airPodsBattery: WidgetKindSpec(
            title: "AirPods Battery",
            summary: "Your AirPods' charge, as last reported.",
            symbol: "airpods",
            iconColors: [.rgb(0.92, 0.92, 0.94), .rgb(0.62, 0.63, 0.68)],
            category: .system, family: .airPods,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 3, height: 1),
            maximumSize: GridSize(width: 6, height: 3),
            elements: ElementSpec.reading(["100%"], caption: "AirPods"),
            stacksElements: true
        ),
    ]
}
