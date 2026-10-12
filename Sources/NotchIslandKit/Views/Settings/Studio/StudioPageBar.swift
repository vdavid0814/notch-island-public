import AppKit
import SwiftUI

/// In the stage's bar, in Widgets and Size mode: the page the stage shows — every page the island's
/// picker offers, in the picker's own order (the top bar's), the shelf among them, by its symbol as
/// the picker shows it — the picked page of the user's to rename, one of the island's own to take
/// out of the picker (the shelf is only looked at: it has no widgets to arrange, and is switched
/// on and off in General), and a new page.
struct StudioPageBar: View {
    /// Called as the page changes: the picks on the old board end.
    let changed: () -> Void

    @Environment(AppModel.self) private var model
    /// The shown page's button's popover: its editor, or taking it out of the picker.
    @State private var isActing = false
    /// The "+"'s popover: a new page's name and symbol.
    @State private var isAdding = false
    /// The buttons' glass: one that comes flows out of the one beside it (`glassEffectID`).
    @Namespace private var glass

    /// The pages it offers: the picker's, in its order; home always (first, where the picker has
    /// it hidden).
    static func pages(_ model: AppModel) -> [ExpandedPage] {
        let offered = model.pickerPages.filter { $0.isBoard || $0 == .shelf }
        return offered.contains(.home) ? offered : [.home] + offered
    }

