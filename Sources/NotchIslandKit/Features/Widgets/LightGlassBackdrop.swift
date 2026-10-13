import Foundation
import Observation

/// Liquid Glass, in Light Mode and in Dark Mode: each has a widget background of its own, the one the
/// user set on the Home page's widgets by hand there (October 13). While the Mac is in that Mode with
/// Liquid Glass chosen, wherever the system's Liquid Glass slider stands — however that came about —
/// every widget, whatever its background (None, Plate or another colour), gets that Mode's Colour
/// background as the Mode begins, set as the user would set it in Settings ▸ Widgets
/// (`IslandWidget.background`): shown there, changed or turned off per widget.
///
/// What a widget had before is kept and given back once Liquid Glass ends (another style) — unless
/// the user changed the widget's background meanwhile (`WidgetStore.takeLookEdits`): then theirs
/// stays, and it is not touched again until the next time a Mode begins (`optedOut`, cleared then:
/// asked for, October 13). Going from one Mode to the other gives every widget the other Mode's
/// background, keeping what it had before either. A board put back whole (⌘Z, a notch style) that
/// brings a widget's old background back is not the user's change: it is given the Mode's again.
@MainActor @Observable final class LightGlassBackdrop {
    /// A Mode's background: its colour and strength.
    nonisolated struct Look: Equatable {
        let color: IslandTheme.RGB
        let opacity: Double
    }

    /// Light Mode's: a light grey at 50 %. Dark Mode's: black at 40 %.
    static let light = Look(color: IslandTheme.RGB(red: 0.7117466517857143, green: 0.7117466517857143, blue: 0.7117466517857143),
                            opacity: 0.5)
    static let dark = Look(color: IslandTheme.RGB(red: 0, green: 0, blue: 0), opacity: 0.4)

    nonisolated static let key = "ni2.lightGlassBackdrop"

    /// A widget's background before it was set here.
    private struct Original: Codable, Equatable {
        var background: WidgetBackground
        var color: IslandTheme.RGB?
        var opacity: Double?
    }

    private struct State: Codable {
        /// The widgets given a Mode's background now, with what they had before.
        var applied: [UUID: Original] = [:]
        /// Widgets whose background the user changed after it was set here: left alone until the
        /// next time a Mode begins.
        var optedOut: Set<UUID> = []
        /// The Mode on Liquid Glass at the last look ("light", "dark"; nil: another style): its
        /// beginning is what gives every widget its background. Light Mode alone before October 13
        /// (`wasActive`).
        var mode: String?
        /// 2 since October 13: until then a board put back whole opted its widgets out, so the
        /// opt-outs of version 1 are forgotten.
        var version = 1
        /// The notice in Settings ▸ Widgets about the backgrounds set here was closed or answered
        /// (`dismissNotice`, `revert`): it shows again the next time a Mode begins.
        var noticeDismissed = false

        private enum CodingKeys: String, CodingKey { case applied, optedOut, mode, version, wasActive, noticeDismissed }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(applied, forKey: .applied)
            try container.encode(optedOut, forKey: .optedOut)
            try container.encodeIfPresent(mode, forKey: .mode)
            try container.encode(version, forKey: .version)
            try container.encode(noticeDismissed, forKey: .noticeDismissed)
        }

