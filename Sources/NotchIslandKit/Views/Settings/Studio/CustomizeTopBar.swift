import Foundation
import Observation
import SwiftUI

/// What Customize's editor and its top bar share: the picked part, where the parts are, and the
/// widget's history for undo and redo.
@Observable final class ElementEditing {
    /// The part picked in the editor.
    var selected: ElementID?
    /// Parts picked together with ⌘-click (two or more, `selected` among them; empty otherwise):
    /// sized at once in the inspector, deleted at once.
    var group: Set<ElementID> = []

    /// The part copied with ⌘C, and the widget as it was then (its look is read from it).
    var copied: (id: ElementID, widget: IslandWidget)?

    /// Every part picked: the group, or the one picked.
    var picked: Set<ElementID> { group.isEmpty ? Set([selected].compactMap { $0 }) : group }

    /// ⌘-click on `id`: into the parts picked, or out of them.
    func toggle(_ id: ElementID) {
        var picked = self.picked
        if picked.contains(id) {
            picked.remove(id)
            if selected == id { selected = picked.first }
        } else {
            picked.insert(id)
            selected = id
        }
        group = picked.count >= 2 ? picked : []
    }
    /// Each part where it is drawn (its ink, with its offset), in the widget's points.
    var parts: [ElementID: CGRect] = [:]
    /// Each part's layout box, which it is scaled from (`ElementScale.applied`).
    var boxes: [ElementID: CGRect] = [:]
    /// The saved versions' list, opened over the editor from the top bar.
    var showsVersions = false
    /// The text tried on more lines in the editor (`LabelFit.preview`).
    var linePreview: ElementID?
    /// The part of a playback line picked in the panel under the editor (its line, a time).
    var progressPart: ProgressLook.Part?
    /// The ruler's unit name is picked in the panel under the editor (the inspector sets its type).
    var picksRulerUnit = false
    /// A part's size as drawn, copied in the inspector to give another part (Paste Size).
    var copiedSize: CGSize?
    /// The widget as it was when Customize opened on it, and whether the editor shows it instead
    /// (Before and after).
    var original: IslandWidget?
    var showsOriginal = false
    /// Where that list is, in Customize's own points (`space`): a click outside it closes it.
    var versionsFrame: CGRect = .zero
    static let space = "customize"

    private(set) var undoStack: [IslandWidget] = []
    private(set) var redoStack: [IslandWidget] = []
    /// The widget an undo or redo is putting back: its change is not one to record.
    @ObservationIgnored private var restoring: IslandWidget?
    @ObservationIgnored private var lastRecord: TimeInterval = 0

    /// Changes this close together (a slider's steps) are one step back.
    static let coalescing: TimeInterval = 0.5
    static let limit = 100

    /// The parts the picked one overlaps.
    var overlapping: [ElementID] {
        guard let selected, let frame = parts[selected] else { return [] }
        return parts.filter { $0.key != selected && $0.value.intersects(frame) }.map(\.key)
    }

    /// A change that is not one to undo (the widget anchored at its size as Customize opens).
    func skipRecording(_ widget: IslandWidget) {
        restoring = widget
    }

    /// The widget changed from `old` (anything in Customize: a move, a switch, the background).
    func record(_ old: IslandWidget, _ new: IslandWidget) {
        if let restoring, restoring == new {
            self.restoring = nil
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastRecord = now }
        redoStack.removeAll()
        if now - lastRecord < Self.coalescing, !undoStack.isEmpty { return }
        undoStack.append(old)
        if undoStack.count > Self.limit { undoStack.removeFirst() }
    }

    /// The widget as it was before the last change (`current` kept for redo); nil: nothing to undo.
    func undo(from current: IslandWidget) -> IslandWidget? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        restoring = previous
        lastRecord = 0
        return previous
    }

    func redo(from current: IslandWidget) -> IslandWidget? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        restoring = next
        lastRecord = 0
        return next
    }
}

/// Over the editor: saving the widget's look as a version and opening the saved ones, putting the
/// picked part or the whole widget back, whether the picked part is drawn under or over those it overlaps,
/// Done, and undo and redo.
struct CustomizeTopBar: View {
    let widget: IslandWidget
    let editing: ElementEditing
    let versions: WidgetVersionStore
    let close: () -> Void

