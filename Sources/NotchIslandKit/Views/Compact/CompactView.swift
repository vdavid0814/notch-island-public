import SwiftUI

/// An ongoing activity in the pill that hugs the notch: one glyph in each ear, never taller than the
/// notch itself (a taller pill reads as a window stuck to the screen).
struct CompactView: View {
    let activity: CompactActivity

    @Environment(AppModel.self) private var model

    var body: some View {
        let layout = model.layout
        let split = NotchSplit(
            layout: layout,
            presentation: .compact(activity),
            outerInset: Metrics.Compact.inset,
            clearance: Metrics.Compact.notchClearance
        )
        let glyphSide = max(0, layout.notch.height - 2 * Metrics.Compact.inset)

        switch activity {
        case .nowPlaying:
            NowPlayingCompact(split: split, height: layout.notch.height, glyphSide: glyphSide)
        case .timer:
            TimerCompact(mode: .countdown, split: split, height: layout.notch.height, glyphSide: glyphSide)
        case .stopwatch:
            TimerCompact(mode: .stopwatch, split: split, height: layout.notch.height, glyphSide: glyphSide)
        case .recording:
            RecordingCompact(split: split, height: layout.notch.height, glyphSide: glyphSide)
        case .update:
            UpdateCompact(split: split, height: layout.notch.height, glyphSide: glyphSide)
        }
    }
}