        init() { version = Self.current }
        static let current = 2

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            applied = try container.decodeIfPresent([UUID: Original].self, forKey: .applied) ?? [:]
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            noticeDismissed = try container.decodeIfPresent(Bool.self, forKey: .noticeDismissed) ?? false
            mode = try container.decodeIfPresent(String.self, forKey: .mode)
                ?? ((try? container.decodeIfPresent(Bool.self, forKey: .wasActive)) ?? !applied.isEmpty ? "light" : nil)
            optedOut = version < Self.current ? [] : try container.decodeIfPresent(Set<UUID>.self, forKey: .optedOut) ?? []
            version = Self.current
        }
    }

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var state: State
    @ObservationIgnored private var isPending = false

    /// Settings ▸ Widgets tells the user their widgets' backgrounds were set here, with a way back
    /// (asked for, October 13): while some are, until the notice is closed or answered.
    private(set) var showsNotice = false
    /// The Mode whose background was set ("light", "dark"), for the notice's words.
    var noticeMode: String? { state.mode }

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        state = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    /// Follows the Mac's appearance, the glass chosen and every board from now on.
    func start() {
        evaluate()
        track()
    }

    /// The Mode whose background widgets get now: Liquid Glass chosen — clear or frosted (kept over
    /// the whole slider, asked for October 13); nil with another style.
    private var mode: String? {
        guard let model, model.preferences.glassStyle == .liquidGlass else { return nil }
        return SystemAppearance.shared.isDark ? "dark" : "light"
    }

    private func track() {
        guard let model else { return }
        withObservationTracking {
            _ = SystemAppearance.shared.isDark
            _ = SystemAppearance.shared.glassTint
            _ = model.preferences.glassStyle
            _ = model.preferences.header.orderedPages
            for store in boards(model) { _ = store.board }
        } onChange: { [weak self] in
            // Once the change is made, and once for a burst of them.
            DispatchQueue.main.async {
                guard let self, !self.isPending else { return }
                self.isPending = true
                DispatchQueue.main.async {
                    self.isPending = false
                    self.evaluate()
                    self.track()
                }
            }
        }
    }

    /// Every page's board.
    private func boards(_ model: AppModel) -> [WidgetStore] {
        model.preferences.header.orderedPages.filter(\.isBoard).map { model.boards.store(for: $0) }
    }

    private static func has(_ look: Look, _ widget: IslandWidget) -> Bool {
        widget.background == .tinted && widget.backgroundColor == look.color && widget.backgroundOpacity == look.opacity
    }

    private func evaluate() {
        // Settings' pictures switch the style for a moment: nothing of the user's is changed then.
        guard let model, !model.isPictureScene else { return }
        let stores = boards(model)
        var changed = false
        // A widget given a Mode's background that the user changed since: theirs from now on.
        for store in stores {
            for id in store.takeLookEdits().map(\.rawValue) where state.applied[id] != nil {
                state.applied[id] = nil
                state.optedOut.insert(id)
                changed = true
            }
        }
        let mode = mode
        if mode != state.mode {
            // Begun, ended or the other Mode: whatever the user kept of theirs is given the Mode's anew.
            state.mode = mode
            state.optedOut = []
            state.noticeDismissed = false
            changed = true
        }
        if let mode {
            let look = mode == "dark" ? Self.dark : Self.light
            for store in stores {
                for widget in store.board.widgets where !Self.has(look, widget) {
                    let id = widget.id.rawValue
                    guard !state.optedOut.contains(id) else { continue }
                    // Given a Mode's before (the other Mode's, or put back by a board restored
                    // whole): this Mode's now, with the original kept from the first time.
                    if state.applied[id] == nil {
                        state.applied[id] = Original(background: widget.background, color: widget.backgroundColor,
                                                     opacity: widget.backgroundOpacity)
                    }
                    store.updateOutsideHistory(widget.id) {
                        $0.background = .tinted
                        $0.backgroundColor = look.color
                        $0.backgroundOpacity = look.opacity
                    }
                    changed = true
                }
            }
        } else if !state.applied.isEmpty {
            for (id, original) in state.applied {
                let widgetID = WidgetID(rawValue: id)
                guard let store = model.boards.store(containing: widgetID) else { continue }
                store.updateOutsideHistory(widgetID) {
                    $0.background = original.background
                    $0.backgroundColor = original.color
                    $0.backgroundOpacity = original.opacity
                }
            }
            state.applied = [:]
            changed = true
        }
        // Widgets gone (deleted, their page removed) are forgotten.
        let present = Set(stores.flatMap { ($0.board.widgets + $0.board.parked).map(\.id.rawValue) })
        let before = (state.applied.count, state.optedOut.count)
        state.applied = state.applied.filter { present.contains($0.key) }
        state.optedOut = state.optedOut.intersection(present)
        if before != (state.applied.count, state.optedOut.count) { changed = true }
        if changed { save() }
        let shows = !state.applied.isEmpty && !state.noticeDismissed
        if showsNotice != shows { showsNotice = shows }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: Self.key) }
    }

    /// Every widget given the Mode's background back to what it had (the user's saved settings),
    /// and left alone until a Mode begins again.
    func revert() {
        guard let model else { return }
        for (id, original) in state.applied {
            let widgetID = WidgetID(rawValue: id)
            guard let store = model.boards.store(containing: widgetID) else { continue }
            store.updateOutsideHistory(widgetID) {
                $0.background = original.background
                $0.backgroundColor = original.color
                $0.backgroundOpacity = original.opacity
            }
            state.optedOut.insert(id)
        }
        state.applied = [:]
        state.noticeDismissed = true
        save()
        showsNotice = false
    }

    /// The notice closed: the backgrounds stay as they were set.
    func dismissNotice() {
        state.noticeDismissed = true
        save()
        showsNotice = false
    }
}
