import AppKit
import SwiftUI

/// An item of the top bar in hand: where the pointer has it, and — let go over a bar — the place it
/// settles into. Watched by the chip that floats under the pointer alone, so a move of the pointer
/// goes over that one view and not the page.
@MainActor @Observable final class TopBarDrag {
    var item: HeaderItem?
    var location: CGPoint = .zero
    /// Let go over a bar: on its way to its place there.
    var isSettling = false
    /// Fading out, once nearly there (or let go nowhere).
    var isLeaving = false
    /// Over the list: let go, it leaves the bar.
    var removes = false
}

/// Under the stage in Top Bar mode, all of it in sight without scrolling and as tall as the room
/// under the stage: each side's bar — its items as round chips in their order, the page picker
/// among them with every page it offers in sight, a small pair of arrows between two that swaps
/// them — then everything the bar can hold, once, three to a row, each with a tick that puts it in
/// the bar (greyed, with a cross that takes it out, once it is there); the buttons' colour; and a red
/// Reset for both bars, level with the sidebar's foot.
///
/// A click on a chip or on a page picks it, ⌘-click picks more: Button Colour sets the colour of the
/// picks — of every button and page, with none picked.
///
/// Anything is dragged anywhere: from the list into either bar, from one bar to the other, to
/// another place in its own, and out of a bar onto the list. In hand, an item floats under the
/// pointer; over a bar, the chips there make room where it would land, and let go it settles there.
struct TopBarInspector: View {
    /// The room under the stage.
    var height: CGFloat = TopBarInspector.minimumHeight

    @Environment(AppModel.self) private var model
    @State private var drag = TopBarDrag()
    /// Where in a bar the item in hand would land now.
    @State private var landing: Landing?
    @State private var zones: [Zone: CGRect] = [:]
    /// The colour mixer is open over the list (`toggleMixer`), and what is on it in.
    @State private var showsMixer = false
    @State private var mixerContentIn = false
    @State private var buttonHeight: CGFloat = 36

    struct Landing: Equatable {
        var side: HeaderSide
        /// Among the side's items without the one in hand.
        var index: Int
    }

    private enum Zone: Hashable {
        case card(HeaderSide), row(HeaderSide), list
    }

    static let space = "topBarInspector"
    static let settle: Animation = .spring(duration: 0.3, bounce: 0.18)
    /// The least it takes: its bars, the list at its tiles' lowest, and the two buttons.
    static let minimumHeight: CGFloat = 356
    /// Inside a card, from its edge to what is in it.
    static let inset: CGFloat = 10
    static let chip: CGFloat = 34
    /// Between two chips: the swap arrows' room.
    static let gap: CGFloat = 20
    static let spacing: CGFloat = 10

