import AppKit
import SwiftUI

/// A drag in progress: where the item is under the pointer, and the place it will land on.
struct DragSession<ID: Hashable, Target: Equatable>: Equatable {
    let id: ID
    /// nil while moving.
    let handle: ResizeHandle?
    let start: CGRect
    var live: CGRect
    var candidate: Target
    var isValid: Bool

    init(id: ID, handle: ResizeHandle?, start: CGRect, candidate: Target) {
        self.id = id
        self.handle = handle
        self.start = start
        live = start
        self.candidate = candidate
        isValid = true
    }

    /// Lands on `candidate`, ticking when it is a new place.
    mutating func land(on candidate: Target, isValid: Bool) {
        if candidate != self.candidate { SnapTick.perform() }
        self.candidate = candidate
        self.isValid = isValid
    }
}

/// The "click" of snapping: one tick per new landing place.
enum SnapTick {
    static func perform() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

extension Gesture {
    /// Holds `isDragging` true for as long as the drag is really in progress. Unlike `onEnded`, a
    /// `GestureState` also resets when the drag is cancelled (released outside the panel, the panel
    /// losing the pointer): `finishingCancelledDrag` then finishes the drag instead of the item
    /// staying stuck half-way.
    func tracking(_ isDragging: GestureState<Bool>) -> GestureStateGesture<Self, Bool> {
        updating(isDragging) { _, dragging, _ in dragging = true }
    }
}

extension View {
    /// Calls `finish` when a drag `tracking` `isDragging` stops, whether it ended or was cancelled
    /// (`finish` does nothing for a drag already finished).
    func finishingCancelledDrag(_ isDragging: Bool, finish: @escaping () -> Void) -> some View {
        onChange(of: isDragging) { _, dragging in
            if !dragging { finish() }
        }
    }
}
