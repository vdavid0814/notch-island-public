import CoreGraphics
import Foundation
import SwiftUI

/// One thing in the panel's top bar.
nonisolated enum HeaderItem: Hashable, Sendable, Identifiable, CaseIterable {
    /// The page picker.
    case pages
    /// The battery; opens the battery page. Only on a Mac with a battery.
    case battery
    case siri
    /// Keep the panel open.
    case pin
    case settings
    case clock
    /// The cover and play/pause of what is playing. Only while something is.
    case nowPlaying
    case toggle(HeaderToggle)
    /// Releases the window held under the notch. Only while one is.
    case anchorWindow
    case screenshot
    case lock

    static let allCases: [HeaderItem] = [.pages, .battery, .siri, .pin, .settings, .clock, .nowPlaying]
        + HeaderToggle.allCases.map(HeaderItem.toggle) + [.anchorWindow, .screenshot, .lock]

    var id: String { rawValue }

    /// In the bar exactly once: moved, never removed, and never in the "⋯" menu.
    var isRequired: Bool { self == .settings || self == .pages }

    var title: String {
        switch self {
        case .pages: String(localized: "Pages")
        case .battery: String(localized: "Battery")
        case .siri: String(localized: "Siri")
        case .pin: String(localized: "Keep Open")
        case .settings: String(localized: "Settings")
        case .clock: String(localized: "Clock")
        case .nowPlaying: String(localized: "Now Playing")
        case .toggle(let toggle): toggle.control.title
        case .anchorWindow: String(localized: "Release Window")
        case .screenshot: String(localized: "Screenshot")
        case .lock: String(localized: "Lock Screen")
        }
    }

    var systemImage: String {
        switch self {
        case .pages: "rectangle.split.3x1"
        case .battery: "battery.100percent"
        case .siri: "siri"
        case .pin: "pin"
        case .settings: "gearshape"
        case .clock: "clock"
        case .nowPlaying: "play.fill"
        case .toggle(let toggle): toggle.control.symbol(on: true)
        case .anchorWindow: "rectangle.topthird.inset.filled"
        case .screenshot: "camera.viewfinder"
        case .lock: "lock.fill"
        }
    }

    /// What it is there for, in the editor's palette.
    var summary: String {
        switch self {
        case .pages: String(localized: "Switch between the panel's pages.")
        case .battery: String(localized: "The charge; a click opens the battery page.")
        case .siri: String(localized: "Opens Siri in the notch.")
        case .pin: String(localized: "Keeps the panel open when the pointer leaves.")
        case .settings: String(localized: "Opens Settings.")
        case .clock: String(localized: "The time.")
        case .nowPlaying: String(localized: "The cover and play/pause, while something plays.")
        case .toggle(let toggle): toggle.summary
        case .anchorWindow: String(localized: "Lets go of the window held under the notch. Shown only while one is.")
        case .screenshot: String(localized: "Opens the Screenshot toolbar.")
        case .lock: String(localized: "Locks the Mac.")
        }
    }
}

nonisolated extension HeaderItem: RawRepresentable, Codable {
    init?(rawValue: String) {
        if rawValue.hasPrefix("toggle.") {
            guard let toggle = HeaderToggle(rawValue: String(rawValue.dropFirst(7))) else { return nil }
            self = .toggle(toggle)
            return
        }
        switch rawValue {
        case "pages": self = .pages
        case "battery": self = .battery
        case "siri": self = .siri
        case "pin": self = .pin
        case "settings": self = .settings
        case "clock": self = .clock
        case "nowPlaying": self = .nowPlaying
        case "anchorWindow": self = .anchorWindow
        case "screenshot": self = .screenshot
        case "lock": self = .lock
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .pages: "pages"
        case .battery: "battery"
        case .siri: "siri"
        case .pin: "pin"
        case .settings: "settings"
        case .clock: "clock"
        case .nowPlaying: "nowPlaying"
        case .toggle(let toggle): "toggle." + toggle.rawValue
        case .anchorWindow: "anchorWindow"
        case .screenshot: "screenshot"
        case .lock: "lock"
        }
    }
}