    var body: some View {
        let header = model.preferences.header
        let layout = model.layout
        let split = NotchSplit(layout: layout, presentation: .expanded(.home),
                               outerInset: Metrics.Expanded.horizontalInset, clearance: Metrics.notchClearance)
        let size = Metrics.Control.size(fittingBand: layout.notch.height)
        VStack(spacing: Self.spacing) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(HeaderSide.allCases, id: \.self) { side in
                    barCard(side, header: header, fit: HeaderEar.fit(model: model, side: side, room: split.earWidth, size: size))
                }
            }
            ZStack(alignment: .bottom) {
                VStack(spacing: Self.spacing) {
                    listCard(header, split: split, size: size)
                    colourButton(header)
                    // Both bars as they were, in one: red, a capsule, as wide as the list over it.
                    Button(role: .destructive) {
                        change { $0.resetBars() }
                        model.studio.headerPicks = []
                    } label: {
                        Text("Reset Bars").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(header.hasStandardBars)
                    .help("Both bars as they were: the pages on the left; battery, Siri, Keep Open and Settings on the right, each in its own colour")
                    // Under the mixer while it is open: its red showed round the box's corners.
                    .opacity(mixerContentIn ? 0 : 1)
                }
                mixerBox(header)
            }
        }
        .frame(height: max(height, Self.minimumHeight))
        .coordinateSpace(.named(Self.space))
        .overlay { FloatingChip(drag: drag) }
    }

    private func card(isTargeted: Bool) -> some View {
        RoundedRectangle(cornerRadius: SettingsForm.cardRadius, style: .continuous)
            .fill(SettingsPalette.card)
            .overlay {
                RoundedRectangle(cornerRadius: SettingsForm.cardRadius, style: .continuous)
                    .strokeBorder(isTargeted ? Color.islandAccent : SettingsPalette.cardStroke, lineWidth: isTargeted ? 1.5 : 1)
            }
    }

    private func note(_ zone: Zone) -> (CGRect) -> Void {
        { frame in if zones[zone] != frame { zones[zone] = frame } }
    }

    // MARK: A side's bar

    /// What a bar shows: its items — without the one in hand, and with its place kept where it
    /// would land.
    private enum Slot: Hashable {
        case item(HeaderItem)
        case landing(HeaderItem)
    }

    /// The item in hand (not one already let go and settling).
    private var held: HeaderItem? { drag.isSettling || drag.isLeaving ? nil : drag.item }

    /// The item in hand stays in its own bar's row all the while — it is the view that follows the
    /// drag, and taken away it never heard of the drag's end (the chip in hand froze where it was
    /// let go). In its own bar it stands where it would land, drawn as the place kept open; over the
    /// other bar or nowhere it is folded away at the row's end.
    private func slots(_ side: HeaderSide, header: HeaderLayout) -> [Slot] {
        var items = header.items(on: side)
        guard let held else { return items.map(Slot.item) }
        let isOwn = items.contains(held)
        items.removeAll { $0 == held }
        var slots = items.map(Slot.item)
        if let landing, landing.side == side {
            slots.insert(isOwn ? .item(held) : .landing(held), at: min(max(landing.index, 0), slots.count))
        } else if isOwn {
            slots.append(.item(held))
        }
        return slots
    }

    /// The item in hand, in its own bar, while it is not over it: folded away.
    private func isFolded(_ slot: Slot, side: HeaderSide) -> Bool {
        if case .item(let item) = slot, item == held, landing?.side != side { return true }
        return false
    }

    /// The place kept open for the item in hand.
    private func place(_ item: HeaderItem) -> some View {
        Capsule()
            .fill(Color.islandAccent.opacity(0.16))
            .overlay { Capsule().strokeBorder(Color.islandAccent.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) }
            .frame(width: width(item), height: Self.chip)
    }

    private func width(_ item: HeaderItem) -> CGFloat {
        item == .pages ? PagesGroup.width(pages: model.pickerPages.count) : Self.chip
    }

    /// The side's bar: its chips in order, a swap between each two.
    private func barCard(_ side: HeaderSide, header: HeaderLayout, fit: HeaderFit) -> some View {
        let items = header.items(on: side)
        let slots = slots(side, header: header)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(side == .leading ? "Top Bar Left" : "Top Bar Right").font(.headline)
                Spacer(minLength: 8)
                RoomMeter(used: fit.used, room: fit.room)
            }
            HStack(spacing: 0) {
                if slots.isEmpty {
                    Label("Drag an item here", systemImage: "arrow.down.to.line")
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                        .frame(maxWidth: .infinity, minHeight: Self.chip)
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                }
                ForEach(Array(slots.enumerated()), id: \.element) { index, slot in
                    let folded = isFolded(slot, side: side)
                    if index > 0, !folded { between(slots[index - 1], slot, side: side, items: items) }
                    switch slot {
                    case .item(let item):
                        let inHand = held == item
                        Group {
                            if item == .pages {
                                // The pages, each in sight, in a bar of their own.
                                PagesGroup(moved: { dragChanged(.pages, to: $0) }, ended: { dragEnded() })
                            } else {
                                BarChip(item: item, isLifted: model.studio.headerPicks.contains(.item(item)),
                                        tint: header.itemTints[item]?.color,
                                        isOverflowing: fit.overflow.contains(item), note: note(item, fit: fit)?.text,
                                        lift: {
                                            // Alone, or with ⌘ one more of the picks.
                                            let adds = NSEvent.modifierFlags.contains(.command)
                                            withAnimation(Self.settle) { model.studio.pick(.item(item), adding: adds) }
                                        }, moved: { dragChanged(item, to: $0) }, ended: { dragEnded() })
                            }
                        }
                        // In hand: unseen here (it floats under the pointer), its place kept open.
                        .opacity(inHand ? 0 : 1)
                        .overlay { if inHand, !folded { place(item) } }
                        .frame(width: folded ? 0 : nil)
                        .zIndex(model.studio.headerPicks.contains(.item(item)) ? 1 : 0)
                    case .landing(let item):
                        // Where the one in hand would land: its place, kept open.
                        place(item)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: Self.chip + 6)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }, action: note(.row(side)))
            .animation(Self.settle, value: slots)
        }
        .padding(.horizontal, Self.inset + 2)
        .padding(.vertical, Self.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card(isTargeted: landing?.side == side))
        // A click beside the chips lets the picks go.
        .contentShape(.rect)
        .onTapGesture {
            if !model.studio.headerPicks.isEmpty { withAnimation(Self.settle) { model.studio.headerPicks = [] } }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }, action: note(.card(side)))
    }

    /// Between two chips: the pair of arrows that swaps them (nothing beside a place kept open).
    @ViewBuilder private func between(_ before: Slot, _ after: Slot, side: HeaderSide, items: [HeaderItem]) -> some View {
        if case .item(let first) = before, case .item(let second) = after, first != held, second != held,
           let index = items.firstIndex(of: second) {
            Button {
                change { $0.place(second, on: side, at: index - 1) }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(SettingsPalette.secondary)
                    .frame(width: Self.gap, height: Self.chip)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Swap \(first.title) and \(second.title)")
            .accessibilityLabel("Swap \(first.title) and \(second.title)")
        } else {
            Color.clear.frame(width: Self.gap, height: Self.chip)
        }
    }

    // MARK: Dragging

    /// An item in hand, the pointer at `point`: over a bar, the place it would land — before the
    /// first chip whose middle the pointer has not passed.
    private func dragChanged(_ item: HeaderItem, to point: CGPoint) {
        if drag.item != item || drag.isSettling || drag.isLeaving {
            drag.isSettling = false
            drag.isLeaving = false
            drag.removes = false
            drag.location = point
            withAnimation(.spring(duration: 0.22, bounce: 0.3)) { drag.item = item }
        }
        drag.location = point
        var next: Landing?
        for side in HeaderSide.allCases {
            guard let card = zones[.card(side)], card.insetBy(dx: -4, dy: -10).contains(point), let row = zones[.row(side)] else { continue }
            let items = model.preferences.header.items(on: side).filter { $0 != item }
            var edge = row.minX
            var index = items.count
            for (place, other) in items.enumerated() {
                let width = width(other)
                if point.x < edge + width / 2 {
                    index = place
                    break
                }
                edge += width + Self.gap
            }
            next = Landing(side: side, index: index)
        }
        if landing != next {
            // A place opens for it between the chips: felt on the trackpad.
            if next != nil { SnapTick.perform() }
            withAnimation(Self.settle) { landing = next }
        }
        let removes = next == nil && zones[.list]?.contains(point) == true && model.preferences.header.contains(item) && !item.isRequired
        if drag.removes != removes { withAnimation(.easeOut(duration: 0.15)) { drag.removes = removes } }
    }

    /// Let go: over a bar it settles into the place kept for it; over the list it leaves the bar;
    /// anywhere else it goes back.
    private func dragEnded() {
        guard let item = drag.item, !drag.isSettling, !drag.isLeaving else { return }
        if let landing, let row = zones[.row(landing.side)] {
            let items = model.preferences.header.items(on: landing.side).filter { $0 != item }
            let before = items.prefix(landing.index).reduce(CGFloat(0)) { $0 + width($1) + Self.gap }
            let place = CGPoint(x: row.minX + before + width(item) / 2, y: row.midY)
            // In its place at once, with no move of its own; the one in hand glides onto it and fades.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                drag.isSettling = true
                self.landing = nil
                var header = model.preferences.header
                header.place(item, on: landing.side, at: landing.index)
                model.preferences.header = header
            }
            withAnimation(.spring(duration: 0.3, bounce: 0.28)) { drag.location = place }
            withAnimation(.easeIn(duration: 0.14).delay(0.16)) { drag.isLeaving = true }
            // As it clicks into its place.
            Task {
                try? await Task.sleep(for: .milliseconds(170))
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        } else {
            if drag.removes {
                change { $0.remove(item) }
                model.studio.headerPicks.remove(.item(item))
            }
            withAnimation(.easeIn(duration: 0.16)) { drag.isLeaving = true }
            withAnimation(Self.settle) { landing = nil }
        }
        let ended = item
        Task {
            try? await Task.sleep(for: .milliseconds(340))
            // Not one picked up again meanwhile.
            guard drag.item == ended, drag.isLeaving else { return }
            drag.item = nil
            drag.isSettling = false
            drag.isLeaving = false
            drag.removes = false
        }
    }

    // MARK: What the bar can hold

    /// Everything the bar can hold, once, three to a row: a tick puts one in the bar (on the side
    /// with more room left); in a bar, it is greyed and its cross takes it out. Dragged into either
    /// bar; a chip let go here leaves its bar.
    private func listCard(_ header: HeaderLayout, split: NotchSplit, size: ControlSize) -> some View {
        let items = HeaderItem.allCases
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Add to the Top Bar").font(.headline)
            VStack(spacing: 6) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(rows[row]) { item in
                            ListTile(item: item, isInBar: header.contains(item), isHeld: drag.item == item,
                                     add: {
                                         // On the side with more room left, at its notch end.
                                         let room = HeaderSide.allCases.map { side in
                                             (side, split.earWidth - HeaderEar.fit(model: model, side: side, room: split.earWidth, size: size).used)
                                         }
                                         let side = room.max { $0.1 < $1.1 }?.0 ?? .trailing
                                         change { $0.place(item, on: side, at: side == .leading ? $0.leading.count : 0) }
                                     },
                                     remove: item.isRequired ? nil : {
                                         change { $0.remove(item) }
                                         model.studio.headerPicks.remove(.item(item))
                                     }, moved: { dragChanged(item, to: $0) }, ended: { dragEnded() })
                        }
                        // A shorter last row keeps the tiles' width.
                        ForEach(0..<(3 - rows[row].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(Self.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(card(isTargeted: drag.removes))
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }, action: note(.list))
    }

    // MARK: The buttons' colour

    /// What Button Colour sets the colour of: the picks that are in the bar — with none, every
    /// button the bar can hold and every page.
    private func targets(_ header: HeaderLayout) -> [HeaderPart] {
        let inBar = (header.leading + header.trailing).filter { $0 != .pages }.map(HeaderPart.item)
            + model.pickerPages.map(HeaderPart.page)
        let picked = inBar.filter(model.studio.headerPicks.contains)
        if !picked.isEmpty { return picked }
        return HeaderItem.allCases.filter { $0 != .pages }.map(HeaderPart.item) + header.orderedPages.map(HeaderPart.page)
    }

    /// Whether any of the bar's parts is picked (not only one that has left it).
    private func hasPicks(_ header: HeaderLayout) -> Bool {
        model.studio.headerPicks.contains { part in
            switch part {
            case .item(let item): header.contains(item)
            case .page(let page): model.pickerPages.contains(page)
            }
        }
    }

    private func title(of part: HeaderPart) -> String {
        switch part {
        case .item(let item): item.title
        case .page(let page): page.title
        }
    }

    /// "Colour of Settings", "Colour of 3 Buttons", or of them all.
    private func colourTitle(_ header: HeaderLayout) -> String {
        guard hasPicks(header) else { return String(localized: "Button Colour") }
        let targets = targets(header)
        if targets.count == 1, let only = targets.first { return String(localized: "Colour of \(title(of: only))") }
        return String(localized: "Colour of \(targets.count) Buttons")
    }

    /// The colours `targets` have now, in their order, each once (white for one in its own).
    private func colours(_ header: HeaderLayout) -> [Color] {
        var seen: Set<IslandTheme.RGB?> = []
        return targets(header).map { header.tint(of: $0) }.filter { seen.insert($0).inserted }.map { $0?.color ?? .white }
    }

    /// The colour of the bar's buttons: a capsule as large as Reset under it; pressed, the mixer
    /// opens out of it, upwards over the list.
    private func colourButton(_ header: HeaderLayout) -> some View {
        let colours = colours(header)
        return Button { toggleMixer() } label: {
            HStack(spacing: 8) {
                Circle()
                    // The picks in more than one colour: all of them, round the swatch.
                    .fill(colours.count == 1 ? AnyShapeStyle(colours[0])
                          : AnyShapeStyle(AngularGradient(colors: colours + colours.prefix(1), center: .center)))
                    .overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1) }
                    .frame(width: 14, height: 14)
                Text(colourTitle(header))
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonHeight = $0 }
        .help("The colour of the top bar's buttons: of the ones picked above (click one, ⌘-click more), or of them all")
    }

    /// Opened and closed as Customize's Open Widgets and Size's ready-made sizes are: the box grows
    /// out of the button, then what is on it comes in; that goes first on the way back.
    private func toggleMixer() {
        let pace = 0.8
        if showsMixer {
            withAnimation(.easeIn(duration: 0.12 * pace)) { mixerContentIn = false }
            withAnimation(.spring(duration: 0.38 * pace, bounce: 0.08).delay(0.06 * pace)) { showsMixer = false }
        } else {
            withAnimation(.spring(duration: 0.55 * pace, bounce: 0.22)) { showsMixer = true }
            withAnimation(.spring(duration: 0.45 * pace, bounce: 0.1).delay(0.1 * pace)) { mixerContentIn = true }
        }
    }

    /// The mixer's box: from the button's capsule up over the list and down over Reset.
    private func mixerBox(_ header: HeaderLayout) -> some View {
        GeometryReader { proxy in
            let radius = showsMixer ? WidgetVersionsMenu.radius : buttonHeight / 2
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(colourTitle(header)).font(.headline)
                    Text(hasPicks(header) ? "Click another button above to colour that one, ⌘-click to colour more together."
                         : "Every button and page. Click one above to colour it alone, ⌘-click to pick more.")
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Button("Automatic") {
                        var layout = model.preferences.header
                        layout.setTint(nil, of: targets(layout))
                        withAnimation(Self.settle) { model.preferences.header = layout }
                    }
                    .disabled(targets(header).allSatisfy { header.tint(of: $0) == nil })
                    .help("These in their own colour")
                    Button("Done") { toggleMixer() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.cancelAction)
                }
                .buttonBorderShape(.capsule)
                // The mixer is taller than the room over the buttons: its recent colours scroll.
                ScrollView(.vertical) {
                    ColorMixer(rgb: Binding(get: {
                        let header = model.preferences.header
                        return targets(header).lazy.compactMap { header.tint(of: $0) }.first ?? IslandTheme.RGB(red: 1, green: 1, blue: 1)
                    }, set: { tint in
                        var layout = model.preferences.header
                        layout.setTint(tint, of: targets(layout))
                        model.preferences.header = layout
                    }))
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.automatic)
            }
            .padding(12)
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Comes up out of a blur and a little from below as the box opens around it.
            .opacity(mixerContentIn ? 1 : 0)
            .blur(radius: mixerContentIn ? 0 : 6)
            .offset(y: mixerContentIn ? 0 : 10)
            .frame(width: proxy.size.width, height: showsMixer ? proxy.size.height : buttonHeight, alignment: .bottom)
            .background { SettingsBackdrop() }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(showsMixer ? 0.5 : 0), radius: 18, y: 8)
            .opacity(showsMixer ? 1 : 0)
            .allowsHitTesting(showsMixer)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // Closed, it is the button: over Reset by the button's height and the gap.
            .offset(y: showsMixer ? 0 : -(buttonHeight + Self.spacing))
        }
    }

    /// Why an item of the bar is not drawn as it stands.
    private func note(_ item: HeaderItem, fit: HeaderFit) -> BarNote? {
        if fit.overflow.contains(item) { return .init(text: String(localized: "In ⋯ menu: no room beside the notch"), isWarning: true) }
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
}

