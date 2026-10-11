import SwiftUI

/// The panel is kept alive while the island shows something else (`IslandContentStack.keptPage`),
/// hidden. What its views would keep running on their own — clocks, system monitors — must wait
/// until it is shown again: at rest a hidden clock ticking once a second cost Energy Impact 2–5
/// (measured).
extension View {
    /// `start` when the view appears shown or its hidden panel is shown again; `stop` when it
    /// disappears or its panel is hidden. The panel's replacement for `onAppear`/`onDisappear`.
    func whileShown(_ start: @escaping () -> Void, stop: @escaping () -> Void = {}) -> some View {
        modifier(WhileShown(start: start, stop: stop))
    }
}

/// A page of the open panel kept built while another one is shown (`ExpandedView`): whether it is
/// the shown one. An object only the leaves that pause read (`WhileShown`, `PanelTimelineView`, the
/// scrubber's line), so a page switch re-derives only them: an environment value written at each
/// switch goes through every view of both pages (Settings' deck: 60–80 ms a switch, measured).
@Observable final class PanelPageShown {
    var isShown: Bool
    init(_ isShown: Bool) { self.isShown = isShown }
}

extension EnvironmentValues {
    /// The page this view is on, in the open panel (nil: not on one of its pages).
    @Entry var panelPageShown: PanelPageShown? = nil
}

private struct WhileShown: ViewModifier {
    let start: () -> Void
    let stop: () -> Void
    @Environment(\.isIslandPanelHidden) private var isPanelHidden
    @Environment(\.panelPageShown) private var pageShown
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.isHeaderPicture) private var isHeaderPicture
    @State private var isRunning = false

    func body(content: Content) -> some View {
        let isHidden = isPanelHidden || pageShown?.isShown == false
            || ((isPreview || isHeaderPicture) && !SettingsPresence.shared.isShown)
        content
            .onAppear { set(!isHidden) }
            .onDisappear { set(false) }
            .onChange(of: isHidden) { _, hidden in set(!hidden) }
    }

    private func set(_ running: Bool) {
        guard running != isRunning else { return }
        isRunning = running
        running ? start() : stop()
    }
}

/// A timeline that stands still while its panel is hidden: one entry, then none until shown again
/// (a new schedule, which the timeline starts over from the present).
struct PanelTimeline<Base: TimelineSchedule>: TimelineSchedule {
    let base: Base
    let isPaused: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        if isPaused { return AnyIterator(CollectionOfOne(startDate).makeIterator()) }
        var entries = base.entries(from: startDate, mode: mode).makeIterator()
        return AnyIterator { entries.next() }
    }
}

/// A `TimelineView` that stands still while its panel is hidden (`PanelTimeline`). A view of its
/// own, so only the timeline reads the panel's visibility: read by a whole widget, showing the
/// panel re-derived the widget (the timer's ruler: ~15 ms per open, measured).
struct PanelTimelineView<Schedule: TimelineSchedule, Content: View>: View {
    let schedule: Schedule
    @ViewBuilder let content: (TimelineViewDefaultContext) -> Content
    @Environment(\.isIslandPanelHidden) private var isPanelHidden
    @Environment(\.panelPageShown) private var pageShown
    /// The editor's canvas is a picture: one entry, never a tick.
    @Environment(\.widgetRenderMode) private var renderMode
    /// Settings' pictures (the gallery's previews, the stage's header) tick only while Settings
    /// is on screen: it is kept while closed (`SettingsWindow`), and their clocks woke the app
    /// every second for nothing.
    @Environment(\.isWidgetPreview) private var isPreview
    @Environment(\.isHeaderPicture) private var isHeaderPicture

    private var isHidden: Bool {
        isPanelHidden || pageShown?.isShown == false || ((isPreview || isHeaderPicture) && !SettingsPresence.shared.isShown)
    }

    init(_ schedule: Schedule, @ViewBuilder content: @escaping (TimelineViewDefaultContext) -> Content) {
        self.schedule = schedule
        self.content = content
    }

    var body: some View {
        TimelineView(PanelTimeline(base: schedule, isPaused: isHidden || renderMode == .canvas), content: content)
    }
}
