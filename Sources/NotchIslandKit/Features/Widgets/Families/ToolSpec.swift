import Foundation

/// The shelf, Siri and the tools (`ShelfWidget`, `AssistantWidget`).
nonisolated enum ToolSpecs {
    static let all: [IslandWidgetKind: WidgetKindSpec] = [
        .shelf: WidgetKindSpec(
            title: "Shelf",
            summary: "Files dropped on the notch, ready to drag out.",
            symbol: "tray.full.fill",
            iconColors: [.rgb(0.35, 0.78, 1.0), .rgb(0.12, 0.48, 1.0)],
            category: .tools, family: .tools,
            minimumSize: GridSize(width: 2, height: 1), defaultSize: GridSize(width: 5, height: 1),
            maximumSize: GridSize(width: 12, height: 3),
            elements: [
                // Previews 22 pt tall at least, which a widget 56 pt tall gives.
                ElementSpec(.previews, "File previews", symbol: "photo.on.rectangle", role: .image, priority: 50,
                            minRoom: MinRoom(height: 56), isSizable: false, isBlock: true),
                ElementSpec(.shelfCount, "Item count", symbol: "number", role: .text,
                            samples: ["Drop files here", "Drop files", "Drop", "99 items"], priority: 90),
                ElementSpec(.shelfActions, "AirDrop and Clear buttons", symbol: "square.and.arrow.up", role: .button,
                            priority: 40, minRoom: MinRoom(width: 200), isSizable: false, parts: ["airDrop", "clear"]),
            ]
        ),
        .assistant: WidgetKindSpec(
            title: "Siri",
            summary: "Search apps and files, or ask Apple Intelligence, right in the notch.",
            symbol: "siri",
            iconColors: [.rgb(0.36, 0.62, 1.0), .rgb(0.86, 0.3, 0.95)],
            category: .tools, family: .tools,
            minimumSize: GridSize(width: 1, height: 1), defaultSize: GridSize(width: 2, height: 1),
            maximumSize: GridSize(width: 6, height: 3),
            elements: [
                ElementSpec(.assistantLabel, "Name", symbol: "textformat", role: .text, samples: ["Siri"], priority: 50,
                            minRoom: MinRoom(width: 70), acceptsLabel: true),
            ],
            supportsCustomLayout: false
        ),
        .shortcut: tool("Shortcut", "Run one of your shortcuts.", symbol: "square.stack.3d.up.fill",
                        elements: [ElementSpec(.symbol, "Symbol", symbol: "star", role: .symbol, priority: 100, isRequired: true),
                                   ElementSpec(.label, "Name", symbol: "textformat", role: .text, samples: ["My Shortcut"], priority: 60,
                                               acceptsLabel: true)],
                        sizes: (GridSize(width: 1, height: 1), GridSize(width: 2, height: 1), GridSize(width: 4, height: 2))),
        .appLauncher: tool("App Launcher", "Up to eight apps, a click away.", symbol: "square.grid.2x2.fill",
                           elements: [ElementSpec(.appIcons, "Apps", symbol: "square.grid.2x2", role: .feature, priority: 100, isSizable: false, isBlock: true,
                                                  isRequired: true)],
                           sizes: (GridSize(width: 1, height: 1), GridSize(width: 3, height: 1), GridSize(width: 12, height: 2)),
                           customLayout: false),
        .clipboard: tool("Clipboard", "The last things you copied; a click copies one again.", symbol: "doc.on.clipboard.fill",
                         elements: [ElementSpec(.clipList, "Copies", symbol: "list.bullet", role: .feature, priority: 100, isBlock: true,
                                                isRequired: true)],
                         sizes: (GridSize(width: 3, height: 1), GridSize(width: 4, height: 2), GridSize(width: 12, height: 3)),
                         config: { $0.count = 3 }, customLayout: false),
        .photoFrame: tool("Photo", "A picture of your choosing.", symbol: "photo.fill",
                          elements: [ElementSpec(.photo, "Photo", symbol: "photo", role: .image, priority: 100, isBlock: true,
                                                 isRequired: true)],
                          sizes: (GridSize(width: 1, height: 1), GridSize(width: 3, height: 2), GridSize(width: 12, height: 3)),
                          customLayout: false),
    ]

    private static func tool(_ title: String, _ summary: String, symbol: String, elements: [ElementSpec],
                             sizes: (minimum: GridSize, standard: GridSize, maximum: GridSize),
                             config: (inout WidgetConfig) -> Void = { _ in }, customLayout: Bool = true) -> WidgetKindSpec {
        var defaults = WidgetConfig()
        config(&defaults)
        return WidgetKindSpec(
            title: title, summary: summary, symbol: symbol, iconColors: [.rgb(0.62, 0.64, 0.7), .rgb(0.38, 0.4, 0.47)],
            category: .tools, family: .tools,
            minimumSize: sizes.minimum, defaultSize: sizes.standard, maximumSize: sizes.maximum,
            elements: elements,
            defaultConfig: defaults,
            supportsCustomLayout: customLayout
        )
    }
}
