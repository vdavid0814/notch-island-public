import SwiftUI

/// Under the stage in Top Bar mode: what stands left and right of the notch, in order, with each
/// side's room — first, right under the stage, so the bar shows what is set; the items not in the
/// bar, to drag onto it or add with "+"; and the picker's pages. An item is dragged between the
/// sides' lists as on the stage.
struct TopBarInspector: View {
    @Environment(AppModel.self) private var model
    @State private var targeted: HeaderSide?

    private static let settle: Animation = .spring(duration: 0.28, bounce: 0.12)

    var body: some View {
        let header = model.preferences.header
        let layout = model.layout
        let split = NotchSplit(layout: layout, presentation: .expanded(.home),
                               outerInset: Metrics.Expanded.horizontalInset, clearance: Metrics.notchClearance)
        let size = Metrics.Control.size(fittingBand: layout.notch.height)
        VStack(alignment: .leading, spacing: 12) {
            // The two sides, as tall as each other.
            HStack(alignment: .top, spacing: 12) {
                ForEach(HeaderSide.allCases, id: \.self) { side in
                    sideCard(side, header: header, fit: HeaderEar.fit(model: model, side: side, room: split.earWidth, size: size))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Drag items on the island above or between the lists. What finds no room beside the notch goes into a ⋯ menu.")
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondary)
                Spacer(minLength: 12)
                Button("Reset Top Bar") {
                    withAnimation(Self.settle) { model.preferences.header = .standard }
                    model.studio.headerSelection = nil
                }
                .controlSize(.small)
                .disabled(header == .standard)
            }
            HStack(alignment: .top, spacing: 12) {
                StudioCard("Add", subtitle: "Drag one onto the bar, or press +.") {
                    palette(header, split: split, size: size)
                }
                .frame(maxWidth: .infinity)
                StudioCard("Pages", subtitle: "The pages the picker offers, in this order.") {
                    pages(header)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Sides

    /// A side: its title and room on one line, its items; a drop anywhere on it ends the list.
    private func sideCard(_ side: HeaderSide, header: HeaderLayout, fit: HeaderFit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(side.title).font(.headline)
                Spacer(minLength: 8)
                RoomMeter(used: fit.used, room: fit.room)
            }
            sideList(side, header: header, fit: fit)
            // The room the other, longer side leaves under a short list: where an item is dropped.
            Spacer(minLength: 0)
                .frame(maxWidth: .infinity)
                .overlay {
                    GeometryReader { proxy in
                        if proxy.size.height >= 34 {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(targeted == side ? Color.islandAccent : .white.opacity(0.14),
                                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .overlay {
                                    Label("Drag an item here", systemImage: "arrow.down.to.line")
                                        .font(.caption)
                                        .foregroundStyle(SettingsPalette.secondary)
                                }
                                .padding(.top, 6)
                        }
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsPalette.card, in: .rect(cornerRadius: SettingsForm.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsForm.cardRadius, style: .continuous)
                .strokeBorder(targeted == side ? Color.islandAccent : SettingsPalette.cardStroke, lineWidth: targeted == side ? 1.5 : 1)
        }
        .dropDestination(for: String.self) { names, _ in
            drop(names, on: side, at: header.items(on: side).count)
        } isTargeted: { inside in
            if inside { targeted = side } else if targeted == side { targeted = nil }
        }
    }

    /// An item dragged from a list or the palette, placed on `side` before `index` (counted with it
    /// still where it was).
    private func drop(_ names: [String], on side: HeaderSide, at index: Int) -> Bool {
        guard let item = names.lazy.compactMap(HeaderItem.init(rawValue:)).first else { return false }
        let items = model.preferences.header.items(on: side)
        // Taken out first: an item moved down its own list lands one place higher.
        let from = items.firstIndex(of: item)
        let to = from.map { $0 < index ? index - 1 : index } ?? index
        change { $0.place(item, on: side, at: to) }
        model.studio.headerSelection = item
        targeted = nil
        return true
    }

    @ViewBuilder private func sideList(_ side: HeaderSide, header: HeaderLayout, fit: HeaderFit) -> some View {
        let items = header.items(on: side)
        VStack(spacing: 0) {
            if items.isEmpty {
                Text("Nothing on this side.")
                    .font(.callout)
                    .foregroundStyle(SettingsPalette.secondary)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            }
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                if index > 0 { Divider().opacity(0.5) }
                BarRow(item: item,
                       note: note(item, fit: fit),
                       isSelected: model.studio.headerSelection == item,
                       canMoveUp: index > 0, canMoveDown: index < items.count - 1,
                       select: { model.studio.headerSelection = item },
                       move: { delta in change { $0.place(item, on: side, at: index + delta) } },
                       cross: { change { $0.place(item, on: side == .leading ? .trailing : .leading, at: side == .leading ? 0 : $0.leading.count) } },
                       crossTitle: side == .leading ? "Move right of the notch" : "Move left of the notch",
                       remove: item.isRequired ? nil : {
                           change { $0.remove(item) }
                           if model.studio.headerSelection == item { model.studio.headerSelection = nil }
                       })
                // Dropped on a row: before it in its upper half, after it in its lower.
                .dropDestination(for: String.self) { names, location in
                    drop(names, on: side, at: location.y < BarRow.height / 2 ? index : index + 1)
                } isTargeted: { inside in
                    if inside { targeted = side } else if targeted == side { targeted = nil }
                }
            }
        }
    }

    /// Why an item of the bar is not drawn as it stands.
    private func note(_ item: HeaderItem, fit: HeaderFit) -> BarRow.Note? {
        if fit.overflow.contains(item) { return .init(text: String(localized: "In ⋯ menu"), isWarning: true) }
        if !HeaderEar.exists(item, model: model) {
            switch item {
            case .battery: return .init(text: String(localized: "No battery in this Mac"), isWarning: false)
            case .nowPlaying: return .init(text: String(localized: "While something plays"), isWarning: false)
            case .anchorWindow: return .init(text: String(localized: "While a window is held"), isWarning: false)
            default: return nil
            }
        }
        if item == .pages, fit.pages.count != model.pickerPages.count, model.pickerPages.count > 1 {
            return .init(text: String(localized: "Battery page left out: no room"), isWarning: true)
        }
        if item == .pages, model.pickerPages.count <= 1 { return .init(text: String(localized: "One page: no picker"), isWarning: false) }
        return nil
    }

    private func change(_ edit: (inout HeaderLayout) -> Void) {
        var layout = model.preferences.header
        edit(&layout)
        withAnimation(Self.settle) { model.preferences.header = layout }
    }

    // MARK: Palette

    @ViewBuilder private func palette(_ header: HeaderLayout, split: NotchSplit, size: ControlSize) -> some View {
        let unused = header.unused
        if unused.isEmpty {
            Text("Everything is in the bar.")
                .font(.callout)
                .foregroundStyle(SettingsPalette.secondary)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        } else {
            GalleryGrid(minimum: 150, maximum: 260, spacing: 8) {
                ForEach(unused) { item in
                    PaletteTile(item: item) {
                        // On the side with more room left, at its notch end.
                        let room = HeaderSide.allCases.map { side in
                            (side, split.earWidth - HeaderEar.fit(model: model, side: side, room: split.earWidth, size: size).used)
                        }
                        let side = room.max { $0.1 < $1.1 }?.0 ?? .trailing
                        change { $0.place(item, on: side, at: side == .leading ? $0.leading.count : 0) }
                        model.studio.headerSelection = item
                    }
                }
            }
        }
    }

    // MARK: Pages

    @ViewBuilder private func pages(_ header: HeaderLayout) -> some View {
        let available = model.availablePages
        let ordered = header.orderedPages
        VStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.element) { index, page in
                if index > 0 { Divider().opacity(0.5) }
                let exists = available.contains(page)
                let isShown = exists && !header.hiddenPages.contains(page)
                HStack(spacing: 10) {
                    Image(systemName: page.systemImage)
                        .frame(width: 22)
                        .foregroundStyle(isShown ? .primary : SettingsPalette.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(page.title)
                        if !exists {
                            Text(page == .shelf ? "The shelf is switched off" : "Not on this Mac")
                                .font(.caption)
                                .foregroundStyle(SettingsPalette.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    ArrowButtons(canMoveUp: index > 0, canMoveDown: index < ordered.count - 1) { delta in
                        change { $0.movePage(page, to: index + delta) }
                    }
                    Toggle(page.title, isOn: Binding(get: { isShown }, set: { shown in
                        var layout = model.preferences.header
                        if layout.setPage(page, hidden: !shown, among: available) {
                            withAnimation(Self.settle) { model.preferences.header = layout }
                        } else {
                            NSSound.beep()
                        }
                    }))
                    .labelsHidden()
                    .toggleStyle(.islandSwitch)
                    .disabled(!exists)
                    .help(isShown && model.pickerPages == [page] ? "The last page in the picker stays" : "")
                }
                .padding(.vertical, 6)
            }
            Divider().opacity(0.5)
            HStack {
                Spacer(minLength: 0)
                // Its widgets are arranged in Widgets mode, on the new page.
                Button("New Page", systemImage: "plus") {
                    guard let page = model.addPage() else { return }
                    model.studio.page = page
                    model.studio.switchMode(to: .widgets)
                }
                .controlSize(.small)
                .disabled(header.customPages.count >= CustomPage.limit)
            }
            .padding(.top, 8)
        }
    }
}

/// An item of the bar in its side's list; dragged to another place or the other side's list.
private struct BarRow: View {
    /// About as tall as a row draws (its 24 pt symbol and padding).
    static let height: CGFloat = 36

    struct Note {
        let text: String
        let isWarning: Bool
    }

    let item: HeaderItem
    let note: Note?
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let select: () -> Void
    let move: (Int) -> Void
    let cross: () -> Void
    let crossTitle: String
    /// nil for an item that stays in the bar.
    let remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(isSelected ? Color.islandAccent.opacity(0.3) : .white.opacity(0.07), in: .rect(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                if let note {
                    Text(note.text)
                        .font(.caption)
                        .foregroundStyle(note.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(SettingsPalette.secondary))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ArrowButtons(canMoveUp: canMoveUp, canMoveDown: canMoveDown, move: move)
            Button(action: cross) { Image(systemName: "arrow.left.arrow.right") }
                .help(crossTitle)
                .accessibilityLabel(crossTitle)
            Button(role: .destructive) { remove?() } label: { Image(systemName: "minus.circle") }
                .disabled(remove == nil)
                .help(remove == nil ? "\(item.title) stays in the bar" : "Take it out of the bar")
                .accessibilityLabel("Remove \(item.title)")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 6)
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .draggable(item.rawValue) {
            Label(item.title, systemImage: item.systemImage)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.8), in: Capsule())
        }
    }
}

/// Up and down in a list.
private struct ArrowButtons: View {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(!canMoveUp)
                .help("Earlier")
                .accessibilityLabel("Move earlier")
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(!canMoveDown)
                .help("Later")
                .accessibilityLabel("Move later")
        }
        .buttonStyle(.borderless)
    }
}

/// An item not in the bar: dragged onto the stage's bar, or added with its "+".
private struct PaletteTile: View {
    let item: HeaderItem
    let add: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.07), in: .rect(cornerRadius: 7, style: .continuous))
            Text(item.title).lineLimit(1)
            Spacer(minLength: 4)
            Button(action: add) { Image(systemName: "plus.circle.fill") }
                .buttonStyle(.borderless)
                .help("Add \(item.title) to the bar")
                .accessibilityLabel("Add \(item.title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.04), in: .rect(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
        .draggable(item.rawValue) {
            Label(item.title, systemImage: item.systemImage)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.8), in: Capsule())
        }
        .help(item.summary)
    }
}

/// How much of a side's room its items take ("96 of 153 pt").
private struct RoomMeter: View {
    let used: CGFloat
    let room: CGFloat

    /// The gauge's length, beside the side's title.
    private static let length: CGFloat = 64

    var body: some View {
        let share = room > 0 ? min(used / room, 1) : 1
        let isFull = used > room
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(isFull ? Color.orange : Color.islandAccent).frame(width: max(Self.length * share, 4))
            }
            .frame(width: Self.length, height: 4)
            Text("\(Int(used.rounded())) of \(Int(room.rounded())) pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(SettingsPalette.secondary)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Room used")
    }
}
