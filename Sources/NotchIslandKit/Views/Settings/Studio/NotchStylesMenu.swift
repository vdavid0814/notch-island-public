import SwiftUI

/// Beside Settings ▸ Widgets' title: saving the whole island as a notch style (`NotchStyle`), and
/// opening the saved ones — as Customize's Save Widget and Open Widgets do for one widget.
struct NotchStyleButtons: View {
    @Environment(AppModel.self) private var model
    /// The style just saved: its button says so for a moment.
    @State private var justSaved: UUID?

    var body: some View {
        VStack(spacing: Self.spacing) {
            Button {
                let style = model.notchStyles.save(model.currentNotchStyle())
                withAnimation(.spring(duration: 0.3)) { justSaved = style.id }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.spring(duration: 0.3)) { if justSaved == style.id { justSaved = nil } }
                }
            } label: {
                Label(justSaved == nil ? "Save Notch Style" : "Saved", systemImage: justSaved == nil ? "square.and.arrow.down" : "checkmark")
                    .frame(maxWidth: .infinity)
                    .contentTransition(.symbolEffect(.replace))
            }
            .help("Keep the whole island as it looks (every page's widgets, the top bar, the size, the surface and colour) as a style to open again")
            NotchStylesMenu()
        }
        .buttonStyle(HeaderOutlineButtonStyle())
        .fixedSize()
    }

    /// Between the two, which are together as tall as the title and its line.
    static let spacing: CGFloat = 4
    static let height: CGFloat = 18
}

/// The page header's buttons: small, black, their edge a faint grey line.
struct HeaderOutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(HeaderLabelStyle())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .frame(height: NotchStyleButtons.height)
            .background(Capsule().fill(Color.black))
            .overlay(Capsule().strokeBorder(Color.white.opacity(configuration.isPressed ? 0.32 : 0.16), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct HeaderLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10, weight: .medium))
            configuration.title
        }
    }
}

/// Open Notch Styles: a button that grows into the list of the saved styles, down and to the left
/// over the page, and back into the button when closed — as Open Widgets does in Customize
/// (`WidgetVersionsMenu`), from the button's top-trailing corner, the window's edge being on its
/// right.
struct NotchStylesMenu: View {
    @Environment(AppModel.self) private var model

    static let width: CGFloat = 380

    var body: some View {
        @Bindable var studio = model.studio
        HeaderMenuButton(title: "Open Notch Styles", symbol: "rectangle.stack",
                         help: "The saved notch styles: open one, rename or delete it",
                         isOpen: $studio.showsNotchStyles, buttonFrame: $studio.notchStylesButton)
    }

    /// The space the open list's frame is measured in: the Settings page around it, where a click
    /// beside the list closes it (`NotchStylesDismissal`).
    static let space = "notchStyles"
}

/// The button of a page header's menu. The list it grows into lies over the page, not in the header
/// (`HeaderMenuBox`): the header is the page's bar, and what stands out of a bar takes no clicks.
struct HeaderMenuButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let help: LocalizedStringKey
    @Binding var isOpen: Bool
    @Binding var buttonFrame: CGRect

    var body: some View {
        Button {
            if isOpen {
                withAnimation(.spring(duration: 0.38, bounce: 0.08).delay(0.06)) { isOpen = false }
            } else {
                withAnimation(WidgetVersionsMenu.unfold) { isOpen = true }
            }
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .help(help)
        .opacity(isOpen ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchStylesMenu.space)) } action: { buttonFrame = $0 }
    }
}

/// What a header's menu grows into, down and to the left over the page, and back into the button
/// when closed — as Open Widgets does in Customize (`WidgetVersionsMenu`), from the button's
/// top-trailing corner, the window's edge being on its right.
struct HeaderMenuBox<Panel: View>: View {
    let width: CGFloat
    @Binding var isOpen: Bool
    let buttonFrame: CGRect
    @Binding var frame: CGRect
    @ViewBuilder let panel: (_ close: @escaping () -> Void) -> Panel

    @State private var listHeight: CGFloat = 0
    /// The list in the box: in a moment after the box starts growing, out before it shrinks.
    @State private var contentIn = false

