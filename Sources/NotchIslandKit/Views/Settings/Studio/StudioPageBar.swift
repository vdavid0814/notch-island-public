import SwiftUI

/// In the stage's bar, in Widgets and Size mode: the page whose board the stage edits — one of
/// those the island's picker offers (home, the timer's, the battery's, the user's), by its symbol
/// as the picker shows it — the picked page of the user's to rename, and a new page.
struct StudioPageBar: View {
    /// Called as the page changes: the picks on the old board end.
    let changed: () -> Void

    @Environment(AppModel.self) private var model
    @State private var isEditing = false

    /// The pages it offers: the boards among the picker's pages, home always.
    static func pages(_ model: AppModel) -> [ExpandedPage] {
        let offered = model.pickerPages.filter(\.isBoard)
        return offered.contains(.home) ? offered : [.home] + offered
    }

    var body: some View {
        let pages = Self.pages(model)
        let page = pages.contains(model.studio.page) ? model.studio.page : .home
        HStack(spacing: 6) {
            if pages.count > 1 {
                Picker("Page", selection: Binding(get: { page }, set: select)) {
                    ForEach(pages) { page in
                        Label(page.title, systemImage: page.systemImage)
                            .labelStyle(.iconOnly)
                            .help("Edit the \(page.title) page")
                            .tag(page)
                    }
                }
                .choiceBar()
                .labelsHidden()
                .fixedSize()
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
            Button("New Page", systemImage: "plus") {
                withAnimation(Motion.content) {
                    if let added = model.addPage() { select(added) }
                }
            }
            .disabled(model.preferences.header.customPages.count >= CustomPage.limit)
            .help(model.preferences.header.customPages.count >= CustomPage.limit
                  ? "At most \(CustomPage.limit) pages of your own: the picker stays beside the notch"
                  : "A new page of widgets in the island's picker")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .labelStyle(.iconOnly)
        // A page no longer offered (hidden in the picker, the battery gone): back to home.
        .onChange(of: pages) { _, pages in
            if !pages.contains(model.studio.page) { select(.home) }
        }
    }

    private func select(_ page: ExpandedPage) {
        guard page != model.studio.page else { return }
        changed()
        withAnimation(Motion.content) { model.studio.page = page }
    }
}

/// A page of the user's: its name and its symbol in the picker, and taking it away.
struct CustomPageEditor: View {
    let page: ExpandedPage
    let remove: () -> Void

    @Environment(AppModel.self) private var model
    @State private var title = ""
    @State private var confirmsRemoval = false

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8)

    var body: some View {
        let custom = model.preferences.header.customPage(page)
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: $title)
                .textFieldStyle(.roundedBorder)
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
                            .background(isPicked ? Color.islandAccent.opacity(0.35) : .white.opacity(0.06),
                                        in: .rect(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(isPicked ? Color.islandAccent : .clear, lineWidth: 1.5)
                            }
                            .contentShape(.rect)
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
                    Spacer(minLength: 0)
                    Button("Delete Page", role: .destructive, action: remove)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            } else {
                Button("Delete Page…", role: .destructive) { withAnimation(Motion.content) { confirmsRemoval = true } }
            }
        }
        .padding(16)
        .frame(width: 8 * 30 + 7 * 6 + 32)
        .onAppear { title = custom?.title ?? "" }
        // A name typed and left is kept too.
        .onDisappear { model.preferences.header.editCustomPage(page, title: title) }
    }
}
