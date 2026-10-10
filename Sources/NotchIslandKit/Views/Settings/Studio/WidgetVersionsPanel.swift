import SwiftUI

/// The top bar's Open Widgets: a button that grows into the list of the saved versions of the
/// widget's kind, down and across over the editor, and back into the button when closed. The list is
/// laid out at its own size from the start; the box around it (on Settings' ground, black easing
/// into grey) grows from the button's to the list's, from the button's top-leading corner, and shows
/// more of it as it does — and unfolds the same way when the list grows (a preview coming in).
struct WidgetVersionsMenu: View {
    let widget: IslandWidget
    let versions: WidgetVersionStore
    let editing: ElementEditing

    @State private var buttonSize: CGSize = .zero
    @State private var listHeight: CGFloat = 0
    /// The list in the box: in a moment after the box starts growing, out before it shrinks.
    @State private var contentIn = false
    /// The list is built a moment after Customize has come in, on the efficiency cores, not with
    /// it: hidden until asked for, it was a quarter of every opening's energy (measured).
    @State private var hasList = false
    @State private var listBuild: Timer?
    /// After Customize's steps in.
    static let listDelay: TimeInterval = 0.9

    static let width: CGFloat = 360
    static let radius: CGFloat = 16
    /// The box following the list's height: unfolding, settling with a little bounce.
    static let unfold = Animation.spring(duration: 0.55, bounce: 0.22)

