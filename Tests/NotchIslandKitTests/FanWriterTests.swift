import Foundation
import Testing
@testable import NotchIslandKit

/// A Mac's fan keys for the writer's tests: an M5's (the mode taken as it is, no "Ftst") or an
/// M4's (the mode refused until "Ftst" has been 1 for four seconds), with the ways a real SMC
/// misbehaves switched on one at a time. Time passes only as the writer waits.
nonisolated final class FakeFanKeys: FanKeys, @unchecked Sendable {
    enum Chip { case m5, m4 }

    let chip: Chip
    var values: [String: SMC.Value] = [:]
    var clock: TimeInterval = 0
    /// When "Ftst" was set to 1.
    var unlockedAt: TimeInterval?
    /// Every write asked for, in order.
    var writes: [(key: String, bytes: [UInt8])] = []
    /// Says it took a write and does not.
    var dropsWrites = false
    /// Refuses the mode whatever is done.
    var refusesMode = false
    /// Answers 0x87 to a target it took all the same.
    var miscountsTargets = false
    /// Will not hold a fan slower than its slowest: a lower target is not taken.
    var keepsFansTurning = false

    var mode: String { chip == .m5 ? "md" : "Md" }

    init(_ chip: Chip, fans: Int = 2) {
        self.chip = chip
        for index in 0..<fans {
            values["F\(index)Ac"] = Self.float(2300)
            values["F\(index)Mn"] = Self.float(1200)
            values["F\(index)Mx"] = Self.float(5800)
            values["F\(index)Tg"] = Self.float(1200)
            values["F\(index)\(mode)"] = SMC.Value(type: "ui8 ", bytes: [chip == .m5 ? 0 : 3])
        }
        if chip == .m4 { values["Ftst"] = SMC.Value(type: "ui8 ", bytes: [0]) }
    }

    static func float(_ number: Double) -> SMC.Value { SMC.Value(type: "flt ", bytes: SMC.encode(number, type: "flt ")!) }

    func read(_ key: String) -> SMC.Value? { values[key] }

    func number(_ key: String) -> Double? {
        // The thermal daemon lets go a few seconds after "Ftst": its mode (3) reads 0 then.
        if chip == .m4, key.hasSuffix("Md"), values[key]?.bytes == [3], let unlockedAt, clock - unlockedAt >= 3.5 { return 0 }
        return values[key].flatMap(SMC.decode)
    }

    func write(_ key: String, bytes: [UInt8]) -> Bool { result(ofWriting: key, bytes: bytes) == SMC.success }

    func result(ofWriting key: String, bytes: [UInt8]) -> UInt8? {
        writes.append((key, bytes))
        guard let value = values[key] else { return 0x84 }
        if key.hasSuffix(mode), bytes == [1] {
            if refusesMode { return 0x82 }
            if chip == .m4 {
                guard let unlockedAt, clock - unlockedAt >= 4 else { return 0x82 }
            }
        }
        if dropsWrites { return SMC.success }
        if keepsFansTurning, key.hasSuffix("Tg"), let target = SMC.decode(SMC.Value(type: value.type, bytes: bytes)), target < 1200 {
            return 0x87
        }
        values[key] = SMC.Value(type: value.type, bytes: bytes)
        if key == "Ftst" { unlockedAt = bytes == [1] ? clock : nil }
        return key.hasSuffix("Tg") && miscountsTargets ? 0x87 : SMC.success
    }

    /// macOS takes the fans back, as over sleep: the modes its own again, "Ftst" cleared.
    func reclaim() {
        for key in values.keys where key.hasSuffix(mode) { values[key] = SMC.Value(type: "ui8 ", bytes: [chip == .m5 ? 0 : 3]) }
        for key in values.keys where key.hasSuffix("Tg") { values[key] = Self.float(1200) }
        if chip == .m4 { values["Ftst"] = SMC.Value(type: "ui8 ", bytes: [0]) }
        unlockedAt = nil
    }

    func writer(fans: Int = 2) -> FanWriter {
        FanWriter(smc: self, count: fans, modeKey: { "F\($0)\(self.mode)" }, pause: { self.clock += $0 })
    }
}