    var body: some View {
        let boxWidth = isOpen ? width : buttonFrame.width
        let radius = isOpen ? WidgetVersionsMenu.radius : buttonFrame.height / 2
        panel {
            withAnimation(.spring(duration: 0.38, bounce: 0.08).delay(0.06)) { isOpen = false }
        }
        // Settings' own buttons on the list, not the header's.
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            // Open, the box unfolds to the list's new height rather than jumping to it.
            if isOpen, listHeight > 0 {
                withAnimation(WidgetVersionsMenu.unfold) { listHeight = height }
            } else {
                listHeight = height
            }
        }
        // Comes up out of a blur and a little from above as the box opens around it.
        .opacity(contentIn ? 1 : 0)
        .blur(radius: contentIn ? 0 : 6)
        .offset(y: contentIn ? 0 : -10)
        .frame(width: boxWidth, height: isOpen ? listHeight : buttonFrame.height, alignment: .topTrailing)
        .background { SettingsBackdrop() }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(NotchStylesMenu.space)) } action: { frame = $0 }
        .shadow(color: .black.opacity(isOpen ? 0.5 : 0), radius: 18, y: 8)
        .opacity(isOpen ? 1 : 0)
        .allowsHitTesting(isOpen)
        .controlSize(.regular)
        .offset(x: buttonFrame.maxX - boxWidth, y: buttonFrame.minY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: isOpen) { _, open in
            if open {
                withAnimation(.spring(duration: 0.45, bounce: 0.1).delay(0.1)) { contentIn = true }
            } else {
                withAnimation(.easeIn(duration: 0.12)) { contentIn = false }
            }
        }
    }
}

extension View {
    /// The saved notch styles open: a click anywhere but on them closes them (and does nothing else).
    func notchStylesDismissal(_ model: AppModel, if applies: Bool) -> some View {
        headerMenuDismissal(isOpen: applies && model.studio.showsNotchStyles, frame: model.studio.notchStylesFrame) {
            model.studio.showsNotchStyles = false
        }
    }

    /// A header menu open (`HeaderUnfoldMenu`): a click anywhere but on it closes it (and does nothing else).
    func headerMenuDismissal(isOpen: Bool, frame: CGRect, close: @escaping () -> Void) -> some View {
        overlay {
            if isOpen {
                Color.clear
                    .contentShape(Rectangle().subtracting(Rectangle().path(in: frame)))
                    .onTapGesture { withAnimation(.spring(duration: 0.38, bounce: 0.08), close) }
            }
        }
        .coordinateSpace(.named(NotchStylesMenu.space))
    }
}

/// The saved notch styles: each with its name (renamed in place), when it was saved, its cells and
/// widgets, Open, and delete; the one under the pointer drawn below the list as its home page
/// looks. Opening one is a change like any other: Undo takes the boards back.
struct NotchStylesPanel: View {
    let close: () -> Void

    @Environment(AppModel.self) private var model
    @State private var hovered: UUID?
    /// The pointer's coming and going, a moment later: passing over the list shows nothing.
    @State private var hoverChange: Task<Void, Never>?
    @State private var confirmsDeleteAll = false