    var body: some View {
        let isOpen = editing.showsVersions
        Button(action: toggle) {
            Label("Open Widgets", systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity)
        }
        .help("The saved versions of this kind of widget: open one, rename or delete it")
        .opacity(isOpen ? 0 : 1)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { buttonSize = $0 }
        .overlay(alignment: .topLeading) { if hasList {
            WidgetVersionsPanel(widget: widget, versions: versions, editing: editing, close: toggle)
                .frame(width: Self.width)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // Open, the box unfolds to the list's new height rather than jumping to it.
                    if editing.showsVersions, listHeight > 0 {
                        withAnimation(Self.unfold) { listHeight = height }
                    } else {
                        listHeight = height
                    }
                }
                // Comes up out of a blur and a little from above as the box opens around it.
                .opacity(contentIn ? 1 : 0)
                .blur(radius: contentIn ? 0 : 6)
                .offset(y: contentIn ? 0 : -10)
                .frame(width: isOpen ? Self.width : buttonSize.width, height: isOpen ? listHeight : buttonSize.height,
                       alignment: .topLeading)
                .background { SettingsBackdrop() }
                .clipShape(RoundedRectangle(cornerRadius: isOpen ? Self.radius : buttonSize.height / 2, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: isOpen ? Self.radius : buttonSize.height / 2, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ElementEditing.space)) } action: {
                    editing.versionsFrame = $0
                }
                .shadow(color: .black.opacity(isOpen ? 0.5 : 0), radius: 18, y: 8)
                .opacity(isOpen ? 1 : 0)
                .allowsHitTesting(isOpen)
                .controlSize(.regular)
        } }
        // Closed from elsewhere (another widget picked): the list goes with it.
        .onChange(of: isOpen) { _, open in
            if !open, contentIn { withAnimation(.easeIn(duration: 0.12)) { contentIn = false } }
        }
        .onAppear(perform: buildListSoon)
        .onDisappear {
            listBuild?.invalidate()
            listBuild = nil
        }
    }

    /// A run-loop timer, not a task: its turn runs at background quality of service
    /// (`MainThrift.lowPower`), which a main-actor task's priority would override.
    private func buildListSoon() {
        guard !hasList, listBuild == nil else { return }
        let timer = Timer(timeInterval: Self.listDelay, repeats: false) { _ in
            MainActor.assumeIsolated {
                listBuild = nil
                guard !hasList else { return }
                MainThrift.lowPower(for: 0.4)
                hasList = true
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        listBuild = timer
    }

    private func toggle() {
        // Asked for before it was built: built now, and opened a turn later, once laid out (the box
        // unfolds to the list's height as it always did).
        guard hasList else {
            listBuild?.invalidate()
            listBuild = nil
            hasList = true
            DispatchQueue.main.async { toggle() }
            return
        }
        if editing.showsVersions {
            withAnimation(.easeIn(duration: 0.12)) { contentIn = false }
            withAnimation(.spring(duration: 0.38, bounce: 0.08).delay(0.06)) { editing.showsVersions = false }
        } else {
            withAnimation(Self.unfold) { editing.showsVersions = true }
            withAnimation(.spring(duration: 0.45, bounce: 0.1).delay(0.1)) { contentIn = true }
        }
    }
}

/// The saved versions of the widget's kind: each with its name (renamed in place), when it was
/// saved and at what size, Open, and delete; the one under the pointer drawn below the list.
/// Opening one is a change like any other: Undo takes it back.
struct WidgetVersionsPanel: View {
    let widget: IslandWidget
    let versions: WidgetVersionStore
    let editing: ElementEditing
    let close: () -> Void

    @Environment(AppModel.self) private var model
    @State private var hovered: UUID?
    /// The pointer's coming and going, a moment later: passing over the list shows nothing.
    @State private var hoverChange: Task<Void, Never>?
    @State private var confirmsDeleteAll = false

    static let maxListHeight: CGFloat = 240
    /// The preview's tallest, its frame included.
    static let previewMaxHeight: CGFloat = 170
    /// Around the widget in its preview, its corners concentric with the widget's.
    static let previewInset: CGFloat = 6

    var body: some View {
        let saved = versions.versions(of: widget.kind)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved Widgets").font(.headline)
                    Text("Versions of \(widget.kind.title)")
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                }
                Spacer(minLength: 8)
                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .help("Close")
            }
            if saved.isEmpty {
                Text("None yet. Save Widget keeps this widget's look, to open again here.")
                    .font(.callout)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(saved) { version in
                            VersionRow(version: version, isCurrent: version.applied(to: widget) == widget,
                                       open: { open(version) }, rename: { versions.rename(version.id, to: $0) },
                                       delete: { delete(version.id) })
                                .onHover { inside in hover(version.id, inside: inside) }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: Self.maxListHeight)
                .fixedSize(horizontal: false, vertical: true)
                deleteAll(count: saved.count)
                // Below the list, so the rows stay under the pointer as it comes and goes.
                if let version = saved.first(where: { $0.id == hovered }) {
                    preview(version)
                        .id(version.id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.8, anchor: .top)).combined(with: .offset(y: -14)),
                            removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))))
                }
            }
        }
        .padding(14)
        .onChange(of: editing.showsVersions) { _, shown in
            if !shown { confirmsDeleteAll = false }
        }
    }

    /// Delete All, then asked once more in its place.
    @ViewBuilder private func deleteAll(count: Int) -> some View {
        HStack(spacing: 8) {
            if confirmsDeleteAll {
                Text(count == 1 ? "Delete the saved version?" : "Delete all \(count) saved versions?")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                Spacer(minLength: 4)
                Button("Cancel") { withAnimation(.spring(duration: 0.3)) { confirmsDeleteAll = false } }
                    .controlSize(.small)
                Button("Delete", role: .destructive) {
                    withAnimation(.spring(duration: 0.3)) {
                        versions.deleteAll(of: widget.kind)
                        confirmsDeleteAll = false
                        hovered = nil
                    }
                }
                .controlSize(.small)
                .tint(.red)
            } else {
                Spacer(minLength: 0)
                Button("Delete All") { withAnimation(.spring(duration: 0.3)) { confirmsDeleteAll = true } }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(SettingsPalette.secondary)
                    .help("Delete every saved version of \(widget.kind.title)")
            }
        }
        .buttonBorderShape(.capsule)
        .frame(minHeight: 22)
    }

    /// The version as it looks, as large as the panel allows, a little way in from its frame's
    /// corners (concentric with its own).
    private func preview(_ version: WidgetVersion) -> some View {
        let geometry = WidgetBoardGeometry(size: WidgetsSettingsPage.boardSize(model.layout), grid: model.editedWidgets.board.grid)
        let size = geometry.laidSize(for: version.widget.frame)
        let inset = Self.previewInset
        let room = CGSize(width: WidgetVersionsMenu.width - 28 - 2 * inset, height: Self.previewMaxHeight - 2 * inset)
        let scale = min(room.width / max(size.width, 1), room.height / max(size.height, 1))
        let corners = IslandWidgetView.outerCorners(version.widget, size: size, board: nil)
        let radius = max(corners.topLeading, corners.topTrailing, corners.bottomLeading, corners.bottomTrailing) * scale + inset
        // As sharp as it is shown, its glass buttons' glass drawn as it is.
        return SharpZoom(widget: version.widget) { _ in
            IslandWidgetView(widget: version.widget, size: size)
                .environment(\.isWidgetPreview, true)
                .environment(\.widgetRenderMode, .canvas)
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
        }
            .allowsHitTesting(false)
            .padding(inset)
            .background(.black, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    /// Shown once the pointer has rested on a row a moment, at once when it moves from one row to
    /// the next, and gone a moment after it leaves them.
    private func hover(_ id: UUID, inside: Bool) {
        hoverChange?.cancel()
        if inside, hovered != nil {
            withAnimation(.spring(duration: 0.4, bounce: 0.12)) { hovered = id }
            return
        }
        guard inside || hovered == id else { return }
        hoverChange = Task {
            try? await Task.sleep(for: .milliseconds(inside ? 140 : 180))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.5, bounce: inside ? 0.2 : 0.05)) { hovered = inside ? id : nil }
        }
    }

    private func open(_ version: WidgetVersion) {
        withAnimation(.spring(duration: 0.4, bounce: 0.18)) {
            model.editedWidgets.update(widget.id) { $0 = version.applied(to: $0) }
        }
        close()
    }

    private func delete(_ id: UUID) {
        withAnimation(.spring(duration: 0.3)) {
            versions.delete(id)
            if hovered == id { hovered = nil }
        }
    }
}

/// One saved version: its name to rename in place, when and at what size it was saved, and its
/// buttons.
private struct VersionRow: View {
    let version: WidgetVersion
    /// The widget looks like it now: nothing to open.
    let isCurrent: Bool
    let open: () -> Void
    let rename: (String) -> Void
    let delete: () -> Void

    @State private var name = ""
    @State private var isHovered = false
    @FocusState private var isEditingName: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.callout.weight(.medium))
                    .focused($isEditingName)
                    .onSubmit { rename(name) }
                    .onChange(of: isEditingName) { _, editing in
                        if !editing { rename(name) }
                    }
                    .help("Rename")
                Text("\(version.date.formatted(date: .abbreviated, time: .shortened)) · \(version.widget.frame.width) × \(version.widget.frame.height)")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 6)
            if isCurrent {
                Text("Current")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SettingsPalette.secondary)
            } else {
                Button("Open", action: open)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help("This widget with this version's look (Undo takes it back)")
            }
            Button("Delete", systemImage: "trash", action: delete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(SettingsPalette.secondary)
                .help("Delete this version")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.white.opacity(isHovered ? 0.09 : isCurrent ? 0.06 : 0.03), in: .rect(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
        .onAppear { name = version.name }
        .onChange(of: version.name) { _, new in name = new }
    }
}