/// The switches the top bar can carry.
nonisolated enum HeaderToggle: String, Sendable, CaseIterable, Codable {
    case wifi, bluetooth, darkMode, focus

    var control: SystemControl {
        switch self {
        case .wifi: .wifi
        case .bluetooth: .bluetooth
        case .darkMode: .darkMode
        case .focus: .focus
        }
    }

    var summary: String {
        switch self {
        case .wifi: String(localized: "Switches Wi-Fi on and off.")
        case .bluetooth: String(localized: "Switches Bluetooth on and off. macOS asks for the Bluetooth permission once.")
        case .darkMode: String(localized: "Switches between the light and the dark appearance.")
        case .focus: String(localized: "Opens Focus.")
        }
    }
}

nonisolated enum HeaderSide: String, Sendable, Codable, CaseIterable {
    case leading, trailing

    var title: String { self == .leading ? String(localized: "Left of the Notch") : String(localized: "Right of the Notch") }
}

/// The panel's top bar as the user arranged it (Settings ▸ Widgets ▸ Top Bar): what stands left and
/// right of the notch, in order, and which pages the picker offers, in which order. Stored as one
/// JSON value (`ni2.header`).
///
/// Pages are stored as the hidden ones, so a page a later version adds shows by itself. A missing or
/// unreadable field takes its default, an item this version does not know is left out, and what
/// comes out is always a bar that works (`sanitize`): nothing twice, Settings and the page picker
/// exactly once.
nonisolated struct HeaderLayout: Sendable, Equatable, Codable {
    static let version = 1

    var leading: [HeaderItem]
    var trailing: [HeaderItem]
    var hiddenPages: Set<ExpandedPage>
    /// The picker's order; a page missing here follows in the panel's own order.
    var pageOrder: [ExpandedPage]
    /// The pages the user added, each a board of widgets, in the order they were added.
    var customPages: [CustomPage] = []

    /// The bar as it was before it could be arranged.
    static let standard = HeaderLayout(leading: [.pages], trailing: [.battery, .siri, .pin, .settings])

    init(leading: [HeaderItem], trailing: [HeaderItem], hiddenPages: Set<ExpandedPage> = [], pageOrder: [ExpandedPage] = ExpandedPage.allCases,
         customPages: [CustomPage] = []) {
        self.leading = leading
        self.trailing = trailing
        self.hiddenPages = hiddenPages
        self.pageOrder = pageOrder
        self.customPages = customPages
        sanitize()
    }

    private enum CodingKeys: String, CodingKey { case version, leading, trailing, hiddenPages, pageOrder, customPages }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Names, so one this version does not know drops out alone.
        func items(_ key: CodingKeys) -> [HeaderItem]? {
            c.lossy([String].self, key).map { $0.compactMap(HeaderItem.init(rawValue:)) }
        }
        func pages(_ key: CodingKeys) -> [ExpandedPage]? {
            c.lossy([String].self, key).map { $0.compactMap(ExpandedPage.init(rawValue:)) }
        }
        // Each page on its own: one unreadable drops out alone.
        let custom = (c.lossy([JSONValue].self, .customPages) ?? []).compactMap { value -> CustomPage? in
            guard let data = try? JSONEncoder().encode(value) else { return nil }
            return try? JSONDecoder().decode(CustomPage.self, from: data)
        }
        self.init(leading: items(.leading) ?? Self.standard.leading, trailing: items(.trailing) ?? Self.standard.trailing,
                  hiddenPages: Set(pages(.hiddenPages) ?? []), pageOrder: pages(.pageOrder) ?? ExpandedPage.allCases,
                  customPages: custom)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.version, forKey: .version)
        try c.encode(leading.map(\.rawValue), forKey: .leading)
        try c.encode(trailing.map(\.rawValue), forKey: .trailing)
        try c.encode(orderedPages.filter(hiddenPages.contains).map(\.rawValue), forKey: .hiddenPages)
        try c.encode(pageOrder.map(\.rawValue), forKey: .pageOrder)
        if !customPages.isEmpty { try c.encode(customPages, forKey: .customPages) }
    }

    // MARK: Reading

    func items(on side: HeaderSide) -> [HeaderItem] { side == .leading ? leading : trailing }

    func side(of item: HeaderItem) -> HeaderSide? {
        leading.contains(item) ? .leading : trailing.contains(item) ? .trailing : nil
    }

    func contains(_ item: HeaderItem) -> Bool { side(of: item) != nil }

    /// The items not in the bar, in the palette's order.
    var unused: [HeaderItem] { HeaderItem.allCases.filter { !contains($0) } }

    /// Every page in the picker's order: the island's own and the user's.
    var orderedPages: [ExpandedPage] {
        pageOrder + (ExpandedPage.allCases + customPages.map(\.page)).filter { !pageOrder.contains($0) }
    }

    /// A page the user added, by its page.
    func customPage(_ page: ExpandedPage) -> CustomPage? { customPages.first { $0.page == page } }

    /// Adds a page of the user's at the picker's end, shown; nil at the limit.
    mutating func addCustomPage(title: String, symbol: String = CustomPage.defaultSymbol) -> ExpandedPage? {
        guard customPages.count < CustomPage.limit else { return nil }
        let page = ExpandedPage.newCustom()
        customPages.append(CustomPage(page: page, title: title, symbol: symbol))
        pageOrder = orderedPages
        sanitize()
        return page
    }

    /// Renames a page of the user's or gives it another symbol.
    mutating func editCustomPage(_ page: ExpandedPage, title: String? = nil, symbol: String? = nil) {
        guard let index = customPages.firstIndex(where: { $0.page == page }) else { return }
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { customPages[index].title = trimmed }
        }
        if let symbol { customPages[index].symbol = symbol }
    }

    /// Takes a page of the user's away (its board is the caller's to delete).
    mutating func removeCustomPage(_ page: ExpandedPage) {
        customPages.removeAll { $0.page == page }
        sanitize()
    }

    /// A name for a new page: "Page 2", "Page 3"… one not taken.
    var nextCustomTitle: String {
        let taken = Set(customPages.map(\.title))
        return (2...).lazy.map { "Page \($0)" }.first { !taken.contains($0) } ?? "Page"
    }

    /// The pages the picker offers among the ones this Mac has now, in order; never none.
    func pages(among available: [ExpandedPage]) -> [ExpandedPage] {
        let shown = orderedPages.filter { available.contains($0) && !hiddenPages.contains($0) }
        return shown.isEmpty ? Array(available.prefix(1)) : shown
    }

    // MARK: Arranging

    /// Puts `item` on `side` at `index` (among the side's other items), from wherever it was.
    mutating func place(_ item: HeaderItem, on side: HeaderSide, at index: Int) {
        leading.removeAll { $0 == item }
        trailing.removeAll { $0 == item }
        if side == .leading {
            leading.insert(item, at: min(max(index, 0), leading.count))
        } else {
            trailing.insert(item, at: min(max(index, 0), trailing.count))
        }
        sanitize()
    }

    /// Takes `item` out of the bar; false for one that must stay (Settings, the pages).
    @discardableResult
    mutating func remove(_ item: HeaderItem) -> Bool {
        guard !item.isRequired, contains(item) else { return false }
        leading.removeAll { $0 == item }
        trailing.removeAll { $0 == item }
        return true
    }

    /// Shows or hides a page in the picker; false when it is the last one shown among `available`.
    @discardableResult
    mutating func setPage(_ page: ExpandedPage, hidden: Bool, among available: [ExpandedPage]) -> Bool {
        if hidden {
            guard pages(among: available).contains(where: { $0 != page }) else { return false }
            hiddenPages.insert(page)
        } else {
            hiddenPages.remove(page)
        }
        return true
    }

    mutating func movePage(_ page: ExpandedPage, to index: Int) {
        var order = orderedPages
        order.removeAll { $0 == page }
        order.insert(page, at: min(max(index, 0), order.count))
        pageOrder = order
    }

    /// Nothing twice (the first stays), Settings and the pages in the bar (put back where they
    /// stand by default), every page in the order once, and never every page hidden.
    mutating func sanitize() {
        var seen: Set<HeaderItem> = []
        leading = leading.filter { seen.insert($0).inserted }
        trailing = trailing.filter { seen.insert($0).inserted }
        if !seen.contains(.pages) { leading.insert(.pages, at: 0) }
        if !seen.contains(.settings) { trailing.append(.settings) }
        var seenPages: Set<ExpandedPage> = []
        customPages = customPages.filter { $0.page.isCustom && seenPages.insert($0.page).inserted }
        let known = Set(ExpandedPage.allCases + customPages.map(\.page))
        var pages: Set<ExpandedPage> = []
        pageOrder = pageOrder.filter { known.contains($0) && pages.insert($0).inserted }
        pageOrder += (ExpandedPage.allCases + customPages.map(\.page)).filter { !pages.contains($0) }
        hiddenPages = hiddenPages.intersection(known)
        if hiddenPages.isSuperset(of: ExpandedPage.allCases) { hiddenPages.remove(.home) }
    }
}

