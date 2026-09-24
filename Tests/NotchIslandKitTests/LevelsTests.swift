import CoreGraphics
import Testing
@testable import NotchIslandKit

// Pure logic only: nothing here installs an event tap, starts a service, or touches the system
// volume or brightness.

@Suite struct LevelStepperTests {
    @Test func stepsAlongTheSixteenthGrid() {
        #expect(LevelStepper.stepped(0.5, up: true, fine: false) == 0.5625)
        #expect(LevelStepper.stepped(0.5, up: false, fine: false) == 0.4375)
    }

    @Test func fineStepIsASixtyFourth() {
        #expect(LevelStepper.stepped(0.5, up: true, fine: true) == 0.515625)
        #expect(LevelStepper.stepped(0.5, up: false, fine: true) == 0.484375)
    }

    @Test func offGridValuesSnapToTheNeighbouringLine() {
        #expect(LevelStepper.stepped(0.51, up: true, fine: false) == 0.5625)
        #expect(LevelStepper.stepped(0.51, up: false, fine: false) == 0.5)
        #expect(LevelStepper.stepped(0.55, up: false, fine: false) == 0.5)
    }

    @Test func roundTripNoiseStillMovesAWholeStep() {
        // 5/16 read back through Float32 / a dB table.
        #expect(LevelStepper.stepped(0.312_499_9, up: true, fine: false) == 0.375)
        #expect(LevelStepper.stepped(0.312_499_9, up: false, fine: false) == 0.25)
        #expect(LevelStepper.stepped(0.312_500_1, up: false, fine: false) == 0.25)
        #expect(LevelStepper.stepped(Double(Float(0.3125)), up: true, fine: false) == 0.375)
    }

    @Test func clampsAtTheLimits() {
        #expect(LevelStepper.stepped(1, up: true, fine: false) == 1)
        #expect(LevelStepper.stepped(0.99, up: true, fine: false) == 1)
        #expect(LevelStepper.stepped(0, up: false, fine: false) == 0)
        #expect(LevelStepper.stepped(0.01, up: false, fine: true) == 0)
        #expect(LevelStepper.stepped(1.7, up: false, fine: false) == 0.9375)
        #expect(LevelStepper.stepped(-3, up: true, fine: false) == 0.0625)
    }

    @Test func nanIsTreatedAsSilence() {
        #expect(LevelStepper.stepped(.nan, up: true, fine: false) == 0.0625)
        #expect(LevelStepper.stepped(.nan, up: false, fine: false) == 0)
        #expect(LevelStepper.clamped(.nan) == 0)
    }

    @Test(arguments: [false, true])
    func sixteenOrSixtyFourPressesSpanTheRange(fine: Bool) {
        let presses = fine ? 64 : 16
        var value = 0.0
        for _ in 0..<presses { value = LevelStepper.stepped(value, up: true, fine: fine) }
        #expect(value == 1)
        for _ in 0..<presses { value = LevelStepper.stepped(value, up: false, fine: fine) }
        #expect(value == 0)
    }
}

@Suite struct MediaKeyDecoderTests {
    private func data1(code: Int, state: Int, isRepeat: Bool = false) -> Int {
        code << 16 | state << 8 | (isRepeat ? 1 : 0)
    }

    @Test(arguments: MediaKey.allCases)
    func decodesEveryHandledKey(key: MediaKey) {
        let event = MediaKeyDecoder.decode(subtype: 8, data1: data1(code: key.rawValue, state: 0x0A), flags: [])
        #expect(event == MediaKeyEvent(key: key, isDown: true, isRepeat: false, isFine: false))
    }

    @Test func keyUpAndRepeat() {
        let up = MediaKeyDecoder.decode(subtype: 8, data1: data1(code: 3, state: 0x0B), flags: [])
        #expect(up == MediaKeyEvent(key: .brightnessDown, isDown: false, isRepeat: false, isFine: false))

        let held = MediaKeyDecoder.decode(subtype: 8, data1: data1(code: 7, state: 0x0A, isRepeat: true), flags: [])
        #expect(held == MediaKeyEvent(key: .mute, isDown: true, isRepeat: true, isFine: false))
    }

    @Test func fineNeedsBothShiftAndOption() {
        let both = MediaKeyDecoder.decode(subtype: 8, data1: data1(code: 0, state: 0x0A), flags: [.maskShift, .maskAlternate])
        #expect(both?.isFine == true)
        let shiftOnly = MediaKeyDecoder.decode(subtype: 8, data1: data1(code: 0, state: 0x0A), flags: [.maskShift])
        #expect(shiftOnly?.isFine == false)
        let optionOnly = MediaKeyDecoder.decode(subtype: 8, data1: data1(code: 1, state: 0x0A), flags: [.maskAlternate])
        #expect(optionOnly?.isFine == false)
    }

    @Test func ignoresEverythingElse() {
        // Other system-defined subtypes.
        #expect(MediaKeyDecoder.decode(subtype: 7, data1: data1(code: 0, state: 0x0A), flags: []) == nil)
        // Play (16), next (17), illumination up (21) are left to the system.
        for code in [16, 17, 21, 22, 23] {
            #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(code: code, state: 0x0A), flags: []) == nil)
        }
        // Unknown key state.
        #expect(MediaKeyDecoder.decode(subtype: 8, data1: data1(code: 0, state: 0x05), flags: []) == nil)
    }
}

