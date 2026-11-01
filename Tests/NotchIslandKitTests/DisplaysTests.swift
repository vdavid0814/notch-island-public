import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

// MARK: - The island's screen

@Suite struct IslandScreenTests {
    private static func screen(_ id: CGDirectDisplayID, builtIn: Bool, notch: Bool, key: String, name: String = "Monitor") -> ScreenCandidate {
        let frame = CGRect(x: CGFloat(id) * 3000, y: 0, width: 1512, height: 982)
        let metrics = NotchMetrics.derive(displayID: id, screenFrame: frame, safeAreaTop: notch ? 32 : 0,
                                          auxiliaryTopLeftWidth: notch ? 664 : nil, auxiliaryTopRightWidth: notch ? 664 : nil,
                                          menuBarThickness: 24, isBuiltin: builtIn)
        return ScreenCandidate(metrics: metrics, id: ScreenID(key: builtIn ? ScreenID.builtInKey : key, name: name))
    }

    private let macBook = screen(1, builtIn: true, notch: true, key: "")
    private let flatMacBook = screen(1, builtIn: true, notch: false, key: "")
    private let studio = screen(2, builtIn: false, notch: false, key: "1552-44-7", name: "Studio Display")
    private let msi = screen(3, builtIn: false, notch: false, key: "14627-1-0", name: "MAG 321CQ E18")

    @Test func automaticKeepsTheNotchElseTheMenuBarScreen() {
        // A monitor owning the menu bar does not take the island from the notch.
        #expect(IslandScreenPicker.pick([studio, macBook], choice: .automatic) == macBook)
        // No notch anywhere (a MacBook Air M1 with a monitor): the menu bar's screen.
        #expect(IslandScreenPicker.pick([flatMacBook, studio], choice: .automatic) == flatMacBook)
        #expect(IslandScreenPicker.pick([studio, flatMacBook], choice: .automatic) == studio)
        #expect(IslandScreenPicker.pick([], choice: .automatic) == nil)
    }

    @Test func aChosenMonitorIsUsedWhileConnected() {
        #expect(IslandScreenPicker.pick([macBook, studio, msi], choice: .external(msi.id)) == msi)
        // Another monitor than the one chosen: still a monitor.
        #expect(IslandScreenPicker.pick([macBook, studio], choice: .external(msi.id)) == studio)
        #expect(IslandScreenPicker.pick([macBook, studio], choice: .external(nil)) == studio)
        // No monitor: back to automatic, never hidden.
        #expect(IslandScreenPicker.pick([macBook], choice: .external(msi.id)) == macBook)
    }

    @Test func theMacBookChosenButClosedFallsBack() {
        #expect(IslandScreenPicker.pick([studio, macBook], choice: .builtIn) == macBook)
        // Clamshell: only the monitor is there.
        #expect(IslandScreenPicker.pick([studio], choice: .builtIn) == studio)
    }

    @Test func theBarOffersEveryScreen() {
        let all = IslandScreenPicker.choices(screens: [macBook, studio, msi], current: .automatic, hasBuiltIn: true,
                                             includesAutomatic: true)
        #expect(all == [.automatic, .builtIn, .external(studio.id), .external(msi.id)])
        // The notice leaves Automatic out.
        let notice = IslandScreenPicker.choices(screens: [macBook, msi], current: .automatic, hasBuiltIn: true,
                                                includesAutomatic: false)
        #expect(notice == [.builtIn, .external(msi.id)])
        // No monitor connected: a plain "Monitor" to choose ahead.
        let alone = IslandScreenPicker.choices(screens: [macBook], current: .automatic, hasBuiltIn: true, includesAutomatic: true)
        #expect(alone == [.automatic, .builtIn, .external(nil)])
        // A monitor chosen before and not connected stays offered, by its name.
        let saved = IslandScreenPicker.choices(screens: [macBook, studio], current: .external(msi.id), hasBuiltIn: true,
                                               includesAutomatic: true)
        #expect(saved == [.automatic, .builtIn, .external(studio.id), .external(msi.id)])
        // A Mac without its own screen offers no MacBook.
        let desktop = IslandScreenPicker.choices(screens: [studio], current: .automatic, hasBuiltIn: false, includesAutomatic: false)
        #expect(desktop == [.external(studio.id)])
        // In clamshell the MacBook is still offered on a laptop.
        let clamshell = IslandScreenPicker.choices(screens: [studio], current: .automatic, hasBuiltIn: true, includesAutomatic: false)
        #expect(clamshell == [.builtIn, .external(studio.id)])
    }