private struct BarNote {
    let text: String
    let isWarning: Bool
}

/// The item in hand, under the pointer: its chip larger and lifted off the page, a shadow under it;
/// let go over a bar it glides to its place, shrinking to a chip's size, and fades onto the chip there.
private struct FloatingChip: View {
    let drag: TopBarDrag

    var body: some View {
        if let item = drag.item {
            Image(systemName: item.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(drag.removes ? Color.red.opacity(0.85) : Color.islandAccent.opacity(0.9), in: .circle)
                .overlay { Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5) }
                .overlay(alignment: .topTrailing) {
                    if drag.removes {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white, .red)
                            .offset(x: 4, y: -4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .scaleEffect(drag.isSettling ? TopBarInspector.chip / 42 : 1.12)
                .rotationEffect(.degrees(drag.isSettling || drag.isLeaving ? 0 : -4))
                .shadow(color: .black.opacity(drag.isSettling ? 0.15 : 0.5), radius: drag.isSettling ? 3 : 12, y: drag.isSettling ? 1 : 8)
                .opacity(drag.isLeaving ? 0 : 1)
                // Moved, not laid out: where it is drawn changes at every move of the pointer, the
                // page's layout never.
                .offset(x: drag.location.x - 21, y: drag.location.y - 21)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }
}

/// An item in its side's bar: a round chip. Clicked, it is lifted over the others; dragged to
/// another place, to the other bar, or out onto the list.
private struct BarChip: View {
    let item: HeaderItem
    /// Picked: Button Colour colours it.
    let isLifted: Bool
    /// The colour set for it; nil: its own.
    let tint: Color?
    let isOverflowing: Bool
    let note: String?
    let lift: () -> Void
    /// Dragged: the pointer in the inspector's space; and let go.
    let moved: (CGPoint) -> Void
    let ended: () -> Void

    @State private var isHovered = false
    @GestureState private var isDragging = false

    var body: some View {
        Image(systemName: item.systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint ?? .white)
            .frame(width: TopBarInspector.chip, height: TopBarInspector.chip)
            .background(isLifted ? Color.islandAccent.opacity(0.45) : .white.opacity(isHovered ? 0.16 : 0.08), in: .circle)
            .overlay { Circle().strokeBorder(isLifted ? Color.islandAccent : .white.opacity(0.1), lineWidth: isLifted ? 1.5 : 1) }
            .overlay(alignment: .topTrailing) {
                // No room beside the notch: it is in the ⋯ menu.
                if isOverflowing {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                        .overlay { Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1) }
                }
            }
            .scaleEffect(isLifted ? 1.14 : isHovered ? 1.05 : 1)
            .offset(y: isLifted ? -2 : 0)
            .shadow(color: .black.opacity(isLifted ? 0.5 : 0), radius: isLifted ? 7 : 0, y: isLifted ? 5 : 0)
            .contentShape(.circle)
            .onTapGesture(perform: lift)
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named(TopBarInspector.space))
                    .updating($isDragging) { _, dragging, _ in dragging = true }
                    .onChanged { moved($0.location) }
            )
            // Let go, or the drag taken away from it: either way it ends.
            .finishingCancelledDrag(isDragging, finish: ended)
            .onHover { isHovered = $0 }
            .animation(.spring(duration: 0.22, bounce: 0.25), value: isHovered)
            .help(note.map { "\(item.title): \($0)" } ?? "\(item.title): drag it to its place; click it to colour it, ⌘-click to pick more")
            .accessibilityLabel(item.title)
            .accessibilityAddTraits(isLifted ? [.isButton, .isSelected] : .isButton)
    }
}