/// The fan helper's writes: a fan held is read back as held, one macOS took back is held again, one
/// that will not hold is given back — on an M5 and on the chips that want "Ftst" first.
struct FanWriterTests {
    @Test func anM5HoldsItsFansAsAsked() {
        let keys = FakeFanKeys(.m5)
        let writer = keys.writer()
        #expect(writer.set([2000, 9000]) == nil)
        #expect(writer.isHolding && writer.held == [2000, 5800])
        #expect(keys.number("F0md") == 1 && keys.number("F1md") == 1)
        #expect(keys.number("F0Tg") == 2000 && keys.number("F1Tg") == 5800)
        // Down to nothing: a fan held by hand may be stopped, or turned slower than macOS turns it.
        #expect(writer.set([0, 600]) == nil)
        #expect(keys.number("F0Tg") == 0 && keys.number("F1Tg") == 600 && writer.held == [0, 600])
        #expect(writer.set([-50, 0]) == nil)
        #expect(writer.held == [0, 0])
        #expect(writer.setAutomatic() == nil)
        #expect(!writer.isHolding && keys.number("F0md") == 0 && keys.number("F1md") == 0)
    }

    /// A Mac that will not hold a fan under its slowest: held there, said once, and not tried again
    /// at every step of a turn of the dial.
    @Test func aFanThatCannotBeStoppedIsHeldAtItsSlowest() {
        let keys = FakeFanKeys(.m5)
        keys.keepsFansTurning = true
        let writer = keys.writer()
        #expect(writer.set([0, 3000]) == nil)
        #expect(writer.held == [1200, 3000] && keys.number("F0Tg") == 1200 && keys.number("F0md") == 1)
        keys.writes = []
        #expect(writer.set([400, 3000]) == nil)
        #expect(writer.held == [1200, 3000])
        #expect(!keys.writes.contains { $0.key == "F0Tg" && $0.bytes != SMC.encode(1200, type: "flt ")! })
        // Still held as asked: nothing to hold again.
        keys.writes = []
        writer.maintain()
        #expect(keys.writes.isEmpty)
    }

    /// The chip at its limit, look after look, gives held fans back; they stay with macOS until it
    /// has cooled. A core at 95–100 °C, as under any heavy load, never does.
    @Test func onlyAChipAtItsLimitTakesTheFansBack() {
        var guardian = HeatGuard()
        /// Looks at the chip `times` over; how many of them said to give the fans back.
        func looks(_ times: Int, at hottest: Double, holding: Bool = true) -> Int {
            (0..<times).count { _ in guardian.check(hottest: hottest, holding: holding) }
        }
        #expect(looks(20, at: 101) == 0)
        #expect(looks(2, at: 106) == 0)
        // Cooler between: counted from the start again.
        #expect(looks(1, at: 99) == 0 && looks(2, at: 106) == 0)
        #expect(looks(1, at: 105) == 1 && guardian.isTripped)
        // Tripped: nothing more to give back, and not over until it is under 95 °C.
        #expect(looks(3, at: 108, holding: false) == 0 && guardian.isTripped)
        #expect(looks(1, at: 96, holding: false) == 0 && guardian.isTripped)
        #expect(looks(1, at: 94, holding: false) == 0 && !guardian.isTripped)
        // Nothing held: a hot chip is macOS's business.
        #expect(looks(5, at: 109, holding: false) == 0 && !guardian.isTripped)
    }

    @Test func givingBackNeverWritesATarget() {
        let keys = FakeFanKeys(.m5)
        let writer = keys.writer()
        _ = writer.set([3000, 3000])
        keys.writes = []
        _ = writer.setAutomatic()
        #expect(!keys.writes.contains { $0.key.hasSuffix("Tg") })
    }