    var body: some View {
        let pages = Self.pages(model)
        let page = pages.contains(model.studio.page) ? model.studio.page : .home
        // The picked one, shown at once while the board is still on its way (`switchPage`).
        let picked = model.studio.pendingPage.flatMap { pages.contains($0) ? $0 : nil } ?? page
        // The buttons beside the pages are the shown page's once its switch has landed
        // (`WidgetStudio.barPage`): changed in the long turn of the switch, their animation lost its
        // first frames and they appeared at once.
        let buttons = model.studio.barPage.flatMap { pages.contains($0) ? $0 : nil } ?? page
        // In one glass container: a button that comes flows out of the one beside it (`New Page`)
        // and back into it as it goes, the two glasses joined while they are close.
        GlassEffectContainer(spacing: Self.blend) {
            HStack(spacing: Self.gap) {
                    if pages.count > 1 {
                    Picker("Page", selection: Binding(get: { picked }, set: select)) {
                        ForEach(pages) { page in
                            // In the colour set for it in Top Bar mode, as the island's picker has it.
                            PageSymbolLabel(page: page, tint: model.preferences.header.pageTints[page])
                                .labelStyle(.iconOnly)
                                .tag(page)
                        }
                    }
                    .choiceBar()
                    .labelsHidden()
                    .fixedSize()
                    // A page renamed, given another symbol or another colour is the same page: its
                    // segment is drawn again only when the bar is made anew (its picture stayed the
                    // old one).
                    .id(PagesLook(custom: model.preferences.header.customPages, tints: model.preferences.header.pageTints))
                }
                // The shown page's own button: a page of the user's is edited (renamed, its symbol
                // picked, deleted), one of the island's own taken out of the picker — unless it is
                // the shelf or the last one in it. One glass for both, its symbol swapped: two
                // glasses, one flowing away as the other came (home to a page of the user's), hung
                // the app — SwiftUI's key view loop went round for ever (Oct 12 2026).
                let action: PageAction? = buttons.isCustom ? .edit : buttons != .shelf && pages.count > 1 ? .remove : nil
                if let action {
                    Button { isActing = true } label: {
                        Self.glassLabel(action.symbol)
                            .id(action)
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("action", in: glass)
                    .accessibilityLabel(action == .edit ? "Edit Page" : "Remove Page")
                    .popover(isPresented: $isActing, arrowEdge: .bottom) {
                        if action == .edit {
                            CustomPageEditor(page: buttons) {
                                isActing = false
                                withAnimation(Motion.content) { model.removePage(buttons) }
                                changed()
                            }
                        } else {
                            OwnPageRemoval(page: buttons) {
                                isActing = false
                                var layout = model.preferences.header
                                if layout.setPage(buttons, hidden: true, among: model.availablePages) {
                                    changed()
                                    withAnimation(Motion.content) { model.preferences.header = layout }
                                } else {
                                    NSSound.beep()
                                }
                            }
                        }
                    }
                }
                // A new page, named and given its symbol first — and the island's own pages taken
                // out of the picker (home, the battery's, the shelf), to bring back.
                let isFull = model.preferences.header.customPages.count >= CustomPage.limit
                let hidden = [ExpandedPage.home, .battery, .shelf].filter {
                    model.availablePages.contains($0) && model.preferences.header.hiddenPages.contains($0)
                }
                let canAdd = !isFull || !hidden.isEmpty
                Button { isAdding = true } label: { Self.glassLabel("plus").opacity(canAdd ? 1 : 0.4) }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("add", in: glass)
                    .disabled(!canAdd)
                    .accessibilityLabel("New Page")
                    .popover(isPresented: $isAdding, arrowEdge: .bottom) {
                        NewPageEditor(hidden: hidden, isFull: isFull) { title, symbol in
                            isAdding = false
                            addPage(title: title, symbol: symbol)
                        } show: { page in
                            isAdding = false
                            var layout = model.preferences.header
                            layout.setPage(page, hidden: false, among: model.availablePages)
                            withAnimation(Motion.content) { model.preferences.header = layout }
                            select(page)
                        }
                    }
            }
        }
        .labelStyle(.iconOnly)
        .animation(Self.flow, value: buttons)
        // A page no longer offered (hidden in the picker, the battery gone): back to home.
        .onChange(of: pages) { _, pages in
            if !pages.contains(model.studio.page) { select(.home) }
        }
    }

    /// Between the bar and its buttons; glass nearer than `blend` flows together.
    static let gap: CGFloat = 8
    static let blend: CGFloat = 6
    /// The buttons' circles, as tall as the page bar.
    static let side: CGFloat = 24
    static let flow: Animation = .spring(duration: 0.5, bounce: 0.22)

    static func glassLabel(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .contentShape(.circle)
    }

    private func addPage(title: String, symbol: String) {
        withAnimation(Motion.content) {
            if let added = model.addPage(title: title, symbol: symbol) { select(added) }
        }
    }

    private func select(_ page: ExpandedPage) {
        // With no animation over it: another page is another board — every widget on the stage and
        // every card's Add or Edit under it. The board fades out and in (`switchPage`); the picks
        // on the old one end as it goes (`WidgetsSettingsPage`).
        model.studio.switchPage(to: page)
    }
}

/// What the shown page's button does.
private enum PageAction: Hashable {
    case edit, remove

    var symbol: String { self == .edit ? "pencil" : "trash" }
}

/// What the page bar's segments are drawn from, beside the pages themselves.
private struct PagesLook: Hashable {
    let custom: [CustomPage]
    let tints: [ExpandedPage: IslandTheme.RGB]
}

/// A page of the user's: its name and its symbol in the picker, and taking it away.
/// A page's name and its symbol in the picker: the editor of a page of the user's, and of a new one.
private struct PageLookFields: View {
    @Binding var title: String
    let symbol: String
    let pick: (String) -> Void
    var submit: () -> Void = {}

    @FocusState private var isNameFocused: Bool
    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8)

    var body: some View {
        // A capsule, as the buttons round it are.
        TextField("Name", text: $title)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(.white.opacity(0.08), in: .capsule)
            .overlay { Capsule().strokeBorder(.white.opacity(isNameFocused ? 0.3 : 0.1), lineWidth: 1) }
            .focused($isNameFocused)
            .onSubmit(submit)
        Text("Symbol")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SettingsPalette.secondary)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(CustomPage.symbols, id: \.self) { candidate in
                let isPicked = symbol == candidate
                Button { pick(candidate) } label: {
                    Image(systemName: candidate)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(isPicked ? Color.islandAccent.opacity(0.35) : .white.opacity(0.06), in: .circle)
                        .overlay { Circle().strokeBorder(isPicked ? Color.islandAccent : .clear, lineWidth: 1.5) }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
            }
        }
    }

    /// Half as far from the popover's edges as a form's (16): the capsules' ends sit round its
    /// corners, and the popover is that much smaller.
    static let inset: CGFloat = 8
    static let width: CGFloat = 8 * 30 + 7 * 6 + 2 * inset
}

