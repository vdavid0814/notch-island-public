import Foundation
import Testing
@testable import NotchIslandKit

// Nothing here resets a permission or installs an event tap.

@Suite struct KeyTapHoldTests {
    private func state(held: Bool) -> FeatureState {
        FeatureState(showNowPlaying: false, showLevelHUD: true, replaceSystemHUD: true, accessibilityTrusted: true,
                     keyTapsHeld: held, shelfEnabled: false, suspended: false, commandSpaceOpensSiri: true, anchorEnabled: true)
    }

    @Test func aResetTakesBothKeyTapsDownAndOnlyThem() {
        let held = state(held: true)
        #expect(!held.commandSpace)
        #expect(!held.interception)
        // Not a missing permission: nothing asks for it meanwhile, and the anchor stays.
        #expect(!held.needsAccessibility)
        #expect(held.anchor)
        let free = state(held: false)
        #expect(free.commandSpace)
        #expect(free.interception)
    }

    @Test func lettingGoArmsTheTapsAgain() {
        let actions = FeatureState.actions(from: state(held: true), to: state(held: false))
        #expect(actions.contains(.setCommandSpace(true)))
        #expect(actions.contains(.setInterception(true)))
    }

    @Test func aTapSwitchedOffByUserInputAlwaysComesBack() {
        #expect(CommandSpaceTap.mayReenable(after: .tapDisabledByUserInput))
    }
}

@Suite struct SourceDeadlineTests {
    @Test func anAnswerInTimeIsKept() async {
        let value = await SourceDeadline.value("test-fast", within: .seconds(2), fallback: 0) { 42 }
        #expect(value == 42)
    }

    @Test func aSourceThatHangsIsLeftOutAndNotAskedAgainUntilItAnswers() async {
        let release = DispatchSemaphore(value: 0)
        let calls = Counter()
        let first = await SourceDeadline.value("test-hang", within: .milliseconds(100), fallback: -1) {
            calls.add()
            release.wait()
            return 1
        }
        // The call is still blocked: the answer is the fallback, given at the deadline.
        #expect(first == -1)
        // Overdue: the next read does not start another call behind it.
        let second = await SourceDeadline.value("test-hang", within: .milliseconds(100), fallback: -2) {
            calls.add()
            return 2
        }
        #expect(second == -2)
        #expect(calls.value == 1)
        // Once it answers, it is asked again.
        release.signal()
        try? await Task.sleep(for: .milliseconds(100))
        let third = await SourceDeadline.value("test-hang", within: .seconds(2), fallback: -3) { 3 }
        #expect(third == 3)
    }
}

nonisolated private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
