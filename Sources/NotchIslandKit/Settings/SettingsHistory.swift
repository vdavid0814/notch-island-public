import Foundation

/// Where Settings is: its page, and the widget open in Customize over it.
nonisolated struct SettingsPlace: Equatable, Sendable {
    var pane: IslandSettingsPane
    var customizing: WidgetID?
}

/// Settings' steps back and forward, as a browser's: two fingers to the right go back where the
/// user was (out of Customize to Widgets, to the page before), to the left forward again (asked
/// for: as in Siri, `AssistantModel.swipeBack`).
@MainActor final class SettingsHistory {
    enum Step: Sendable { case back, forward }

    private(set) var back: [SettingsPlace] = []
    private(set) var forward: [SettingsPlace] = []
    /// The step being taken: the page deck slides its way (`SettingsPageDeckView.show`).
    private var pendingStep: Step?
    private var isApplying = false

    static let limit = 40

    /// The user went somewhere (a sidebar row, a link, Customize opened or closed).
    func moved(from old: SettingsPlace, to new: SettingsPlace) {
        guard !isApplying, old != new else { return }
        back.append(old)
        if back.count > Self.limit { back.removeFirst(back.count - Self.limit) }
        forward.removeAll()
    }

    /// A change that is not a step of the user's (Customize closing with Settings).
    func withoutRecording(_ change: () -> Void) {
        isApplying = true
        change()
        isApplying = false
    }

    /// False with nowhere to go. A place the user is at already is passed over.
    func step(_ step: Step, from here: SettingsPlace, apply: (SettingsPlace) -> Void) -> Bool {
        while let place = step == .back ? back.popLast() : forward.popLast() {
            guard place != here else { continue }
            if step == .back { forward.append(here) } else { back.append(here) }
            // Only a step to another page slides it (Customize flies its widget as it always does).
            pendingStep = place.pane != here.pane ? step : nil
            withoutRecording { apply(place) }
            return true
        }
        return false
    }

    /// The step the page now shown came by, once.
    func takeStep() -> Step? {
        defer { pendingStep = nil }
        return pendingStep
    }
}