/// What of one side of the bar fits beside the notch, by arithmetic alone: each item's width is
/// known from the control size (the circles and the clock) or measured once (the system's page
/// picker), so the bar never lays out twice to find out.
///
/// The user's order is kept. What does not fit goes, from the notch outwards, into a "⋯" menu whose
/// circle has its own room; Settings and the pages never go there. A picker still too wide loses
/// its battery segment (the battery in the bar opens that page).
nonisolated struct HeaderFit: Sendable, Equatable {
    /// The items drawn, in the user's order ("⋯" is not among them).
    var shown: [HeaderItem]
    /// The items in the "⋯" menu, in the user's order.
    var overflow: [HeaderItem]
    /// The pages the picker shows (empty when the side has no picker, or a single page).
    var pages: [ExpandedPage]
    /// The width drawn, "⋯" included.
    var used: CGFloat
    /// The ear's width (what is drawn may pass it by `slack`).
    var room: CGFloat

    var hasOverflow: Bool { !overflow.isEmpty }

    /// Between two items.
    static let spacing: CGFloat = 6

    /// The bar may reach this far into the clearance beside the notch (half of it) before anything
    /// goes into the menu: the standard bar does, at the smallest island beside a wide notch.
    static let slack: CGFloat = 3

    /// The "⋯" button.
    static func menu(_ size: ControlSize) -> CGFloat { size == .mini ? 12.5 : 18.5 }

    /// A round button's width: the system's is as wide as its symbol and the control size's padding,
    /// so each has its own (measured on macOS 27, at the two sizes the band takes).
    static func circle(_ item: HeaderItem, _ size: ControlSize) -> CGFloat {
        let (mini, small): (CGFloat, CGFloat) = switch item {
        case .siri: (13, 19)
        case .pin: (12, 18.5)
        case .settings: (13.5, 19.5)
        case .toggle(.wifi): (14, 20.5)
        case .toggle(.bluetooth): (13.5, 19.5)
        case .toggle(.darkMode): (13, 19)
        case .toggle(.focus): (12.5, 19)
        case .anchorWindow: (14.5, 22)
        case .screenshot: (13, 20)
        case .lock: (10, 16.5)
        case .pages, .battery, .clock, .nowPlaying: (14.5, 22)
        }
        return size == .mini ? mini : small
    }

    /// "88:88" in the bar's type.
    static func clock(_ size: ControlSize) -> CGFloat { size == .mini ? 31 : 34 }

    /// The battery with its percentage, and the little room after it.
    static let battery: CGFloat = 22.5 + 4

    /// Now Playing's cover, a square.
    static func cover(_ size: ControlSize) -> CGFloat { size == .mini ? 14 : 20 }

    /// The cover and play/pause beside it.
    static func nowPlaying(_ size: ControlSize) -> CGFloat { cover(size) + 4 + (size == .mini ? 10 : 16) }

    /// The system's page picker with these pages, until it has been measured: what it measures on
    /// macOS 27 (47, 76.5 and 106 pt for two, three and four pages at mini; at small its segments
    /// are all as wide as the widest, 31 pt, or 34 pt with the battery's).
    static func pickerEstimate(pages: [ExpandedPage], size: ControlSize) -> CGFloat {
        let count = CGFloat(pages.count)
        if size == .mini { return max(29.5 * count - 12, 0) + (pages.contains(.battery) && pages.count < 4 ? 2 : 0) }
        return count * (pages.contains(.battery) ? 34 : 31)
    }

    static func width(of item: HeaderItem, size: ControlSize, picker: CGFloat) -> CGFloat {
        switch item {
        case .pages: picker
        case .battery: battery
        case .clock: clock(size)
        case .nowPlaying: nowPlaying(size)
        case .siri, .pin, .settings, .toggle, .anchorWindow, .screenshot, .lock: circle(item, size)
        }
    }

    /// - Parameters:
    ///   - items: the side's items that exist now (no battery on a desktop Mac…), in the user's order.
    ///   - pages: the pages the picker offers.
    ///   - pickerWidth: the picker's width with those pages (measured, or `pickerEstimate`).
    init(items: [HeaderItem], side: HeaderSide, room: CGFloat, size: ControlSize, pages: [ExpandedPage],
         pickerWidth: ([ExpandedPage]) -> CGFloat) {
        // One page needs no picker.
        var shown = items.filter { $0 != .pages || pages.count > 1 }
        var overflow: [HeaderItem] = []
        var pickerPages = shown.contains(.pages) ? pages : []

        func total() -> CGFloat {
            let widths = shown.map { Self.width(of: $0, size: size, picker: $0 == .pages ? pickerWidth(pickerPages) : 0) }
            let count = shown.count + (overflow.isEmpty ? 0 : 1)
            return widths.reduce(0, +) + (overflow.isEmpty ? 0 : Self.menu(size)) + CGFloat(max(count - 1, 0)) * Self.spacing
        }

        let room = room + Self.slack
        // Towards the notch: the leading side's last item, the trailing side's first.
        while total() > room {
            let candidates = shown.indices.filter { !shown[$0].isRequired }
            guard let index = side == .leading ? candidates.last : candidates.first else { break }
            let item = shown.remove(at: index)
            if side == .leading { overflow.insert(item, at: 0) } else { overflow.append(item) }
        }
        // The other pages have no other way in: their segments stay, whatever the room.
        if total() > room, pickerPages.count > 2, let battery = pickerPages.firstIndex(of: .battery) {
            pickerPages.remove(at: battery)
        }
        self.shown = shown
        self.overflow = overflow
        self.pages = pickerPages
        self.used = total()
        self.room = room - Self.slack
    }
}

