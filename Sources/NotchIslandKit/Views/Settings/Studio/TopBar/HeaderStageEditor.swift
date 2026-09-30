import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The stage's top bar in Top Bar mode: each item a chip where the panel draws it, dragged along
/// its side and across the notch (the others make room as it goes), dragged down out of the band
/// to take it out. A dashed outline shows each side's room; what does not fit is in "⋯", live.
struct HeaderStageEditor: View {
    let split: NotchSplit
    let height: CGFloat

    @Environment(AppModel.self) private var model
    @State private var drag: Drag?
    @State private var hovered: HeaderItem?
    @State private var isDropTargeted = false
    @GestureState private var isDragging = false
    @FocusState private var isFocused: Bool

    /// A chip on its way.
    private struct Drag: Equatable {
        let item: HeaderItem
        /// The pointer, in the band.
        var location: CGPoint
        /// From the chip's middle to where it was taken hold of.
        let grip: CGSize
        /// The bar as it would be were the chip let go now.
        var layout: HeaderLayout
        /// Far enough under the band: let go, it leaves the bar.
        var removes: Bool
    }

    private static let space = "headerStage"
    private static let settle: Animation = .spring(duration: 0.28, bounce: 0.12)

    var body: some View {
        let size = Metrics.Control.size(fittingBand: height)
        let layout = drag?.layout ?? model.preferences.header
        ZStack(alignment: .topLeading) {
            ForEach(HeaderSide.allCases, id: \.self) { side in
                let ear = side == .leading ? split.leadingEar : split.trailingEar
                let fit = HeaderEar.fit(model: model, side: side, room: split.earWidth, size: size, layout: layout)
                let frames = HeaderDrop.frames(fit, side: side, split: split, size: size) { HeaderEar.pickerWidth(pages: $0, size: size) }
                // The side's room.
                RoundedRectangle(cornerRadius: (height - 6) / 2, style: .continuous)
                    .strokeBorder(.white.opacity(isDropTargeted || drag != nil ? 0.5 : 0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: ear.upperBound - ear.lowerBound + 8, height: height - 6)
                    .offset(x: ear.lowerBound - 4, y: 3)
                    .allowsHitTesting(false)
                ForEach(Array(zip(fit.shown, frames.items)), id: \.0) { item, frame in
                    // The dragged chip's place is kept open; the chip itself follows the pointer.
                    if item != drag?.item {
                        chip(item, pages: fit.pages, width: frame.upperBound - frame.lowerBound)
                            .offset(x: frame.lowerBound)
                    }
                }
                if let menu = frames.menu {
                    Image(systemName: "ellipsis")
                        .font(.system(size: size == .mini ? 9 : 11, weight: .bold))
                        .frame(width: menu.upperBound - menu.lowerBound, height: height)
                        .background(.white.opacity(0.14), in: Circle())
                        .offset(x: menu.lowerBound)
                        .help("In the ⋯ menu: \(fit.overflow.map(\.title).formatted(.list(type: .and)))")
                }
            }
            if let drag {
                let width = Self.width(drag.item, layout: drag.layout, model: model, size: size)
                chipPicture(drag.item, pages: model.pickerPages, width: width)
                    .background { Capsule().fill(.black.opacity(0.6)).frame(width: max(width + 8, height - 8), height: height - 8) }
                    .overlay {
                        Capsule().strokeBorder(drag.removes ? Color.red : Color.islandAccent, lineWidth: 1.5)
                            .frame(width: max(width + 8, height - 8), height: height - 8)
                    }
                    .overlay(alignment: .topTrailing) {
                        if drag.removes {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.white, .red)
                                .font(.system(size: 12))
                                .offset(x: 8, y: -4)
                        }
                    }
                    .opacity(drag.removes ? 0.7 : 1)
                    .scaleEffect(1.08)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                    .offset(x: drag.location.x - drag.grip.width - width / 2, y: drag.location.y - drag.grip.height - height / 2)
                    .allowsHitTesting(false)
                    .zIndex(2)
            }
        }
        .frame(width: split.islandWidth, height: height, alignment: .topLeading)
        .animation(Self.settle, value: layout)
        .coordinateSpace(.named(Self.space))
        .controlSize(size)
        .environment(\.showsControlHelp, false)
        .environment(\.isHeaderPicture, true)
        .contentShape(.rect)
        .onTapGesture { model.studio.headerSelection = nil }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            step(press.key == .leftArrow ? -1 : 1) ? .handled : .ignored
        }
        .onDeleteCommand(perform: removeSelected)
        .onChange(of: model.studio.headerSelection) { _, new in if new != nil { isFocused = true } }
        .finishingCancelledDrag(isDragging, finish: finish)
        // From the palette under the stage.
        .dropDestination(for: String.self) { names, location in
            guard let item = names.lazy.compactMap(HeaderItem.init(rawValue:)).first else { return false }
            let target = target(for: item, x: location.x, size: size)
            withAnimation(Self.settle) { model.preferences.header.place(item, on: target.side, at: target.index) }
            model.studio.headerSelection = item
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    // MARK: Chips

    private func chip(_ item: HeaderItem, pages: [ExpandedPage], width: CGFloat) -> some View {
        let isSelected = model.studio.headerSelection == item
        return chipPicture(item, pages: pages, width: width)
            .overlay {
                // Round the chip, as tall as the side's outline.
                Capsule()
                    .strokeBorder(isSelected ? Color.islandAccent : .white.opacity(hovered == item ? 0.45 : 0), lineWidth: isSelected ? 1.5 : 1)
                    .frame(width: max(width + 8, height - 8), height: height - 8)
            }
            .contentShape(.rect)
            .onHover { inside in
                if inside { hovered = item } else if hovered == item { hovered = nil }
            }
            .onTapGesture { model.studio.headerSelection = item }
            .gesture(dragGesture(item, width: width))
            .help(item.isRequired ? "\(item.title): drag to move it" : "\(item.title): drag to move it, down to take it out")
            .accessibilityElement()
            .accessibilityLabel(item.title)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The item as the panel draws it, centred in its room: a picture.
    private func chipPicture(_ item: HeaderItem, pages: [ExpandedPage], width: CGFloat) -> some View {
        HeaderItemView(item: item, pages: pages)
            .allowsHitTesting(false)
            .frame(width: width, height: height)
    }

    /// The width the item is drawn at in `layout` (the picker's depends on the pages it shows).
    private static func width(_ item: HeaderItem, layout: HeaderLayout, model: AppModel, size: ControlSize) -> CGFloat {
        let picker = HeaderEar.pickerWidth(pages: layout.pages(among: model.availablePages), size: size)
        return HeaderFit.width(of: item, size: size, picker: picker)
    }

    // MARK: Dragging

    private func dragGesture(_ item: HeaderItem, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .tracking($isDragging)
            .onChanged { value in
                let size = Metrics.Control.size(fittingBand: height)
                let base = model.preferences.header
                var current = drag ?? begin(item, at: value.startLocation, size: size, base: base)
                current.location = value.location
                let removes = !item.isRequired && value.location.y > height + HeaderDrop.removeDistance
                // Where its middle is, not where it was taken hold of.
                let target = target(for: item, x: value.location.x - current.grip.width, size: size)
                var layout = base
                if removes { layout.remove(item) } else { layout.place(item, on: target.side, at: target.index) }
                if layout != current.layout || removes != current.removes { SnapTick.perform() }
                current.layout = layout
                current.removes = removes
                drag = current
            }
            .onEnded { _ in finish() }
    }

    private func begin(_ item: HeaderItem, at start: CGPoint, size: ControlSize, base: HeaderLayout) -> Drag {
        model.studio.headerSelection = item
        // The chip's middle, from where the panel draws it now.
        var middle = start.x
        for side in HeaderSide.allCases {
            let fit = HeaderEar.fit(model: model, side: side, room: split.earWidth, size: size, layout: base)
            let frames = HeaderDrop.frames(fit, side: side, split: split, size: size) { HeaderEar.pickerWidth(pages: $0, size: size) }
            if let index = fit.shown.firstIndex(of: item) {
                middle = (frames.items[index].lowerBound + frames.items[index].upperBound) / 2
            }
        }
        return Drag(item: item, location: start, grip: CGSize(width: start.x - middle, height: start.y - height / 2), layout: base, removes: false)
    }

    /// Where `item` lands with its middle at `x`: among the other items, as the bar draws them
    /// without it.
    private func target(for item: HeaderItem, x: CGFloat, size: ControlSize) -> (side: HeaderSide, index: Int) {
        let base = model.preferences.header
        var frames: [HeaderSide: [ClosedRange<CGFloat>]] = [:]
        var drawn: [HeaderSide: [HeaderItem]] = [:]
        for side in HeaderSide.allCases {
            let others = base.items(on: side).filter { $0 != item }
            let fit = HeaderEar.fit(model: model, side: side, room: split.earWidth, size: size, layout: base, items: others)
            frames[side] = HeaderDrop.frames(fit, side: side, split: split, size: size) { HeaderEar.pickerWidth(pages: $0, size: size) }.items
            drawn[side] = fit.shown
        }
        let target = HeaderDrop.target(x: x, split: split, frames: frames)
        // An index among the items drawn is one among all the side's items: before the drawn item
        // there, or at the end.
        let others = base.items(on: target.side).filter { $0 != item }
        let shown = drawn[target.side] ?? []
        let index = target.index < shown.count ? (others.firstIndex(of: shown[target.index]) ?? others.count)
                                               : (target.side == .leading ? (shown.last.flatMap(others.firstIndex).map { $0 + 1 } ?? 0) : others.count)
        return (target.side, index)
    }

    private func finish() {
        guard let current = drag else { return }
        withAnimation(Self.settle) {
            model.preferences.header = current.layout
            drag = nil
        }
        if current.removes { model.studio.headerSelection = nil }
    }

    // MARK: Keyboard

    /// ← and →: the picked item one place along the bar, across the notch at a side's end.
    private func step(_ direction: Int) -> Bool {
        guard let item = model.studio.headerSelection, let side = model.preferences.header.side(of: item) else { return false }
        var layout = model.preferences.header
        let items = layout.items(on: side)
        guard let index = items.firstIndex(of: item) else { return false }
        let next = index + direction
        if next >= 0, next < items.count {
            layout.place(item, on: side, at: next)
        } else if side == .leading, direction > 0 {
            layout.place(item, on: .trailing, at: 0)
        } else if side == .trailing, direction < 0 {
            layout.place(item, on: .leading, at: layout.leading.count)
        } else {
            NSSound.beep()
            return true
        }
        withAnimation(Self.settle) { model.preferences.header = layout }
        return true
    }

    private func removeSelected() {
        guard let item = model.studio.headerSelection else { return }
        var layout = model.preferences.header
        guard layout.remove(item) else {
            NSSound.beep()
            return
        }
        withAnimation(Self.settle) { model.preferences.header = layout }
        model.studio.headerSelection = nil
    }
}