    var body: some View {
        let saved = model.notchStyles.newestFirst
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved Notch Styles").font(.headline)
                    Text("The whole island: its widgets, top bar, size and look")
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
                Text("None yet. Save Notch Style keeps the whole island as it is, to open again here.")
                    .font(.callout)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(saved) { style in
                            NotchStyleRow(style: style, isCurrent: model.isCurrent(style),
                                          open: { open(style) }, rename: { model.notchStyles.rename(style.id, to: $0) },
                                          delete: { delete(style.id) })
                                .onHover { inside in hover(style.id, inside: inside) }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: WidgetVersionsPanel.maxListHeight)
                .fixedSize(horizontal: false, vertical: true)
                deleteAll(count: saved.count)
                // Below the list, so the rows stay under the pointer as it comes and goes.
                if let style = saved.first(where: { $0.id == hovered }) {
                    preview(style)
                        .id(style.id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.8, anchor: .top)).combined(with: .offset(y: -14)),
                            removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))))
                }
            }
        }
        .padding(14)
        .onChange(of: model.studio.showsNotchStyles) { _, shown in
            if !shown { confirmsDeleteAll = false }
        }
    }

    /// Delete All, then asked once more in its place.
    @ViewBuilder private func deleteAll(count: Int) -> some View {
        HStack(spacing: 8) {
            if confirmsDeleteAll {
                Text(count == 1 ? "Delete the saved style?" : "Delete all \(count) saved styles?")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                Spacer(minLength: 4)
                Button("Cancel") { withAnimation(.spring(duration: 0.3)) { confirmsDeleteAll = false } }
                    .controlSize(.small)
                Button("Delete", role: .destructive) {
                    withAnimation(.spring(duration: 0.3)) {
                        model.notchStyles.deleteAll()
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
                    .help("Delete every saved notch style")
            }
        }
        .buttonBorderShape(.capsule)
        .frame(minHeight: 22)
    }

    /// The style's home page as the open island shows it, as large as the panel allows.
    private func preview(_ style: NotchStyle) -> some View {
        let layout = model.studioLayout.replacing(scale: style.scale).replacing(panel: style.panel.layout)
        let presentation = IslandPresentation.expanded(.home)
        let island = layout.size(for: presentation)
        let boardSize = BoardSizing.board(layout)
        let board = style.boards[ExpandedPage.home.rawValue] ?? WidgetBoard(widgets: [], grid: style.panel.grid)
        let geometry = WidgetBoardGeometry(size: boardSize, grid: board.grid)
        let room = CGSize(width: NotchStylesMenu.width - 28, height: WidgetVersionsPanel.previewMaxHeight)
        let scale = min(room.width / max(island.width, 1), room.height / max(island.height, 1))
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: layout.bottomRadius(for: presentation),
                                           bottomTrailingRadius: layout.bottomRadius(for: presentation), style: .continuous)
        return ZStack(alignment: .topLeading) {
            ForEach(board.widgets) { widget in
                let frame = geometry.frame(for: widget.frame)
                IslandWidgetView(widget: widget, size: frame.size)
                    .environment(\.isWidgetPreview, true)
                    .environment(\.widgetRenderMode, .canvas)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: boardSize.width, height: boardSize.height, alignment: .topLeading)
        // Where the island puts its board: inside the sides' insets, under the header.
        .offset(x: IslandLayout.boardSideInset + layout.boardInset,
                y: layout.notch.height + IslandLayout.boardTopInset + layout.boardInset)
        .frame(width: island.width, height: island.height, alignment: .topLeading)
        .background(.black, in: shape)
        .overlay { shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
        .environment(\.colorScheme, .dark)
        .drawingGroup()
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: island.width * scale, height: island.height * scale, alignment: .topLeading)
        .allowsHitTesting(false)
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

    private func open(_ style: NotchStyle) {
        withAnimation(.spring(duration: 0.4, bounce: 0.18)) { model.open(style) }
        close()
    }

    private func delete(_ id: UUID) {
        withAnimation(.spring(duration: 0.3)) {
            model.notchStyles.delete(id)
            if hovered == id { hovered = nil }
        }
    }
}

/// One saved style: its name to rename in place, when it was saved, its cells and widgets, and its
/// buttons.
private struct NotchStyleRow: View {
    let style: NotchStyle
    /// The island looks like it now: nothing to open.
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
                Text("\(style.date.formatted(date: .abbreviated, time: .shortened)) · \(style.panel.columns) × \(style.panel.rows) · \(style.widgetCount) \(style.widgetCount == 1 ? "widget" : "widgets")")
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
                    .help("The island as this style has it (Undo takes the widgets back)")
            }
            Button("Delete", systemImage: "trash", action: delete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(SettingsPalette.secondary)
                .help("Delete this style")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.white.opacity(isHovered ? 0.09 : isCurrent ? 0.06 : 0.03), in: .rect(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
        .onAppear { name = style.name }
        .onChange(of: style.name) { _, new in name = new }
    }
}