/// Where an item dragged along the bar lands: the side of the notch the pointer is on (in the gap
/// under the notch, the nearer one), before the first item there whose middle is past the pointer.
nonisolated enum HeaderDrop {
    /// - Parameters:
    ///   - x: the pointer, in the island's width.
    ///   - frames: each side's items as drawn (the dragged one left out), in order.
    static func target(x: CGFloat, split: NotchSplit, frames: [HeaderSide: [ClosedRange<CGFloat>]]) -> (side: HeaderSide, index: Int) {
        let side: HeaderSide = x < split.islandWidth / 2 ? .leading : .trailing
        let ranges = frames[side] ?? []
        let index = ranges.firstIndex { x < ($0.lowerBound + $0.upperBound) / 2 } ?? ranges.count
        return (side, index)
    }

    /// Dragged this far under the band, an item leaves the bar.
    static let removeDistance: CGFloat = 26

    /// Where each of a side's items is drawn, in the island's width: the leading side from its
    /// ear's outer edge, the trailing side up to its ear's outer edge, "⋯" at the notch's end.
    static func frames(_ fit: HeaderFit, side: HeaderSide, split: NotchSplit, size: ControlSize,
                       pickerWidth: ([ExpandedPage]) -> CGFloat) -> (items: [ClosedRange<CGFloat>], menu: ClosedRange<CGFloat>?) {
        let widths = fit.shown.map { HeaderFit.width(of: $0, size: size, picker: $0 == .pages ? pickerWidth(fit.pages) : 0) }
        var x = side == .leading ? split.leadingEar.lowerBound : split.trailingEar.upperBound - fit.used
        var menu: ClosedRange<CGFloat>?
        if side == .trailing, fit.hasOverflow {
            menu = x...(x + HeaderFit.menu(size))
            x += HeaderFit.menu(size) + HeaderFit.spacing
        }
        var items: [ClosedRange<CGFloat>] = []
        for width in widths {
            items.append(x...(x + width))
            x += width + HeaderFit.spacing
        }
        if side == .leading, fit.hasOverflow { menu = x...(x + HeaderFit.menu(size)) }
        return (items, menu)
    }
}
