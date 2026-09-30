import Foundation
import SwiftUI
import Testing
@testable import NotchIslandKit

@Suite struct HeaderLayoutTests {
    @Test func theStandardBarIsTheOneFromBeforeItCouldBeArranged() {
        let bar = HeaderLayout.standard
        #expect(bar.leading == [.pages])
        #expect(bar.trailing == [.battery, .siri, .pin, .settings])
        #expect(bar.hiddenPages.isEmpty)
        #expect(bar.pages(among: ExpandedPage.allCases) == ExpandedPage.allCases)
    }

    @Test func everyItemHasANameOfItsOwnThatReadsBack() {
        let names = HeaderItem.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
        for item in HeaderItem.allCases {
            #expect(HeaderItem(rawValue: item.rawValue) == item)
            #expect(!item.title.isEmpty && !item.systemImage.isEmpty && !item.summary.isEmpty)
        }
        #expect(HeaderItem(rawValue: "toggle.teleport") == nil)
        #expect(HeaderItem(rawValue: "") == nil)
    }

    @Test func itSurvivesCodingAndKeepsItsOrder() throws {
        var bar = HeaderLayout(leading: [.clock, .pages, .toggle(.wifi)], trailing: [.settings, .nowPlaying, .lock],
                               hiddenPages: [.shelf], pageOrder: [.timer, .home, .battery, .shelf])
        bar.movePage(.battery, to: 0)
        let decoded = try JSONDecoder().decode(HeaderLayout.self, from: JSONEncoder().encode(bar))
        #expect(decoded == bar)
        #expect(decoded.orderedPages == [.battery, .timer, .home, .shelf])
    }

