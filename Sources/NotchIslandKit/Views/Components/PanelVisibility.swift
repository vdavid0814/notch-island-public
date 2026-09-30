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

private struct WhileShown: ViewModifier {
    let start: () -> Void
    let stop: () -> Void
    @Environment(\.isIslandPanelHidden) private var isHidden
    @State private var isRunning = false

    func body(content: Content) -> some View {
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
    @Environment(\.isIslandPanelHidden) private var isHidden
    /// The editor's canvas is a picture: one entry, never a tick.
    @Environment(\.widgetRenderMode) private var renderMode

    init(_ schedule: Schedule, @ViewBuilder content: @escaping (TimelineViewDefaultContext) -> Content) {
        self.schedule = schedule
        self.content = content
    }

    var body: some View {
        TimelineView(PanelTimeline(base: schedule, isPaused: isHidden || renderMode == .canvas), content: content)
    }
}
