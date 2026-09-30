import SwiftUI

extension Color {
    init(_ cover: ArtworkColor) {
        self.init(red: cover.red, green: cover.green, blue: cover.blue)
    }
}

extension WidgetTint {
    var color: Color? {
        switch self {
        case .automatic: nil
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .gray: .gray
        }
    }
}

extension View {
    /// A widget's two sides swapped (`IslandWidget.mirrored`): the row lays out right to left.
    /// Each side keeps its own direction with `ownDirection()`, so text and sliders read as usual.
    func mirroredSides(_ mirrored: Bool) -> some View {
        environment(\.layoutDirection, mirrored ? .rightToLeft : .leftToRight)
    }

    func ownDirection() -> some View {
        environment(\.layoutDirection, .leftToRight)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