    /// An older or a newer version's value, or a hand-edited one, never breaks the bar.
    @Test func decodingIsLossy() throws {
        func decode(_ json: String) throws -> HeaderLayout {
            try JSONDecoder().decode(HeaderLayout.self, from: Data(json.utf8))
        }
        // Nothing stored: the standard bar.
        #expect(try decode("{}") == .standard)
        // Unknown items and pages drop out alone; duplicates keep their first place.
        let mixed = try decode(#"{"leading":["pages","hologram","clock","clock"],"trailing":["siri","clock","settings"],"hiddenPages":["shelf","moon"],"pageOrder":["timer","moon"]}"#)
        #expect(mixed.leading == [.pages, .clock])
        #expect(mixed.trailing == [.siri, .settings])
        #expect(mixed.hiddenPages == [.shelf])
        #expect(mixed.orderedPages == [.timer, .home, .shelf, .battery])
        // Fields of the wrong type take their defaults.
        let wrong = try decode(#"{"leading":7,"trailing":"x","hiddenPages":{},"pageOrder":null}"#)
        #expect(wrong == .standard)
        // Settings and the pages come back where they stand by default.
        let bare = try decode(#"{"leading":[],"trailing":["pin"]}"#)
        #expect(bare.leading == [.pages])
        #expect(bare.trailing == [.pin, .settings])
    }

    @Test func settingsAndThePagesAreMovedButNeverRemoved() {
        var bar = HeaderLayout.standard
        let removedSettings = bar.remove(.settings), removedPages = bar.remove(.pages)
        #expect(!removedSettings && !removedPages)
        #expect(bar == .standard)
        bar.place(.settings, on: .leading, at: 0)
        #expect(bar.leading == [.settings, .pages])
        #expect(bar.trailing == [.battery, .siri, .pin])
        let removed = bar.remove(.siri), removedAgain = bar.remove(.siri)
        #expect(removed && !removedAgain)
        #expect(bar.trailing == [.battery, .pin])
    }

    @Test func placingMovesAnItemAndNeverDuplicatesIt() {
        var bar = HeaderLayout.standard
        bar.place(.clock, on: .trailing, at: 0)
        #expect(bar.trailing == [.clock, .battery, .siri, .pin, .settings])
        bar.place(.clock, on: .leading, at: 99)
        #expect(bar.leading == [.pages, .clock])
        #expect(bar.trailing == [.battery, .siri, .pin, .settings])
        bar.place(.clock, on: .leading, at: -3)
        #expect(bar.leading == [.clock, .pages])
        #expect(bar.side(of: .clock) == .leading && bar.side(of: .lock) == nil)
        #expect(!bar.unused.contains(.clock) && bar.unused.contains(.lock))
        #expect(Set(bar.unused).union(bar.leading).union(bar.trailing) == Set(HeaderItem.allCases))
    }

    @Test func atLeastOnePageStaysInThePicker() {
        var bar = HeaderLayout.standard
        let available: [ExpandedPage] = [.home, .timer]
        let hidHome = bar.setPage(.home, hidden: true, among: available)
        #expect(hidHome)
        #expect(bar.pages(among: available) == [.timer])
        // The last one shown cannot be hidden.
        let hidTimer = bar.setPage(.timer, hidden: true, among: available)
        #expect(!hidTimer)
        #expect(bar.pages(among: available) == [.timer])
        let shownHome = bar.setPage(.home, hidden: false, among: available)
        #expect(shownHome)
        #expect(bar.pages(among: available) == [.home, .timer])
        // Every page hidden in a stored value: home comes back.
        let all = HeaderLayout(leading: [.pages], trailing: [.settings], hiddenPages: Set(ExpandedPage.allCases))
        #expect(!all.hiddenPages.contains(.home))
        // The only page shown is one this Mac lost (the shelf switched off): the first it has.
        let shelfOnly = HeaderLayout(leading: [.pages], trailing: [.settings], hiddenPages: [.home, .timer, .battery])
        #expect(shelfOnly.pages(among: [.home, .timer]) == [.home])
    }

    /// A page a later version adds is not among the hidden ones, so it shows by itself; the shelf's
    /// goes while the shelf is off.
    @Test func pagesFollowWhatTheMacHas() {
        let bar = HeaderLayout(leading: [.pages], trailing: [.settings], hiddenPages: [.timer], pageOrder: [.shelf, .home])
        #expect(bar.pages(among: ExpandedPage.allCases) == [.shelf, .home, .battery])
        #expect(bar.pages(among: [.home, .timer, .battery]) == [.home, .battery])
    }

    @Test func preferencesStoreTheBar() {
        let name = "notchisland.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.header == .standard)
        preferences.header.place(.clock, on: .leading, at: 1)
        #expect(Preferences(defaults: defaults).header.leading == [.pages, .clock])
    }
}

@Suite struct HeaderFitTests {
    /// The picker's width as measured on macOS 27.
    private func picker(_ size: ControlSize) -> ([ExpandedPage]) -> CGFloat {
        { HeaderFit.pickerEstimate(pages: $0, size: size) }
    }

    private func fit(_ items: [HeaderItem], _ side: HeaderSide, room: CGFloat, size: ControlSize = .mini,
                     pages: [ExpandedPage] = ExpandedPage.allCases) -> HeaderFit {
        HeaderFit(items: items, side: side, room: room, size: size, pages: pages, pickerWidth: picker(size))
    }

    private func width(_ items: [HeaderItem], size: ControlSize = .mini, menu: Bool = false) -> CGFloat {
        let count = items.count + (menu ? 1 : 0)
        return items.map { HeaderFit.width(of: $0, size: size, picker: 0) }.reduce(0, +) + (menu ? HeaderFit.menu(size) : 0)
            + CGFloat(max(count - 1, 0)) * HeaderFit.spacing
    }

    @Test func whatFitsIsShownInTheUsersOrder() {
        let items: [HeaderItem] = [.battery, .siri, .pin, .settings]
        let result = fit(items, .trailing, room: 200)
        #expect(result.shown == items && result.overflow.isEmpty && !result.hasOverflow)
        #expect(result.used == width(items))
        #expect(result.used <= result.room && result.room == 200)
    }

    /// The standard bar is whole beside the notch at every island size, on this Mac's notch
    /// (156 pt) and the wide one (185 pt), from the panel's own width up — as it was before it
    /// could be arranged: nothing of it goes into "⋯".
    @Test func theStandardBarNeverOverflows() {
        for notch in [CGSize(width: 156, height: 29), CGSize(width: 156, height: 32), CGSize(width: 185, height: 32)] {
            for factor in [1, PanelSettings.widthRange.upperBound] {
                for scale in IslandScale.allCases {
                    let layout = IslandLayout(notch: notch, scale: scale, panel: PanelLayout(widthFactor: factor))
                    let split = NotchSplit(layout: layout, presentation: .expanded(.home),
                                           outerInset: Metrics.Expanded.horizontalInset, clearance: Metrics.notchClearance)
                    let size = Metrics.Control.size(fittingBand: notch.height)
                    let trailing = fit(HeaderLayout.standard.trailing, .trailing, room: split.earWidth, size: size)
                    #expect(trailing.overflow.isEmpty, "\(scale) at \(factor), notch \(notch.width): \(trailing.used) in \(split.earWidth)")
                    // Never as far as the notch itself.
                    #expect(trailing.used <= split.earWidth + Metrics.notchClearance / 2)
                    let leading = fit(HeaderLayout.standard.leading, .leading, room: split.earWidth, size: size)
                    #expect(leading.shown == [.pages] && leading.overflow.isEmpty)
                    // The battery's segment only where all four fit.
                    let four = HeaderFit.pickerEstimate(pages: ExpandedPage.allCases, size: size)
                    #expect(leading.pages.count == (four <= split.earWidth + HeaderFit.slack ? 4 : 3))
                }
            }
        }
    }

    @Test func whatDoesNotFitGoesIntoTheMenuFromTheNotchOutwards() {
        let items: [HeaderItem] = [.clock, .toggle(.wifi), .siri, .pin, .settings]
        // Trailing: the notch is on the left, so the first items go. Room for "⋯" and the last three.
        let room = width([.siri, .pin, .settings], menu: true) - HeaderFit.slack
        let trailing = fit(items, .trailing, room: room)
        #expect(trailing.overflow == [.clock, .toggle(.wifi)])
        #expect(trailing.shown == [.siri, .pin, .settings])
        #expect(trailing.used == room + HeaderFit.slack)
        // A point less and the next one goes too.
        #expect(fit(items, .trailing, room: room - 1).overflow == [.clock, .toggle(.wifi), .siri])
        // Leading: the notch is on the right, so the last items go, and the menu keeps their order.
        let leadingRoom = width([.clock, .toggle(.wifi), .settings], menu: true)
        let leading = fit(items, .leading, room: leadingRoom)
        #expect(leading.overflow == [.siri, .pin])
        #expect(leading.shown == [.clock, .toggle(.wifi), .settings])
        #expect(leading.used == leadingRoom)
    }

    /// "⋯" reserves its own width: what is drawn, the menu's button included, is within the room
    /// (and its slack) wherever anything could still be taken out.
    @Test func theMenuHasRoomOfItsOwn() {
        let items: [HeaderItem] = [.siri, .pin, .lock, .settings]
        for room in stride(from: CGFloat(10), through: 120, by: 0.5) {
            for side in HeaderSide.allCases {
                let result = fit(items, side, room: room)
                #expect(result.used == width(result.shown, menu: result.hasOverflow))
                if result.shown != [.settings] { #expect(result.used <= room + HeaderFit.slack) }
                // Both keep the user's order, and together they are the items.
                #expect(result.shown == items.filter(result.shown.contains))
                #expect(result.overflow == items.filter(result.overflow.contains))
                #expect(Set(result.shown).union(result.overflow) == Set(items))
                #expect(result.shown.contains(.settings))
            }
        }
    }

    /// A panel made narrower than its own width (Size ▸ Width) at the smallest island: the bar's
    /// first item beside the notch goes into the menu, and what is drawn fits.
    @Test func aNarrowedPanelOverflowsIntoTheMenu() {
        let layout = IslandLayout(notch: CGSize(width: 156, height: 29), scale: .extraSmall,
                                  panel: PanelLayout(widthFactor: PanelSettings.widthRange.lowerBound))
        let split = NotchSplit(layout: layout, presentation: .expanded(.home),
                               outerInset: Metrics.Expanded.horizontalInset, clearance: Metrics.notchClearance)
        let full = width(HeaderLayout.standard.trailing)
        let trailing = fit(HeaderLayout.standard.trailing, .trailing, room: split.earWidth)
        if full > split.earWidth + HeaderFit.slack {
            #expect(trailing.overflow.first == .battery)
            #expect(trailing.shown.last == .settings)
        } else {
            #expect(trailing.overflow.isEmpty)
        }
        #expect(trailing.used <= split.earWidth + HeaderFit.slack)
    }

    @Test func settingsAndThePagesNeverOverflow() {
        let result = fit([.pages, .clock, .settings], .leading, room: 1)
        #expect(result.shown == [.pages, .settings])
        #expect(result.overflow == [.clock])
        // Too wide still: the battery's segment goes, the other pages stay.
        #expect(result.pages == [.home, .shelf, .timer])
        let noBattery = fit([.pages], .leading, room: 1, pages: [.home, .shelf, .timer])
        #expect(noBattery.pages == [.home, .shelf, .timer])
    }

    @Test func aSinglePageNeedsNoPicker() {
        let result = fit([.pages, .clock], .leading, room: 300, pages: [.home])
        #expect(result.shown == [.clock] && result.pages.isEmpty)
        #expect(result.used == HeaderFit.clock(.mini))
    }

    @Test func thePickersEstimateIsWhatItMeasures() {
        #expect(HeaderFit.pickerEstimate(pages: [.home, .shelf], size: .mini) == 47)
        #expect(HeaderFit.pickerEstimate(pages: [.home, .shelf, .timer], size: .mini) == 76.5)
        #expect(HeaderFit.pickerEstimate(pages: ExpandedPage.allCases, size: .mini) == 106)
        #expect(HeaderFit.pickerEstimate(pages: [.home, .shelf], size: .small) == 62)
        #expect(HeaderFit.pickerEstimate(pages: [.home, .shelf, .timer], size: .small) == 93)
        #expect(HeaderFit.pickerEstimate(pages: ExpandedPage.allCases, size: .small) == 136)
    }

    @Test func everyItemHasAWidthAtBothSizes() {
        for item in HeaderItem.allCases {
            let mini = HeaderFit.width(of: item, size: .mini, picker: 100)
            let small = HeaderFit.width(of: item, size: .small, picker: 100)
            #expect(mini > 0 && small >= mini)
        }
        #expect(HeaderFit.menu(.small) > HeaderFit.menu(.mini))
    }
}
