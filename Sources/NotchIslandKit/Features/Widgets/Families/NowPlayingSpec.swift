import Foundation

/// Now Playing (`NowPlayingWidget`).
nonisolated enum NowPlayingSpecs {
    static let all: [IslandWidgetKind: WidgetKindSpec] = [
        .nowPlaying: WidgetKindSpec(
            title: "Now Playing",
            summary: "Artwork, track and playback controls for any player.",
            symbol: "play.circle.fill",
            iconColors: [.rgb(1.0, 0.36, 0.47), .rgb(0.93, 0.16, 0.33)],
            category: .media, family: .nowPlaying,
            minimumSize: GridSize(width: 3, height: 1), defaultSize: GridSize(width: 7, height: 3),
            maximumSize: GridSize(width: 12, height: 3),
            elements: [
                // Beside the text it needs 110 pt left for the text; in the one-line layout, a
                // widget 150 wide.
                ElementSpec(.artwork, "Artwork", symbol: "photo", role: .image, priority: 60, minRoom: MinRoom(width: 110)),
                ElementSpec(.trackInfo, "Title", symbol: "textformat", role: .text,
                            samples: ["Unknown Title", "Nothing Playing"], priority: 100),
                ElementSpec(.artist, "Artist", symbol: "person", role: .text,
                            samples: ["Music you play appears here."], priority: 70),
                ElementSpec(.progress, "Progress bar", symbol: "minus", role: .line, priority: 30,
                            minRoom: MinRoom(height: 84), isSizable: false, isBlock: true),
                ElementSpec(.playbackButtons, "Play and pause", symbol: "playpause.fill", role: .button, priority: 90),
                ElementSpec(.skipButtons, "Previous and next buttons", symbol: "forward.fill", role: .button, priority: 50,
                            minRoom: MinRoom(width: 170), isSizable: false, parts: ["previous", "next"]),
            ],
            layouts: [.automatic, .beside, .cover, .minimal],
            backgrounds: WidgetBackground.allCases,
            canMirror: true
        ),
    ]
}