@Suite struct MediaKeyPolicyTests {
    private func event(_ key: MediaKey, down: Bool = true, repeat isRepeat: Bool = false) -> MediaKeyEvent {
        MediaKeyEvent(key: key, isDown: down, isRepeat: isRepeat, isFine: false)
    }

    @Test(arguments: MediaKey.allCases)
    func passThroughPolicyTakesNothing(key: MediaKey) {
        #expect(MediaKeyPolicy.passThrough.action(for: event(key)) == .passThrough)
        #expect(MediaKeyPolicy.passThrough.action(for: event(key, down: false)) == .passThrough)
    }

    @Test func volumeWithoutSettableMuteLeavesTheMuteKeyToTheSystem() {
        let policy = MediaKeyPolicy(volume: true, mute: false, brightness: false)
        #expect(policy.action(for: event(.volumeUp)) == .handle)
        #expect(policy.action(for: event(.volumeDown, repeat: true)) == .handle)
        #expect(policy.action(for: event(.volumeUp, down: false)) == .swallow)
        #expect(policy.action(for: event(.mute)) == .passThrough)
        #expect(policy.action(for: event(.brightnessUp)) == .passThrough)
    }

    @Test func heldMuteDoesNotToggleRepeatedly() {
        let policy = MediaKeyPolicy(volume: true, mute: true, brightness: false)
        #expect(policy.action(for: event(.mute)) == .handle)
        #expect(policy.action(for: event(.mute, repeat: true)) == .swallow)
        #expect(policy.action(for: event(.mute, down: false)) == .swallow)
    }

    @Test func brightnessOnly() {
        let policy = MediaKeyPolicy(volume: false, mute: false, brightness: true)
        #expect(policy.action(for: event(.brightnessUp)) == .handle)
        #expect(policy.action(for: event(.brightnessDown, repeat: true)) == .handle)
        #expect(policy.action(for: event(.volumeUp)) == .passThrough)
        #expect(policy.action(for: event(.mute)) == .passThrough)
    }

    @Test func keysMapToTheirLevel() {
        #expect(MediaKey.mute.kind == .volume)
        #expect(MediaKey.volumeDown.kind == .volume)
        #expect(MediaKey.brightnessUp.kind == .brightness)
    }
}

@Suite struct LevelReadingTests {
    private func volume(_ value: Double, muted: Bool = false, available: Bool = true) -> LevelReading {
        LevelReading(value: value, isMuted: muted, isAvailable: available, kind: .volume)
    }

    private func brightness(_ value: Double) -> LevelReading {
        LevelReading(value: value, isMuted: false, isAvailable: true, kind: .brightness)
    }

    @Test func volumeSymbols() {
        #expect(volume(0.8, muted: true).systemImage == "speaker.slash.fill")
        #expect(volume(0).systemImage == "speaker.slash.fill")
        #expect(volume(0.5, available: false).systemImage == "speaker.slash.fill")
        #expect(volume(0.1).systemImage == "speaker.wave.1.fill")
        #expect(volume(1.0 / 3.0).systemImage == "speaker.wave.2.fill")
        #expect(volume(0.5).systemImage == "speaker.wave.2.fill")
        #expect(volume(2.0 / 3.0).systemImage == "speaker.wave.3.fill")
        #expect(volume(1).systemImage == "speaker.wave.3.fill")
    }

    @Test func brightnessSymbols() {
        #expect(brightness(0).systemImage == "sun.min.fill")
        #expect(brightness(0.49).systemImage == "sun.min.fill")
        #expect(brightness(0.5).systemImage == "sun.max.fill")
        #expect(brightness(1).systemImage == "sun.max.fill")
        #expect(LevelReading.unavailable(.brightness).kind == .brightness)
    }

    @Test func contractInitialiserMeansVolume() {
        let reading = LevelReading(value: 0.9, isMuted: false, isAvailable: true)
        #expect(reading.kind == .volume)
        #expect(reading.systemImage == "speaker.wave.3.fill")
        #expect(LevelReading.unavailable.isAvailable == false)
    }

    @Test func volumeSnapshotMapping() {
        let snapshot = VolumeSnapshot(value: 0.4, isMuted: true, canSetVolume: true, canSetMute: false)
        #expect(snapshot.reading == LevelReading(value: 0.4, isMuted: true, isAvailable: true, kind: .volume))
        #expect(VolumeSnapshot.noDevice.reading.isAvailable == false)

        var nudged = snapshot
        nudged.value += 0.0005
        #expect(!nudged.differsAudibly(from: snapshot))
        nudged.value = 0.45
        #expect(nudged.differsAudibly(from: snapshot))
        var unmuted = snapshot
        unmuted.isMuted = false
        #expect(unmuted.differsAudibly(from: snapshot))
        #expect(unmuted.hasSameCapabilities(as: snapshot))
        unmuted.canSetMute = true
        #expect(!unmuted.hasSameCapabilities(as: snapshot))
    }
}