/// The page picker in its bar, with every page it offers in sight: a capsule of its own, apart from
/// the chips, the pages in the picker's order. A page dragged sideways changes places with the ones
/// it passes, at once; a pair of arrows between two swaps them. Pulled up or down out of the
/// capsule, it is the whole picker that comes, as a chip does.
private struct PagesGroup: View {
    /// The whole picker dragged: the pointer in the inspector's space; and let go.
    let moved: (CGPoint) -> Void
    let ended: () -> Void

    @Environment(AppModel.self) private var model
    /// The page in hand: where it began, and how far the pointer has taken it.
    @State private var held: (page: ExpandedPage, start: Int, travel: CGFloat)?
    /// The pull has left the capsule: the picker itself is dragged.
    @State private var dragsPicker = false
    @GestureState private var isDragging = false

    static let icon: CGFloat = 26
    static let gap: CGFloat = 14
    static let padding: CGFloat = 5
    private static var pitch: CGFloat { icon + gap }
    /// Pulled this far up or down, a page takes the picker with it.
    private static let pull: CGFloat = 24

    static func width(pages: Int) -> CGFloat {
        CGFloat(max(pages, 1)) * icon + CGFloat(max(pages - 1, 0)) * gap + 2 * padding
    }

    var body: some View {
        let pages = model.pickerPages
        let tints = model.preferences.header.pageTints
        let picks = model.studio.headerPicks
        HStack(spacing: 0) {
            ForEach(Array(pages.enumerated()), id: \.element) { index, page in
                if index > 0 {
                    Button { move(page, to: index - 1) } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(SettingsPalette.secondary)
                            .frame(width: Self.gap, height: Self.icon)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .opacity(held == nil ? 1 : 0)
                    .help("Swap \(pages[index - 1].title) and \(page.title)")
                    .accessibilityLabel("Swap \(pages[index - 1].title) and \(page.title)")
                }
                icon(page, at: index, among: pages, tint: tints[page]?.color, isPicked: picks.contains(.page(page)))
            }
        }
        .padding(Self.padding)
        .background(.white.opacity(0.06), in: .capsule)
        .overlay { Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1) }
        .finishingCancelledDrag(isDragging, finish: finish)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pages")
    }

    /// A page's symbol in its circle, in the colour set for it; picked, it is ringed.
    private func icon(_ page: ExpandedPage, at index: Int, among pages: [ExpandedPage], tint: Color?, isPicked: Bool) -> some View {
        let isHeld = held?.page == page
        let fill: Color = isHeld ? .islandAccent.opacity(0.85) : isPicked ? .islandAccent.opacity(0.45) : .white.opacity(0.1)
        // In hand it follows the pointer; the places it has passed are already its.
        let travel: CGFloat = isHeld ? (held?.travel ?? 0) - CGFloat(index - (held?.start ?? index)) * Self.pitch : 0
        return Image(systemName: page.systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint ?? .white)
            .frame(width: Self.icon, height: Self.icon)
            .background(fill, in: .circle)
            .overlay { Circle().strokeBorder(Color.islandAccent.opacity(isPicked && !isHeld ? 1 : 0), lineWidth: 1.5) }
            .scaleEffect(isHeld ? 1.18 : 1)
            .shadow(color: .black.opacity(isHeld ? 0.5 : 0), radius: isHeld ? 6 : 0, y: isHeld ? 4 : 0)
            .offset(x: travel)
            .zIndex(isHeld ? 1 : 0)
            .contentShape(.circle)
            // Picked alone, or with ⌘ one more: Button Colour colours the picks.
            .onTapGesture {
                let adds = NSEvent.modifierFlags.contains(.command)
                withAnimation(TopBarInspector.settle) { model.studio.pick(.page(page), adding: adds) }
            }
            .gesture(drag(page, at: index, among: pages))
            .help("\(page.title): drag it along to change the picker's order; click it to colour it, ⌘-click to pick more")
            .accessibilityLabel(page.title)
            .accessibilityAddTraits(isPicked ? [.isButton, .isSelected] : .isButton)
    }

    private func drag(_ page: ExpandedPage, at index: Int, among pages: [ExpandedPage]) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(TopBarInspector.space))
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                if dragsPicker || abs(value.translation.height) > Self.pull {
                    // Out of the capsule: the picker itself.
                    if !dragsPicker {
                        dragsPicker = true
                        withAnimation(TopBarInspector.settle) { held = nil }
                    }
                    return moved(value.location)
                }
                let start = held?.page == page ? held?.start ?? index : index
                if held?.page != page {
                    withAnimation(.spring(duration: 0.2, bounce: 0.3)) { held = (page, start, value.translation.width) }
                } else {
                    held?.travel = value.translation.width
                }
                // Past the middle of the next place: it is its.
                let target = min(max(start + Int((value.translation.width / Self.pitch).rounded()), 0), pages.count - 1)
                if let now = pages.firstIndex(of: page), now != target { move(page, to: target) }
            }
    }

    /// Let go (or the drag taken away): the picker's drag ends, or the page settles into the place
    /// it has — its own travel ends where the place is.
    private func finish() {
        if dragsPicker {
            dragsPicker = false
            return ended()
        }
        guard let held, let now = model.pickerPages.firstIndex(of: held.page) else { return }
        let page = held.page
        withAnimation(.spring(duration: 0.28, bounce: 0.3)) {
            self.held = (held.page, held.start, CGFloat(now - held.start) * Self.pitch)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            if self.held?.page == page { self.held = nil }
        }
    }

    /// `page` to the `index`th place among the pages the picker shows.
    private func move(_ page: ExpandedPage, to index: Int) {
        var layout = model.preferences.header
        let shown = model.pickerPages.filter { $0 != page }
        var order = layout.orderedPages
        order.removeAll { $0 == page }
        // Before the page that now stands there, or at the end.
        let place = index < shown.count ? order.firstIndex(of: shown[index]) ?? order.count : (shown.last.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? order.count)
        layout.movePage(page, to: place)
        // Into its new place: felt on the trackpad.
        SnapTick.perform()
        withAnimation(TopBarInspector.settle) { model.preferences.header = layout }
    }
}