    @Test func anM4IsAskedToLetGoFirst() {
        let keys = FakeFanKeys(.m4)
        let writer = keys.writer()
        #expect(writer.set([3000, 3100]) == nil)
        #expect(keys.clock >= 4 && keys.clock < 15)
        #expect(keys.number("Ftst") == 1 && keys.number("F0Md") == 1 && keys.number("F1Tg") == 3100)
        #expect(writer.setAutomatic() == nil)
        #expect(keys.number("Ftst") == 0 && keys.number("F0Md") != 1 && !writer.isHolding)
    }

    @Test(arguments: [FakeFanKeys.Chip.m5, .m4]) func fansTakenBackAreHeldAgain(_ chip: FakeFanKeys.Chip) {
        let keys = FakeFanKeys(chip)
        let writer = keys.writer()
        #expect(writer.set([2500, 2600]) == nil)
        writer.maintain()
        keys.reclaim()
        writer.maintain()
        #expect(keys.number("F0\(keys.mode)") == 1 && keys.number("F0Tg") == 2500 && keys.number("F1Tg") == 2600)
        #expect(writer.held == [2500, 2600])
    }

    @Test func fansThatWillNotHoldAreGivenBack() {
        let keys = FakeFanKeys(.m5)
        let writer = keys.writer()
        #expect(writer.set([2500, 2500]) == nil)
        keys.reclaim()
        keys.refusesMode = true
        for _ in 0..<4 { writer.maintain() }
        #expect(writer.isHolding)
        writer.maintain()
        #expect(!writer.isHolding && writer.held.isEmpty)
        // Nothing is held: nothing more is written.
        keys.writes = []
        writer.maintain()
        #expect(keys.writes.isEmpty)
    }

    @Test func aRefusalIsToldAndLeavesNothingHeld() {
        let keys = FakeFanKeys(.m5)
        keys.refusesMode = true
        let writer = keys.writer()
        #expect(writer.set([2500, 2500])?.contains("0x82") == true)
        #expect(!writer.isHolding)
    }

    @Test func aWriteTheSMCOnlySaysItTookIsAFailure() {
        let keys = FakeFanKeys(.m5)
        keys.dropsWrites = true
        let writer = keys.writer()
        #expect(writer.set([2500, 2500]) != nil)
        #expect(!writer.isHolding)
    }

    @Test func aTargetTakenWithAnErrorCounts() {
        let keys = FakeFanKeys(.m5)
        keys.miscountsTargets = true
        let writer = keys.writer()
        #expect(writer.set([2500, 2500]) == nil)
        #expect(keys.number("F1Tg") == 2500)
    }

    @Test func oneFanAndNoFan() {
        let one = FakeFanKeys(.m5, fans: 1)
        #expect(one.writer(fans: 1).set([2000]) == nil)
        #expect(FakeFanKeys(.m5, fans: 0).writer(fans: 0).set([2000]) != nil)
    }
}

/// The helper installed with a password: what root is given to run, and its launchd job.
struct FanInstallerTests {
    @Test func pathsWithQuotesAndSpacesAreSafeForTheShell() {
        #expect(FanInstaller.quoted("/Applications/notch app/It's.app") == "'/Applications/notch app/It'\\''s.app'")
        #expect(FanInstaller.scriptString("say \"hi\" \\ there") == "\"say \\\"hi\\\" \\\\ there\"")
    }

    @Test func theInstallPutsACopyOwnedByRootAndStartsItsJob() {
        let script = FanInstaller.installScript(executable: "/Applications/My Apps/NotchIsland.app/Contents/MacOS/NotchIsland",
                                                jobSource: "/tmp/job.plist")
        #expect(script.contains("/bin/cp -X '/Applications/My Apps/NotchIsland.app/Contents/MacOS/NotchIsland' '\(FanInstaller.tool).new'"))
        #expect(script.contains("/usr/sbin/chown root:wheel '\(FanInstaller.tool).new'"))
        #expect(script.contains("/bin/launchctl bootstrap system '\(FanInstaller.job)'"))
        // The last line decides: the job is there, or the install failed.
        #expect(script.hasSuffix("/bin/launchctl print system/com.davidvarga.notchisland.fanhelper >/dev/null"))
    }