    @Environment(AppModel.self) private var model
    /// The last choice shown, kept while the picked half fades out.
    @State private var lastLayering: Layering = .below
    /// The version just saved: its button says so for a moment.
    @State private var justSaved: UUID?


    var body: some View {
        // As large as the band allows: never wider than it (it would push Customize's panels apart).
        ViewThatFits(in: .horizontal) {
            bar(.large, titled: true)
            bar(.regular, titled: true)
            bar(.regular, titled: false)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The bar at `size`; not `titled`, Save Widget and Open Widgets show their icons alone.
    private func bar(_ size: ControlSize, titled: Bool) -> some View {
        let selected = editing.selected
        let overlapping = editing.overlapping
        // The columns 10 points apart at the least, the room left shared between them.
        return HStack(alignment: .center, spacing: 0) {
            // Left: saving this look, and opening the saved ones (the button grows into their list).
            VStack(spacing: 8) {
                Button {
                    let version = versions.save(widget)
                    withAnimation(.spring(duration: 0.3)) { justSaved = version.id }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation(.spring(duration: 0.3)) { if justSaved == version.id { justSaved = nil } }
                    }
                } label: {
                    Label(justSaved == nil ? "Save Widget" : "Saved", systemImage: justSaved == nil ? "square.and.arrow.down" : "checkmark")
                        .frame(maxWidth: .infinity)
                        .contentTransition(.symbolEffect(.replace))
                }
                .help("Keep this widget's look (background, parts, positions, text) as a version to open again")
                WidgetVersionsMenu(widget: widget, versions: versions, editing: editing)
            }
            .labelStyle(TitledLabelStyle(titled: titled))
            .buttonBorderShape(.capsule)
            .fixedSize()
            // Its list over the editor below.
            .zIndex(1)

            Spacer(minLength: 10)

            // Middle: the two resets, one over the other, as wide as each other.
            VStack(spacing: 8) {
                Button {
                    guard let selected else { return }
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
                        update {
                            $0.offsets[selected] = nil
                            $0.layers[selected] = nil
                            $0.scales[selected] = nil
                            $0.textStyles[selected] = nil
                            $0.buttonLooks[selected] = nil
                            $0.progressLooks[selected] = nil
                            $0.imageLooks[selected] = nil
                            // A line's times go back with it.
                            if $0.kind.spec.progressBars.contains(selected) {
                                for part in ProgressLook.Part.allCases {
                                    if let inner = part.textID(in: selected) { $0.textStyles[inner] = nil }
                                }
                            }
                        }
                    }
                } label: {
                    Text("Reset Element").frame(maxWidth: .infinity)
                }
                .disabled(selected.map { widget.offsets[$0] == nil && widget.layers[$0] == nil && widget.scales[$0] == nil
                    && widget.textStyles[$0] == nil && widget.buttonLooks[$0] == nil && widget.progressLooks[$0] == nil
                    && widget.imageLooks[$0] == nil } ?? true)
                .help("Put the picked part back where the layout puts it, at its own size")
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.18)) { update { $0 = Self.fresh(widget) } }
                } label: {
                    Text("Reset Widget").frame(maxWidth: .infinity)
                }
                .disabled(widget == Self.fresh(widget))
                .help("Everything about this widget as it was when added: background, parts, positions")
            }
            .buttonBorderShape(.capsule)
            .fixedSize()

            Spacer(minLength: 10)

            // Right: undo and redo, and Done in the corner, as wide as the bar under them.
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Button { restore(editing.undo(from: widget)) } label: { historyIcon("arrow.uturn.backward") }
                        .disabled(editing.undoStack.isEmpty)
                        .keyboardShortcut("z", modifiers: .command)
                        .help("Undo")
                        .accessibilityLabel("Undo")
                    Button { restore(editing.redo(from: widget)) } label: { historyIcon("arrow.uturn.forward") }
                        .disabled(editing.redoStack.isEmpty)
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .help("Redo")
                        .accessibilityLabel("Redo")
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { editing.showsOriginal.toggle() }
                    } label: {
                        // As large as undo's and redo's arrows: a circle as tall as their capsules.
                        Image(systemName: "square.split.2x1")
                            .imageScale(.large)
                            .fontWeight(.medium)
                            .frame(width: Self.historyHeight, height: Self.historyHeight)
                            .accessibilityLabel(editing.showsOriginal ? "Show After" : "Show Before")
                    }
                    // Tinted while the widget before is shown.
                    .tint(editing.showsOriginal ? Color.accentColor : nil)
                    .foregroundStyle(editing.showsOriginal ? Color.accentColor : Color.primary)
                    .buttonBorderShape(.circle)
                    .disabled(editing.original == nil || editing.original == widget)
                    .help(editing.showsOriginal ? "Back to the widget as it is now"
                          : "The widget as it was before this editing, to compare")
                    .padding(.trailing, 2)
                    Button("Done", action: close)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .keyboardShortcut(.cancelAction)
                        .fixedSize()
                }
                .buttonBorderShape(.capsule)
                .frame(width: Self.barWidth)
                // Nothing overlapped: a bar with nothing picked. Once something is, the picked half
                // fades in over it (and out again, keeping its last choice while it goes).
                let current = layering(of: selected, overlapping)
                ZStack {
                    overlapBar(Binding(get: { nil }, set: { _ in }))
                        .disabled(true)
                        .opacity(current == nil ? 1 : 0)
                    overlapBar(Binding(get: { current ?? lastLayering }, set: { layering in
                        guard let selected, let layering, !overlapping.isEmpty else { return }
                        update { widget in
                            let others = overlapping.map(widget.layer(of:))
                            widget.layers[selected] = layering == .above ? (others.max() ?? 0) + 1 : (others.min() ?? 0) - 1
                            widget.sanitize()
                        }
                    }))
                    .opacity(current == nil ? 0 : 1)
                    .allowsHitTesting(current != nil)
                }
                .animation(.easeInOut(duration: 0.3), value: current == nil)
                // Laid out at its width before the system's bar takes it (a moment after it appears).
                .frame(width: Self.barWidth)
                .onChange(of: current) { _, current in
                    if let current { lastLayering = current }
                }
                .help("Where the picked part overlaps others: drawn under them, or over them")
            }
        }
        .controlSize(size)
    }

    /// The Below / Above bar's width; undo, redo and Done keep to its edges.
    static let barWidth: CGFloat = 200
    /// Undo's and redo's capsules, a little wider than they are tall (room for Before and after).
    static let historyWidth: CGFloat = 14
    /// Their arrows' height: the circle of Before and after is drawn round as tall a symbol.
    static let historyHeight: CGFloat = 20

    /// Undo's or redo's arrow, drawn larger in a wide capsule.
    private func historyIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .imageScale(.large)
            .fontWeight(.medium)
            .frame(width: Self.historyWidth, height: Self.historyHeight)
    }

    /// Below or Above, the system's bar.
    private func overlapBar(_ selection: Binding<Layering?>) -> some View {
        Picker("Overlap", selection: selection) {
            Text("Below").tag(Layering?.some(.below))
            Text("Above").tag(Layering?.some(.above))
        }
        .choiceBar(width: Self.barWidth)
        .labelsHidden()
        .fixedSize()
    }

    /// Over every part it overlaps: above; otherwise below; nil while it overlaps none.
    private func layering(of selected: ElementID?, _ overlapping: [ElementID]) -> Layering? {
        guard let selected, !overlapping.isEmpty else { return nil }
        return overlapping.allSatisfy { widget.isDrawn(selected, over: $0) } ? .above : .below
    }

    private func restore(_ widget: IslandWidget?) {
        guard let widget else { return }
        withAnimation(.spring(duration: 0.4, bounce: 0.18)) { update { $0 = widget } }
    }

    private func update(_ change: (inout IslandWidget) -> Void) {
        model.editedWidgets.update(widget.id, change)
    }

    /// The widget as a new one of its kind, where it is.
    private static func fresh(_ widget: IslandWidget) -> IslandWidget {
        var fresh = IslandWidget(kind: widget.kind, frame: widget.frame, options: widget.kind.defaultOptions, id: widget.id)
        fresh.sanitize()
        return fresh
    }
}

/// Title and icon, or the icon alone (`CustomizeTopBar` where it is narrow).
private struct TitledLabelStyle: LabelStyle {
    let titled: Bool

    func makeBody(configuration: Configuration) -> some View {
        if titled {
            Label(configuration).labelStyle(.titleAndIcon)
        } else {
            Label(configuration).labelStyle(.iconOnly)
        }
    }
}

/// Under or over (`CustomizeTopBar`).
enum Layering: Hashable {
    case below, above
}
