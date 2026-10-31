import Foundation
import Testing
@testable import NotchIslandKit

@MainActor @Suite struct SettingsHistoryTests {
    @Test func theInfoPageIsAPlaceOfItsOwn() {
        let history = SettingsHistory()
        let about = SettingsPlace(pane: .about)
        let info = SettingsPlace(pane: .about, info: .howItWorks)
        var here = info
        history.moved(from: SettingsPlace(pane: .general), to: about)
        history.moved(from: about, to: info)
        let apply: (SettingsPlace) -> Void = { here = $0 }
        #expect(history.step(.back, from: here, apply: apply) && here == about)
        #expect(history.step(.back, from: here, apply: apply) && here == SettingsPlace(pane: .general))
        #expect(history.step(.forward, from: here, apply: apply) && here == about)
        #expect(history.step(.forward, from: here, apply: apply) && here == info)
    }

    @Test func stepsBackAndForwardAsABrowser() {
        let history = SettingsHistory()
        var here = SettingsPlace(pane: .general)
        func go(_ place: SettingsPlace) { history.moved(from: here, to: place); here = place }
        let apply: (SettingsPlace) -> Void = { here = $0 }
        let widget = WidgetID(rawValue: UUID())
        go(SettingsPlace(pane: .widgets))
        go(SettingsPlace(pane: .widgets, customizing: widget))
        // Out of Customize, then to the page before.
        #expect(history.step(.back, from: here, apply: apply) && here == SettingsPlace(pane: .widgets))
        #expect(history.takeStep() == nil)
        #expect(history.step(.back, from: here, apply: apply) && here.pane == .general)
        #expect(history.takeStep() == .back)
        #expect(!history.step(.back, from: here, apply: apply))
        // Forward again, into Customize.
        #expect(history.step(.forward, from: here, apply: apply) && here == SettingsPlace(pane: .widgets))
        #expect(history.step(.forward, from: here, apply: apply) && here.customizing == widget)
        // Somewhere new drops what was ahead.
        #expect(history.step(.back, from: here, apply: apply))
        go(SettingsPlace(pane: .about))
        #expect(!history.step(.forward, from: here, apply: apply))
    }

    @Test func applyingAStepIsNotRecordedAgain() {
        let history = SettingsHistory()
        var here = SettingsPlace(pane: .general)
        history.moved(from: here, to: SettingsPlace(pane: .siri))
        here = SettingsPlace(pane: .siri)
        #expect(history.step(.back, from: here) { place in
            history.moved(from: here, to: place)
            here = place
        })
        #expect(history.back.isEmpty && history.forward == [SettingsPlace(pane: .siri)])
    }
}