/// Something the bar can hold, in the list: a capsule, three to a row. A tick puts it in the bar;
/// once there it is greyed and a cross takes it out (a lock for one that stays). Dragged into
/// either bar.
private struct ListTile: View {
    let item: HeaderItem
    let isInBar: Bool
    /// In hand now: its place in the list is faint.
    let isHeld: Bool
    let add: () -> Void
    /// nil for an item that stays in the bar.
    let remove: (() -> Void)?
    let moved: (CGPoint) -> Void
    let ended: () -> Void

    @State private var isHovered = false
    @GestureState private var isDragging = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                Image(systemName: item.systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.09), in: .circle)
                Text(item.title)
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            // In the bar already: greyed.
            .opacity(isInBar ? 0.4 : 1)
            Spacer(minLength: 0)
            if isInBar {
                Button(role: .destructive) { remove?() } label: {
                    Image(systemName: remove == nil ? "lock.fill" : "xmark.circle.fill")
                        .font(.system(size: remove == nil ? 10 : 14))
                }
                .disabled(remove == nil)
                .help(remove == nil ? "\(item.title) stays in the bar" : "Take \(item.title) out of the bar")
                .accessibilityLabel(remove == nil ? "\(item.title) stays in the bar" : "Remove \(item.title)")
            } else {
                Button(action: add) { Image(systemName: "checkmark.circle").font(.system(size: 14)) }
                    .help("Add \(item.title) to the bar")
                    .accessibilityLabel("Add \(item.title)")
            }
        }
        .buttonStyle(.borderless)
        .padding(.leading, 4)
        .padding(.trailing, 7)
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 34)
        .background(.white.opacity(isInBar ? 0.02 : isHovered ? 0.1 : 0.06), in: .capsule)
        .opacity(isHeld ? 0.35 : 1)
        .contentShape(.capsule)
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named(TopBarInspector.space))
                .updating($isDragging) { _, dragging, _ in dragging = true }
                .onChanged { moved($0.location) }
        )
        .finishingCancelledDrag(isDragging, finish: ended)
        .onHover { isHovered = $0 }
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