/// A page of the user's: its name and its symbol in the picker, and taking it away.
struct CustomPageEditor: View {
    let page: ExpandedPage
    let remove: () -> Void

    @Environment(AppModel.self) private var model
    @State private var title = ""
    @State private var confirmsRemoval = false

    var body: some View {
        let custom = model.preferences.header.customPage(page)
        VStack(alignment: .leading, spacing: 10) {
            PageLookFields(title: $title, symbol: custom?.symbol ?? CustomPage.defaultSymbol,
                           pick: { model.preferences.header.editCustomPage(page, symbol: $0) },
                           submit: { model.preferences.header.editCustomPage(page, title: title) })
            Divider().opacity(0.6)
            // Asked here, in the popover: an alert over it closed the popover (and Settings with it).
            if confirmsRemoval {
                Text("Delete “\(custom?.title ?? page.title)” and its widgets?")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { withAnimation(Motion.content) { confirmsRemoval = false } }
                        .buttonStyle(.glass)
                    Spacer(minLength: 0)
                    Button("Delete Page", role: .destructive, action: remove)
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                }
                .buttonBorderShape(.capsule)
            } else {
                // Red glass, a capsule as the popover's own corners are round.
                Button(role: .destructive) { withAnimation(Motion.content) { confirmsRemoval = true } } label: {
                    Label("Delete Page…", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(PageLookFields.inset)
        .frame(width: PageLookFields.width)
        .onAppear { title = custom?.title ?? "" }
        // A name typed and left is kept too.
        .onDisappear { model.preferences.header.editCustomPage(page, title: title) }
    }
}

/// The "+"'s popover: a new page named and given its symbol, as a page of the user's is edited
/// (`CustomPageEditor`), then made — and, over its button, the island's own pages taken out of
/// the picker, each a grey capsule sharing the button's width, to bring back.
private struct NewPageEditor: View {
    let hidden: [ExpandedPage]
    let isFull: Bool
    let create: (String, String) -> Void
    let show: (ExpandedPage) -> Void

    @Environment(AppModel.self) private var model
    @State private var title = ""
    @State private var symbol = CustomPage.defaultSymbol

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isFull {
                Text("At most \(CustomPage.limit) pages of your own: the picker stays beside the notch.")
                    .font(.callout)
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                PageLookFields(title: $title, symbol: symbol, pick: { symbol = $0 }, submit: make)
                Divider().opacity(0.6)
            }
            if !hidden.isEmpty {
                HStack(spacing: 6) {
                    ForEach(hidden) { page in
                        Button { show(page) } label: {
                            Text("Add \(page.title)")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                    }
                }
            }
            if !isFull {
                Button(action: make) {
                    Label("Create Page", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(PageLookFields.inset)
        .frame(width: PageLookFields.width)
        .onAppear { title = model.preferences.header.nextCustomTitle }
    }

    private func make() {
        create(title, symbol)
    }
}

/// One of the island's own pages, taken out of the picker: what that means, and the button.
private struct OwnPageRemoval: View {
    let page: ExpandedPage
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(page.title, systemImage: page.systemImage)
                .font(.headline)
            Text("The page leaves the island's picker; its widgets are kept. The + beside the pages brings it back.")
                .font(.callout)
                .foregroundStyle(SettingsPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(role: .destructive, action: remove) {
                Label("Remove Page", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .buttonBorderShape(.capsule)
        }
        .padding(8)
        .frame(width: 260)
    }
}

