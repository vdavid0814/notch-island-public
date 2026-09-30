import Foundation

/// Volume, display and keyboard brightness (`LevelWidget`, `KeyboardWidget`).
nonisolated enum LevelSpecs {
    static let all: [IslandWidgetKind: WidgetKindSpec] = [
        .volume: level("Volume", "The output volume as a slider.", symbol: "speaker.wave.2.fill",
                       colors: [.rgb(0.6, 0.5, 1.0), .rgb(0.4, 0.28, 0.92)], category: .media),
        .brightness: level("Display Brightness", "The display brightness as a slider.", symbol: "sun.max.fill",
                           colors: [.rgb(1.0, 0.88, 0.35), .rgb(0.98, 0.7, 0.1)], category: .system),
        .keyboardBrightness: level("Keyboard Brightness", "The keyboard backlight as a slider.", symbol: "light.max",
                                   colors: [.rgb(0.5, 0.85, 0.95), .rgb(0.2, 0.6, 0.8)], category: .system),
    ]

    private static func level(_ title: String, _ summary: String, symbol: String, colors: [IslandTheme.RGB],
                              category: WidgetCategory) -> WidgetKindSpec {
        WidgetKindSpec(
            title: title, summary: summary, symbol: symbol, iconColors: colors, category: category, family: .levels,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 5, height: 1),
            maximumSize: GridSize(width: 12, height: 2),
            elements: [
                // Beside a slider: the symbol from a widget 90 pt wide, the value from 150 (in a ring,
                // the value from a 44-pt ring).
                ElementSpec(.levelIcon, "Symbol", symbol: "speaker.wave.2", role: .symbol, priority: 60, minRoom: MinRoom(width: 90)),
                ElementSpec(.levelValue, "Value", symbol: "number", role: .text, samples: ["100%"], priority: 40,
                            minRoom: MinRoom(width: 150)),
            ],
            layouts: [.automatic, .slider, .ring],
            canMirror: true
        )
    }
}
