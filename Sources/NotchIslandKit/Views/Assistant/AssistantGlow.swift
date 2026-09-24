import SwiftUI

/// Siri's colours: a band of flowing Apple Intelligence colour over a soft, still glow of the same
/// colours, shown while the assistant is answering.
///
/// The flow redraws at 30 fps only while it is on screen and only the sharp band moves (the blur is
/// not recomputed per frame); under Reduce Motion or in Low Power Mode it stands still.
struct AssistantGlow: View {
    var isFlowing: Bool

    static let colors: [Color] = [
        Color(red: 0.25, green: 0.55, blue: 1.0),
        Color(red: 0.65, green: 0.35, blue: 1.0),
        Color(red: 1.0, green: 0.35, blue: 0.65),
        Color(red: 1.0, green: 0.62, blue: 0.25),
        Color(red: 0.25, green: 0.55, blue: 1.0),
    ]

    static var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isFlowing, !reduceMotion, !model.activity.prefersReducedWork {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                band(phase: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            band(phase: 0)
        }
    }

    private func band(phase: TimeInterval) -> some View {
        let angle = Angle.degrees((phase * 220).truncatingRemainder(dividingBy: 360))
        return Capsule()
            .fill(AngularGradient(colors: Self.colors, center: .center, angle: angle))
            .frame(height: 4)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: Self.colors, startPoint: .leading, endPoint: .trailing))
                    .blur(radius: 8)
                    .opacity(0.7)
            }
            .accessibilityHidden(true)
    }
}