    @Test func anyMonitorIsShownAsTheConnectedOne() {
        let choices = IslandScreenPicker.choices(screens: [macBook, msi], current: .external(nil), hasBuiltIn: true,
                                                 includesAutomatic: true)
        #expect(IslandScreenPicker.selection(in: choices, current: .external(nil)) == .external(msi.id))
        #expect(IslandScreenPicker.selection(in: choices, current: .builtIn) == .builtIn)
    }

    @Test func onlyNewMonitorsAreNews() {
        let known: Set = [ScreenID.builtInKey, studio.id.key]
        #expect(IslandScreenPicker.connected([macBook, studio, msi], since: known) == [msi])
        // The MacBook opened again (out of clamshell) is no new monitor.
        #expect(IslandScreenPicker.connected([macBook, studio], since: [studio.id.key]).isEmpty)
    }

    @Test func longMonitorNamesAreCut() {
        #expect(ScreenID(key: "1", name: "LG UltraFine Display Ergo 32").shortName == "LG UltraFine Disp…")
        #expect(ScreenID(key: "1", name: "MAG 321CQ E18").shortName == "MAG 321CQ E18")
    }

    @Test func theChoiceIsStoredAndKept() {
        let defaults = UserDefaults(suiteName: "IslandScreen.\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.islandScreen == .automatic)
        #expect(preferences.displayNotice && preferences.displayNoticeDuration == 15)
        preferences.islandScreen = .external(ScreenID(key: "14627-1-0", name: "MAG 321CQ E18"))
        preferences.restLine.length = 100
        let again = Preferences(defaults: defaults)
        #expect(again.islandScreen == .external(ScreenID(key: "14627-1-0", name: "MAG 321CQ E18")))
        #expect(again.restLine.length == 100)
    }

    @Test func noticeTimeAndLineAreClamped() {
        let defaults = UserDefaults(suiteName: "DisplayNotice.\(UUID().uuidString)")!
        defaults.set(99.0, forKey: Preferences.Key.displayNoticeDuration)
        defaults.set(try! JSONEncoder().encode(RestLine(isShown: true, length: 900, thickness: 0, opacity: 2)), forKey: Preferences.Key.restLine)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.displayNoticeDuration == 30)
        #expect(preferences.restLine == RestLine(isShown: true, length: 160, thickness: 2, opacity: 0.9))
    }

    @Test func urlsChooseTheScreenAndShowTheNotice() {
        #expect(AppCommand.parse(URL(string: "notchisland://demo/displays")!) == .demo(.displays))
        #expect(AppCommand.parse(URL(string: "notchisland://demo/quiet?on=1")!) == .demo(.quiet(true)))
        #expect(AppCommand.parse(URL(string: "notchisland://display?on=macbook")!) == .islandScreen(.builtIn))
        #expect(AppCommand.parse(URL(string: "notchisland://display?on=monitor")!) == .islandScreen(.external(nil)))
        #expect(AppCommand.parse(URL(string: "notchisland://display?on=auto")!) == .islandScreen(.automatic))
    }

    @Test func theNoticeIsAsWideAsItsScreens() {
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard, screen: CGSize(width: 1512, height: 982))
        #expect(layout.size(for: .banner(.displays(2))).width == IslandLayout.bannerMinimumWidth)
        #expect(layout.size(for: .banner(.displays(4))).width == 656)
        #expect(layout.size(for: .banner(.displays(2))).height == 32 + IslandLayout.displayDetailHeight)
        // Its own controls: the pointer over it must not open the panel.
        #expect(BannerKind.displays(2).isInteractive && !BannerKind.displays(2).showsWhileHidden)
    }
}

// MARK: - MacBooks without a notch

@Suite struct FlatMacBookProfileTests {
    @Test func notchlessMacBooksAreRecognised() {
        // CGDisplayScreenSize on a MacBook Air M1 and a MacBook Neo, a little off as EDIDs are.
        #expect(DisplayProfile.matching(physicalSize: CGSize(width: 286, height: 179), isBuiltin: true) == .flat13)
        #expect(DisplayProfile.matching(physicalSize: CGSize(width: 279.5, height: 174.6), isBuiltin: true) == .neo13)
        // Not mistaken for the 13.6-inch Air with a notch.
        #expect(DisplayProfile.matching(physicalSize: DisplayProfile.air13.panelSize, isBuiltin: true) == .air13)
    }

    @Test func theIslandKeepsItsSizeOnTheirDenserPanels() {
        // MacBook Air M1 at its default 1440 × 900: 5.03 pt/mm against the reference's 4.41.
        let air = NotchMetrics.derive(displayID: 1, screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0,
                                      auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarThickness: 24,
                                      physicalSize: DisplayProfile.flat13.panelSize, isBuiltin: true)
        #expect(!air.isPhysical)
        #expect(abs(DisplayProfile.factor(for: air) - 1.140) < 0.005)
    }
}
