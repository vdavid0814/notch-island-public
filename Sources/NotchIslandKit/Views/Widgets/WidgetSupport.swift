import SwiftUI

extension Color {
    init(_ cover: ArtworkColor) {
        self.init(red: cover.red, green: cover.green, blue: cover.blue)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

/// The widget's own accent, when it has one (otherwise the environment's).
struct OptionalTint: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.tint(color)
        } else {
            content
        }
    }
}