@Suite struct BrightnessChangeFilterTests {
    private let now = ContinuousClock.now

    @Test func ambientDriftIsSilentAndKeySizedJumpsAreReported() {
        #expect(BrightnessChangeFilter.verdict(for: 0.5004, previous: 0.5, ownWrite: nil, now: now) == .ignore)
        #expect(BrightnessChangeFilter.verdict(for: 0.51, previous: 0.5, ownWrite: nil, now: now) == .silent)
        #expect(BrightnessChangeFilter.verdict(for: 0.5625, previous: 0.5, ownWrite: nil, now: now) == .external)
        #expect(BrightnessChangeFilter.verdict(for: 0.4375, previous: 0.5, ownWrite: nil, now: now) == .external)
        let threshold = BrightnessChangeFilter.reportThreshold
        #expect(BrightnessChangeFilter.verdict(for: 0.5 + threshold * 1.01, previous: 0.5, ownWrite: nil, now: now) == .external)
        #expect(BrightnessChangeFilter.verdict(for: 0.5 + threshold * 0.9, previous: 0.5, ownWrite: nil, now: now) == .silent)
    }

    @Test func echoOfOurOwnWriteIsAdoptedQuietly() {
        let write = BrightnessChangeFilter.OwnWrite(value: 0.5625, at: now)
        let soon = now.advanced(by: .milliseconds(200))
        #expect(BrightnessChangeFilter.verdict(for: 0.5625, previous: 0.5, ownWrite: write, now: soon) == .silent)
        #expect(BrightnessChangeFilter.verdict(for: 0.5621, previous: 0.5, ownWrite: write, now: soon) == .silent)
        // A ramp frame / stale read while our write is fresh: superseded, not shown.
        #expect(BrightnessChangeFilter.verdict(for: 0.53, previous: 0.5, ownWrite: write, now: soon) == .ignore)
    }

    @Test func ownWriteExpiresSoNothingStaysStale() {
        // A write that produced no notification (at a limit) must not colour later changes.
        let write = BrightnessChangeFilter.OwnWrite(value: 1, at: now)
        let later = now.advanced(by: .seconds(2))
        #expect(!write.isFresh(at: later))
        #expect(BrightnessChangeFilter.verdict(for: 0.995, previous: 1, ownWrite: write, now: later) == .silent)
        #expect(BrightnessChangeFilter.verdict(for: 0.9375, previous: 1, ownWrite: write, now: later) == .external)
    }
}

@Suite struct LevelsControllerTests {
    @Test func startsIdleWithoutTouchingTheSystem() {
        let controller = LevelsController()
        #expect(controller.volume == .unavailable(.volume))
        #expect(controller.brightness == .unavailable(.brightness))
        #expect(controller.interception == .off)
        #expect(controller.reading(.brightness).kind == .brightness)
    }

    @Test func demoInjectionReportsAKeyChange() {
        let controller = LevelsController()
        var changes: [LevelChangeSource] = []
        var kinds: [LevelKind] = []
        controller.onChange = { kind, source in
            kinds.append(kind)
            changes.append(source)
        }
        controller.injectDemo(.volume, value: 0.6)
        controller.injectDemo(.brightness, value: 1.4)
        #expect(controller.volume.value == 0.6)
        #expect(controller.volume.isAvailable)
        #expect(controller.brightness.value == 1)
        #expect(controller.brightness.systemImage == "sun.max.fill")
        #expect(kinds == [.volume, .brightness])
        #expect(changes == [.key, .key])
    }

    @Test func theFirstReadingIsNeverAChange() {
        // After (re)start the first reading, by whichever path it arrives, is the baseline.
        var gate = FirstReadingGate()
        let first = gate.admit()
        let second = gate.admit()
        let third = gate.admit()
        #expect(!first && second && third)
        #expect(gate.hasBaseline)
        gate = FirstReadingGate()
        let afterRestart = gate.admit()
        #expect(!afterRestart)
    }

    @Test func endingADemoRestoresTheReadingsSilently() {
        let controller = LevelsController()
        var fired: [LevelChangeSource] = []
        controller.onChange = { _, source in fired.append(source) }
        controller.injectDemo(.volume, value: 0.6)
        controller.injectDemo(.brightness, value: 0.4)
        controller.endDemo()
        #expect(controller.volume == .unavailable(.volume))
        #expect(controller.brightness == .unavailable(.brightness))
        // Only the two injections spoke; the cleanup is silent (no banner out of a reset).
        #expect(fired == [.key, .key])
    }

    @Test func intentsAreInertUntilStarted() {
        let controller = LevelsController()
        var fired = false
        controller.onChange = { _, _ in fired = true }
        controller.set(.volume, to: 0.3)
        controller.toggleMute()
        // Not running: must not arm the tap (nor even query Accessibility trust).
        controller.setInterceptionEnabled(true)
        #expect(controller.interception == .off)
        #expect(controller.volume == .unavailable(.volume))
        #expect(!fired)
        controller.setInterceptionEnabled(false)
        controller.stop()
        #expect(controller.interception == .off)
    }
}
