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
    @State private var isEditing = false
    @State private var isRemoving = false

    /// The pages it offers: the picker's, in its order; home always (first, where the picker has
    /// it hidden).
    static func pages(_ model: AppModel) -> [ExpandedPage] {
        let offered = model.pickerPages.filter { $0.isBoard || $0 == .shelf }
        return offered.contains(.home) ? offered : [.home] + offered
    }

    var body: some View {
        let pages = Self.pages(model)
        let page = pages.contains(model.studio.page) ? model.studio.page : .home
        HStack(spacing: 6) {
            if pages.count > 1 {
                Picker("Page", selection: Binding(get: { page }, set: select)) {
                    ForEach(pages) { page in
                        // In the colour set for it in Top Bar mode, as the island's picker has it.
                        PageSymbolLabel(page: page, tint: model.preferences.header.pageTints[page])
                            .labelStyle(.iconOnly)
                            .help("Edit the \(page.title) page")
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
            if page.isCustom {
                Button("Edit Page", systemImage: "pencil") { isEditing = true }
                    .help("Rename the page, pick its symbol or delete it")
                    .popover(isPresented: $isEditing, arrowEdge: .bottom) {
                        CustomPageEditor(page: page) {
                            isEditing = false
                            withAnimation(Motion.content) { model.removePage(page) }
                            changed()
                        }
                    }
            }
            // One of the island's own (the battery's, the shelf's…): it has no name or symbol to set,
            // but it can be taken out of the picker here too — unless it is the last one in it.
            if !page.isCustom, page != .shelf, pages.count > 1 {
                Button("Remove Page", systemImage: "trash") { isRemoving = true }
                    .help("Take the \(page.title) page out of the island's picker")
                    .popover(isPresented: $isRemoving, arrowEdge: .bottom) {
                        OwnPageRemoval(page: page) {
                            isRemoving = false
                            var layout = model.preferences.header
                            if layout.setPage(page, hidden: true, among: model.availablePages) {
                                changed()
                                withAnimation(Motion.content) { model.preferences.header = layout }
                            } else {
                                NSSound.beep()
                            }
                        }
                    }
            }
            // A new page — and, while any of the island's own is out of the picker, bringing it back.
            let hidden = model.availablePages.filter { model.preferences.header.hiddenPages.contains($0) }
            let isFull = model.preferences.header.customPages.count >= CustomPage.limit
            if hidden.isEmpty {
                Button("New Page", systemImage: "plus", action: addPage)
                    .disabled(isFull)
                    .help(isFull ? "At most \(CustomPage.limit) pages of your own: the picker stays beside the notch"
                          : "A new page of widgets in the island's picker")
            } else {
                Menu {
                    Button("New Page", systemImage: "plus", action: addPage).disabled(isFull)
                    Divider()
                    ForEach(hidden) { page in
                        Button("Show \(page.title)", systemImage: page.systemImage) {
                            var layout = model.preferences.header
                            layout.setPage(page, hidden: false, among: model.availablePages)
                            withAnimation(Motion.content) { model.preferences.header = layout }
                        }
                    }
                } label: {
                    Label("Pages", systemImage: "plus")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("A new page, or one taken out of the picker back in it")
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .labelStyle(.iconOnly)
        // The buttons beside the pages come and go with the page; the page itself is shown at once
        // (`select`).
        .animation(Motion.content, value: page)
        // A page no longer offered (hidden in the picker, the battery gone): back to home.
        .onChange(of: pages) { _, pages in
            if !pages.contains(model.studio.page) { select(.home) }
        }
    }

    private func addPage() {
        withAnimation(Motion.content) {
            if let added = model.addPage() { select(added) }
        }
    }

    private func select(_ page: ExpandedPage) {
        guard page != model.studio.page else { return }
        changed()
        // At once, with no animation over it: another page is another board — every widget on the
        // stage and every card's Add or Edit under it — and a spring over all of that was drawn in
        // a few uneven frames. The stage fades its own board over (`StageIsland`).
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { model.studio.page = page }
    }
}

/// What the page bar's segments are drawn from, beside the pages themselves.
private struct PagesLook: Hashable {
    let custom: [CustomPage]
    let tints: [ExpandedPage: IslandTheme.RGB]
}

/// A page of the user's: its name and its symbol in the picker, and taking it away.
struct CustomPageEditor: View {
    let page: ExpandedPage
    let remove: () -> Void

    @Environment(AppModel.self) private var model
    @State private var title = ""
    @State private var confirmsRemoval = false
    @FocusState private var isNameFocused: Bool

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8)
    private static let inset: CGFloat = 8

    var body: some View {
        let custom = model.preferences.header.customPage(page)
        VStack(alignment: .leading, spacing: 10) {
            // A capsule, as the buttons round it are.
            TextField("Name", text: $title)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(.white.opacity(0.08), in: .capsule)
                .overlay { Capsule().strokeBorder(.white.opacity(isNameFocused ? 0.3 : 0.1), lineWidth: 1) }
                .focused($isNameFocused)
                .onSubmit { model.preferences.header.editCustomPage(page, title: title) }
            Text("Symbol")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SettingsPalette.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(CustomPage.symbols, id: \.self) { symbol in
                    let isPicked = custom?.symbol == symbol
                    Button { model.preferences.header.editCustomPage(page, symbol: symbol) } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 30, height: 30)
                            .background(isPicked ? Color.islandAccent.opacity(0.35) : .white.opacity(0.06), in: .circle)
                            .overlay { Circle().strokeBorder(isPicked ? Color.islandAccent : .clear, lineWidth: 1.5) }
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                    .accessibilityAddTraits(isPicked ? .isSelected : [])
                }
            }
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
        // Half as far from the popover's edges as before (16): the capsules' ends sit round its
        // corners, and the popover is that much smaller.
        .padding(Self.inset)
        .frame(width: 8 * 30 + 7 * 6 + 2 * Self.inset)
        .onAppear { title = custom?.title ?? "" }
        // A name typed and left is kept too.
        .onDisappear { model.preferences.header.editCustomPage(page, title: title) }
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