    @Test func theJobStartsTheCopyAsTheHelperOnDemand() throws {
        let job = try #require(try PropertyListSerialization.propertyList(from: FanInstaller.jobData(), format: nil) as? [String: Any])
        #expect(job["Label"] as? String == "com.davidvarga.notchisland.fanhelper")
        #expect(job["ProgramArguments"] as? [String] == [FanInstaller.tool, "--fan-helper", "--installed"])
        #expect((job["MachServices"] as? [String: Bool])?["com.davidvarga.notchisland.fanhelper"] == true)
        #expect(job["RunAtLoad"] == nil && job["KeepAlive"] == nil)
    }

    @Test func theCommandThatRemovesIt() {
        #expect(AppCommand.parse(URL(string: "notchisland://fans/remove-helper")!) == .removeFanHelper)
    }
}

/// About ▸ Permissions ▸ Fan Control: what the row says of each state of the helper.
@MainActor struct FanHelperRowTests {
    @Test func theRowSaysWhetherTheHelperWorks() {
        #expect(FanHelperRow.title(.notSetUp, answers: nil) == "Set up when first used")
        #expect(FanHelperRow.title(.needsApproval, answers: nil) == "Switched off")
        #expect(FanHelperRow.title(.ready(installed: false), answers: nil) == "On")
        #expect(FanHelperRow.title(.ready(installed: false), answers: true) == "Working")
        #expect(FanHelperRow.title(.ready(installed: true), answers: false) == "On, not working")
        #expect(FanHelperRow.title(.failed("no"), answers: nil) == "Not working")
        #expect(FanHelperRow.tone(.ready(installed: false), answers: true) == .ok)
        #expect(FanHelperRow.tone(.ready(installed: false), answers: false) == .attention)
        #expect(FanHelperRow.tone(.needsApproval, answers: nil) == .attention)
        #expect(FanHelperRow.tone(.notSetUp, answers: nil) == .neutral)
        #expect(FanHelperRow.note(.failed("SMC 0x82"), answers: nil).contains("SMC 0x82"))
        #expect(FanHelperRow.note(.ready(installed: true), answers: true).contains("password"))
    }
}

struct FanDemoTests {
    @Test func simulatedFansAreAskedForInTheEnvironmentAlone() {
        #expect(FanSensors.demoCount(environment: nil) == nil)
        #expect(FanSensors.demoCount(environment: "1") == 1)
        #expect(FanSensors.demoCount(environment: "9") == 2)
        #expect(FanSensors.demoCount(environment: "0") == nil)
    }
}

/// What's New: the notes of a version, and the page that shows them.
struct ReleaseNotesTests {
    @Test func theNotesHaveSomethingInEverySectionShown() {
        let notes = ReleaseNotes.current
        #expect(!notes.version.isEmpty && !notes.sections.isEmpty)
        for section in notes.sections { #expect(!notes.items(section).isEmpty) }
        // Each item once: the list tells them apart by their titles.
        for section in ReleaseNotes.Section.allCases {
            let titles = notes.items(section).map(\.title)
            #expect(Set(titles).count == titles.count)
        }
        #expect(ReleaseNotes(version: "1", new: [], fixed: [.init(title: "a", detail: "b")], known: []).sections == [.fixed])
    }

    @Test func thePageIsThePanelsButNeverInThePickerOrStored() {
        #expect(!ExpandedPage.allCases.contains(.whatsNew) && !ExpandedPage.whatsNew.isBoard && !ExpandedPage.whatsNew.isNoticeCard)
        #expect(ExpandedPage(rawValue: "whatsNew") == nil)
        #expect(AppCommand.parse(URL(string: "notchisland://whatsnew")!) == .showWhatsNew)
    }
}
