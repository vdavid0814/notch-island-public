import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import NotchIslandKit

/// Window Anchor's numbers, on this Mac's screen (1280×832, a 156 pt notch, a 29 pt menu bar) and others.
@Suite struct AnchorGeometryTests {
    let screen = AnchorScreen(frame: CGRect(x: 0, y: 0, width: 1280, height: 832), band: 29, notch: CGSize(width: 156, height: 28))

    @Test func dropZoneLiesAroundTheNotchBelowTheBand() {
        let zone = AnchorGeometry.dropZone(screen)
        #expect(zone == CGRect(x: 422, y: 29, width: 436, height: 110))
        // Not in the band itself: the top edge is where macOS tiles.
        #expect(!zone.contains(CGPoint(x: 640, y: 10)))
        #expect(zone.contains(CGPoint(x: 640, y: 60)))
        #expect(!zone.contains(CGPoint(x: 400, y: 60)))
    }

    @Test func defaultSizeIsClampedToAWindow() {
        #expect(AnchorGeometry.defaultSize(screen) == CGSize(width: 620, height: 433))
        let large = AnchorScreen(frame: CGRect(x: 0, y: 0, width: 3008, height: 1692), band: 25, notch: CGSize(width: 180, height: 25))
        #expect(AnchorGeometry.defaultSize(large) == CGSize(width: 980, height: 680))
        let middle = AnchorScreen(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), band: 38, notch: CGSize(width: 185, height: 38))
        #expect(AnchorGeometry.defaultSize(middle) == CGSize(width: 795, height: 581))
    }

    @Test func restIsCentredRightUnderTheBand() {
        let rest = AnchorGeometry.restFrame(screen, size: CGSize(width: 620, height: 433))
        #expect(rest == CGRect(x: 330, y: 29, width: 620, height: 433))
        // A second display to the right and lower, as the window server places it.
        let other = AnchorScreen(frame: CGRect(x: 1280, y: -200, width: 1920, height: 1080), band: 25, notch: CGSize(width: 180, height: 25))
        #expect(AnchorGeometry.restFrame(other, size: CGSize(width: 800, height: 500)) == CGRect(x: 1840, y: -175, width: 800, height: 500))
        // Never larger than the screen leaves.
        let huge = AnchorGeometry.restFrame(screen, size: CGSize(width: 2000, height: 2000))
        #expect(huge.width == 1280 && huge.maxY == 832 && huge.minX == 0)
    }

    @Test func tuckIsBoundedByTheNotchAndByWhatWasAccepted() {
        #expect(AnchorGeometry.maximumTuck(screen, limit: nil) == 28)
        #expect(AnchorGeometry.maximumTuck(screen, limit: 6) == 6)
        #expect(AnchorGeometry.restFrame(screen, size: CGSize(width: 620, height: 433), tuck: 20).minY == 9)
        #expect(AnchorGeometry.restFrame(screen, size: CGSize(width: 620, height: 433), tuck: 20, tuckLimit: 6).minY == 23)
        #expect(AnchorGeometry.restFrame(screen, size: CGSize(width: 620, height: 433), tuck: -5).minY == 29)
    }

    @Test func whatTheAppAcceptsIsAdopted() {
        // Notes keeps 701 pt: the wider window is centred again.
        let asked = CGRect(x: 330, y: 29, width: 620, height: 433)
        let notes = AnchorGeometry.adopted(screen, asked: asked, got: CGRect(x: 330, y: 29, width: 701, height: 433))
        #expect(notes.frame == CGRect(x: 290, y: 29, width: 701, height: 433))
        #expect(notes.tuck == 0 && notes.tuckLimit == nil)
        // A top asked into the band comes back lower than asked: how far it got is the limit, remembered.
        let tucked = AnchorGeometry.adopted(screen, asked: CGRect(x: 330, y: 9, width: 620, height: 433), got: CGRect(x: 330, y: 23, width: 620, height: 433))
        #expect(tucked.tuck == 6 && tucked.tuckLimit == 6)
        // Kept under the menu bar (every app on macOS 27): a limit of none.
        let kept = AnchorGeometry.adopted(screen, asked: CGRect(x: 330, y: 9, width: 620, height: 433), got: asked)
        #expect(kept.tuck == 0 && kept.tuckLimit == 0)
        // Accepted as asked: no limit learned.
        let free = AnchorGeometry.adopted(screen, asked: CGRect(x: 330, y: 9, width: 620, height: 433), got: CGRect(x: 330, y: 9, width: 620, height: 433))
        #expect(free.tuck == 20 && free.tuckLimit == nil)
    }

    @Test func releasedOnlyWellAwayFromRest() {
        let rest = CGRect(x: 330, y: 29, width: 620, height: 433)
        #expect(!AnchorGeometry.isReleased(rest.offsetBy(dx: 80, dy: 80), rest: rest))
        #expect(AnchorGeometry.isReleased(rest.offsetBy(dx: 100, dy: 80), rest: rest))
        #expect(AnchorGeometry.isReleased(rest.offsetBy(dx: 0, dy: 121), rest: rest))
    }

    @Test func aResizeThatFillsTheScreenIsAZoom() {
        #expect(AnchorGeometry.fillsScreen(CGSize(width: 1280, height: 803), screen: screen))
        #expect(!AnchorGeometry.fillsScreen(CGSize(width: 640, height: 803), screen: screen))
        #expect(!AnchorGeometry.fillsScreen(CGSize(width: 900, height: 600), screen: screen))
    }

    @Test func aTopEdgeDraggedUpIsTheTuck() {
        #expect(AnchorGeometry.tuck(afterResizeTo: CGRect(x: 330, y: 23, width: 620, height: 439), screen: screen, limit: nil) == 6)
        #expect(AnchorGeometry.tuck(afterResizeTo: CGRect(x: 330, y: 60, width: 620, height: 400), screen: screen, limit: nil) == 0)
        #expect(AnchorGeometry.tuck(afterResizeTo: CGRect(x: 330, y: 5, width: 620, height: 463), screen: screen, limit: 6) == 6)
    }
}

/// The live copy at the top of the screen, and the size every anchored window is given.
@Suite struct AnchorStageTests {
    let screen = AnchorScreen(frame: CGRect(x: 0, y: 0, width: 1280, height: 832), band: 29, notch: CGSize(width: 156, height: 28))

    @Test func underTheWindowASlimBarAndThePictureAsHighAsItAllows() {
        let rest = AnchorGeometry.restFrame(screen, size: CGSize(width: 620, height: 433))
        let layout = AnchorStageLayout(screen: screen, rest: rest, placement: .belowWindow)
        // The bar is 22 pt, the picture 7 pt below the screen's top (29 − 22).
        #expect(layout.offset == 22)
        #expect(layout.frame == CGRect(x: 320, y: 0, width: 640, height: 462))
        #expect(layout.copy == CGRect(x: 10, y: 7, width: 620, height: 433))
        #expect(layout.chin == CGRect(x: 10, y: 440, width: 620, height: 22))
        #expect(layout.copyInScreen == CGRect(x: 330, y: 7, width: 620, height: 433))
        // The stage's bottom is where the real window ends: none of it shows under the stage.
        #expect(layout.frame.maxY == rest.maxY)
        // A second display, placed higher: the stage starts at its own top.
        let other = AnchorScreen(frame: CGRect(x: 1280, y: -200, width: 1920, height: 1080), band: 25, notch: CGSize(width: 180, height: 25))
        let high = AnchorStageLayout(screen: other, rest: AnchorGeometry.restFrame(other, size: CGSize(width: 800, height: 500)))
        #expect(high.frame.minY == -200 && high.offset == 22 && high.copy.minY == 3)
    }

    /// Only the window's very top edge beside the notch brings the tab up.
    @Test func theRaiseEdgeIsTheWindowsTopBesideTheNotch() {
        let rest = AnchorGeometry.restFrame(screen, size: CGSize(width: 620, height: 433))
        let stage = AnchorStageLayout(screen: screen, rest: rest, placement: .menuBar)
        let top = stage.copy.minY
        let notch = CGRect(x: stage.frame.width / 2 - 50, y: 0, width: 100, height: top)
        let beside = stage.copy.minX + 10
        #expect(stage.isOnRaiseEdge(CGPoint(x: beside, y: top), notch: notch))
        #expect(stage.isOnRaiseEdge(CGPoint(x: beside, y: top + AnchorStageLayout.raiseEdgeReach), notch: notch))
        #expect(!stage.isOnRaiseEdge(CGPoint(x: beside, y: top + AnchorStageLayout.raiseEdgeReach + 1), notch: notch))
        #expect(!stage.isOnRaiseEdge(CGPoint(x: notch.midX, y: top), notch: notch))
        #expect(!stage.isOnRaiseEdge(CGPoint(x: stage.copy.minX - 1, y: top), notch: notch))
    }

    /// The tab at the window's top moves the picture; the stage stays exactly where it is.
    @Test func raisingMovesOnlyThePicture() {
        let rest = AnchorGeometry.restFrame(screen, size: CGSize(width: 620, height: 433))
        let low = AnchorStageLayout(screen: screen, rest: rest, placement: .menuBar)
        let high = AnchorStageLayout(screen: screen, rest: rest, placement: .belowWindow)
        #expect(low.frame == high.frame)
        #expect(low.copy(raisedBy: 0) == low.copy && low.copy(raisedBy: 22) == high.copy)
        #expect(low.copy(raisedBy: 100) == high.copy)
        #expect(low.copy(raisedBy: -5) == low.copy)
    }

    @Test func besideTheNotchNothingIsBelowTheWindow() {
        let rest = AnchorGeometry.restFrame(screen, size: CGSize(width: 620, height: 433))
        let layout = AnchorStageLayout(screen: screen, rest: rest, placement: .menuBar)
        // The picture lies exactly over the real window; the band above it holds the name and Release.
        #expect(layout.offset == 0)
        #expect(layout.band == 29)
        #expect(layout.copyInScreen == rest)
        #expect(layout.chin.height == 0)
        #expect(layout.frame.maxY == rest.maxY)
    }

    @Test func aPointOnThePictureIsSentWhereTheWindowHasIt() {
        let layout = AnchorStageLayout(screen: screen, rest: AnchorGeometry.restFrame(screen, size: CGSize(width: 620, height: 433)))
        // The picture's top-left is the window's.
        #expect(layout.forwarded(CGPoint(x: 330, y: 7)) == CGPoint(x: 330, y: 29))
        #expect(layout.inWindow(CGPoint(x: 330, y: 7)) == .zero)
        #expect(layout.forwarded(CGPoint(x: 560, y: 128)) == CGPoint(x: 560, y: 150))
        #expect(layout.inWindow(CGPoint(x: 560, y: 128)) == CGPoint(x: 230, y: 121))
    }

    @Test func onlyADialogSizedWindowOfTheAppMovesTheStageAside() {
        let layout = AnchorStageLayout(screen: screen, rest: AnchorGeometry.restFrame(screen, size: CGSize(width: 620, height: 433)))
        // TextEdit's 66×20 helper window, a tooltip: seen through.
        #expect(!layout.isOverlaid(by: CGRect(x: 336, y: 35, width: 66, height: 20)))
        // A sheet.
        #expect(layout.isOverlaid(by: CGRect(x: 400, y: 60, width: 460, height: 220)))
        // A large window only touching the stage's edge.
        #expect(!layout.isOverlaid(by: CGRect(x: 900, y: 100, width: 500, height: 500)))
        #expect(!layout.isOverlaid(by: CGRect(x: 0, y: 600, width: 1280, height: 200)))
    }

    @Test func theSetSizeIsKeptWithinTheScreen() {
        #expect(AnchorSizePreference().isAutomatic)
        #expect(AnchorSizePreference().size(on: screen) == AnchorGeometry.defaultSize(screen))
        #expect(AnchorSizePreference(width: 800, height: 500).size(on: screen) == CGSize(width: 800, height: 500))
        // Taller than the screen leaves under the menu bar, wider than the screen: cut to fit.
        #expect(AnchorSizePreference(width: 1600, height: 1200).size(on: screen) == CGSize(width: 1280, height: 774))
        // Only the width set: the height is automatic.
        #expect(AnchorSizePreference(width: 900).size(on: screen) == CGSize(width: 900, height: 433))
    }

    @Test func namedSizesFollowTheScreenWithinWhatCanBeSet() {
        let sizes = AnchorSizePreset.allCases.map { $0.size(on: screen) }
        #expect(sizes == [nil, CGSize(width: 461, height: 300), CGSize(width: 640, height: 458), CGSize(width: 794, height: 566),
                          CGSize(width: 538, height: 682), CGSize(width: 1024, height: 416), nil])
        // A small screen: never under the least a window is given.
        let small = AnchorScreen(frame: CGRect(x: 0, y: 0, width: 1024, height: 640), band: 24, notch: .zero)
        #expect(AnchorSizePreset.small.size(on: small) == CGSize(width: 369, height: 230))
        let tiny = AnchorScreen(frame: CGRect(x: 0, y: 0, width: 600, height: 400), band: 24, notch: .zero)
        #expect(AnchorSizePreset.small.size(on: tiny) == CGSize(width: 240, height: 160))
        #expect(AnchorSizePreference.heights(on: screen) == 160...774)
        #expect(AnchorSizePreference.widths(on: screen) == 240...1280)
    }

    @Test func thePickIsAutomaticNamedOrCustom() {
        #expect(AnchorSizePreference().choice == .automatic)
        let large = AnchorSizePreference(preset: .large)
        #expect(large.choice == .large && !large.isAutomatic)
        #expect(large.size(on: screen) == CGSize(width: 794, height: 566))
        #expect(AnchorSizePreference(width: 800, height: 500).choice == .custom)
        // Custom with nothing set by hand is automatic.
        #expect(AnchorSizePreference(preset: .custom).choice == .automatic)
    }

    @Test func theSetSizeRoundTripsAndOldValuesStayAutomatic() throws {
        let size = AnchorSizePreference(width: 812, height: 520)
        let data = try JSONEncoder().encode(size)
        #expect(try JSONDecoder().decode(AnchorSizePreference.self, from: data) == size)
        #expect(try JSONDecoder().decode(AnchorSizePreference.self, from: Data("{}".utf8)).isAutomatic)
        let named = AnchorSizePreference(preset: .tall)
        #expect(try JSONDecoder().decode(AnchorSizePreference.self, from: JSONEncoder().encode(named)) == named)
        // 0.6.1's first builds kept only a width and a height: a size set by hand.
        #expect(try JSONDecoder().decode(AnchorSizePreference.self, from: Data(#"{"width":461,"height":300}"#.utf8)).choice == .custom)
    }
}

@Suite struct AnchorMemoryTests {
    @Test func remembersPerAppAndDropsTheOldest() {
        var memory = AnchorMemory()
        for index in 0..<(AnchorMemory.capacity + 3) {
            memory.remember(.init(width: 600 + Double(index), height: 400), for: "app.\(index)")
        }
        #expect(memory["app.0"] == nil && memory["app.2"] == nil)
        #expect(memory["app.3"]?.width == 603)
        // Used again, an app moves to the newest end.
        memory.remember(.init(width: 700, height: 500, tuck: 6, tuckLimit: 6), for: "app.3")
        memory.remember(.init(width: 1, height: 1), for: "new")
        #expect(memory["app.3"]?.size == CGSize(width: 700, height: 500))
        #expect(memory["app.4"] == nil)
    }

    @Test func roundTripsThroughDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "anchor.memory.\(UUID().uuidString)"))
        var memory = AnchorMemory()
        memory.remember(.init(width: 701, height: 433, tuck: 6, tuckLimit: 6), for: "com.apple.Notes")
        memory.save(to: defaults)
        #expect(AnchorMemory.load(from: defaults) == memory)
        #expect(AnchorMemory.load(from: try #require(UserDefaults(suiteName: "anchor.memory.empty.\(UUID().uuidString)"))) == AnchorMemory())
    }
}

@Suite struct WindowDragLatchTests {
    let atPress = CGRect(x: 100, y: 100, width: 600, height: 400)

    @Test func aWindowThatFollowsThePointerIsDragged() {
        var latch = WindowDragLatch()
        latch.mouseDown(overWindow: true)
        #expect(latch.isUndecided)
        let r1 = latch.mouseDragged(at: 10.00)
        #expect(!r1)
        let r2 = latch.mouseDragged(at: 10.05)
        #expect(!r2)
        let r3 = latch.mouseDragged(at: 10.11)
        #expect(r3)
        latch.looked(atPress: atPress, now: atPress.offsetBy(dx: 30, dy: 12))
        #expect(latch.isDragging && !latch.isUndecided)
        // Decided: no more looks.
        let r4 = latch.mouseDragged(at: 10.4)
        #expect(!r4)
        let r5 = latch.mouseUp()
        #expect(r5)
        #expect(latch.phase == .idle)
    }

    @Test func twoLooksAtAStillWindowEndIt() {
        var latch = WindowDragLatch()
        latch.mouseDown(overWindow: true)
        _ = latch.mouseDragged(at: 5)
        let r6 = latch.mouseDragged(at: 5.12)
        #expect(r6)
        latch.looked(atPress: atPress, now: atPress)
        #expect(latch.isUndecided)
        // The second look is not due yet.
        let r7 = latch.mouseDragged(at: 5.2)
        #expect(!r7)
        let r8 = latch.mouseDragged(at: 5.26)
        #expect(r8)
        latch.looked(atPress: atPress, now: atPress.offsetBy(dx: 1, dy: 0))
        #expect(latch.phase == .ignored)
        let r9 = latch.mouseDragged(at: 5.5)
        #expect(!r9)
        let r10 = latch.mouseUp()
        #expect(!r10)
    }

    @Test func aSlowStartIsCaughtByTheSecondLook() {
        var latch = WindowDragLatch()
        latch.mouseDown(overWindow: true)
        _ = latch.mouseDragged(at: 5)
        _ = latch.mouseDragged(at: 5.1)
        latch.looked(atPress: atPress, now: atPress)
        _ = latch.mouseDragged(at: 5.3)
        latch.looked(atPress: atPress, now: atPress.offsetBy(dx: 0, dy: 9))
        #expect(latch.isDragging)
    }

    @Test func aResizeIsNotADrag() {
        var latch = WindowDragLatch()
        latch.mouseDown(overWindow: true)
        _ = latch.mouseDragged(at: 1)
        _ = latch.mouseDragged(at: 1.1)
        // The left edge dragged: the origin moves, and so does the size.
        latch.looked(atPress: atPress, now: CGRect(x: 60, y: 100, width: 640, height: 400))
        #expect(latch.phase == .ignored)
    }

    @Test func aPressOffAnyWindowOrAGoneWindowIsIgnored() {
        var latch = WindowDragLatch()
        latch.mouseDown(overWindow: false)
        #expect(!latch.isUndecided)
        let r11 = latch.mouseDragged(at: 1)
        #expect(!r11)
        let r12 = latch.mouseUp()
        #expect(!r12)
        latch.mouseDown(overWindow: true)
        _ = latch.mouseDragged(at: 2)
        _ = latch.mouseDragged(at: 2.1)
        latch.lookFailed()
        #expect(latch.phase == .ignored)
    }
}

@Suite struct CoverStateTests {
    let window = CGRect(x: 100, y: 100, width: 400, height: 200)

    @Test func shareCountsOverlapsOnce() {
        #expect(CoverState.share(of: window, under: []) == 0)
        #expect(CoverState.share(of: window, under: [CGRect(x: 0, y: 0, width: 50, height: 50)]) == 0)
        #expect(abs(CoverState.share(of: window, under: [CGRect(x: 0, y: 0, width: 300, height: 200)]) - 0.25) < 1e-9)
        // Two windows over the same quarter are still a quarter.
        let twice = [CGRect(x: 0, y: 0, width: 300, height: 200), CGRect(x: 50, y: 50, width: 250, height: 150)]
        #expect(abs(CoverState.share(of: window, under: twice) - 0.25) < 1e-9)
        // Side by side they add up.
        let apart = [CGRect(x: 100, y: 100, width: 100, height: 200), CGRect(x: 400, y: 100, width: 100, height: 200)]
        #expect(abs(CoverState.share(of: window, under: apart) - 0.5) < 1e-9)
        #expect(CoverState.share(of: window, under: [window.insetBy(dx: -10, dy: -10)]) == 1)
        #expect(CoverState.share(of: .zero, under: [window]) == 0)
    }

    @Test func coveredAboveFourPercentUncoveredBelowOne() {
        var state = CoverState()
        let r13 = state.update(share: 0.03)
        #expect(!r13)
        #expect(!state.isCovered)
        let r14 = state.update(share: 0.05)
        #expect(r14)
        #expect(state.isCovered)
        // Between the two thresholds it stays as it is.
        let r15 = state.update(share: 0.02)
        #expect(!r15)
        #expect(state.isCovered)
        let r16 = state.update(share: 0.005)
        #expect(r16)
        #expect(!state.isCovered)
        let r17 = state.update(share: 0.02)
        #expect(!r17)
    }
}

@Suite struct AnchorFeatureStateTests {
    private func state(enabled: Bool = true, trusted: Bool = true, drag: Bool = true, mirror: Bool = false, paused: Bool = false,
                       away: Bool = false, suspended: Bool = false) -> FeatureState {
        FeatureState(showNowPlaying: false, showLevelHUD: false, replaceSystemHUD: false, accessibilityTrusted: trusted, shelfEnabled: false,
                     suspended: suspended, anchorEnabled: enabled, anchorByDrag: drag, anchorMirror: mirror, anchorPaused: paused,
                     anchorAway: away)
    }

    @Test func runsOnlyWithThePreferenceAndAccessibility() {
        #expect(state().anchor && state().anchorDrag)
        #expect(!state(enabled: false).anchor && !state(enabled: false).anchorDrag)
        #expect(!state(trusted: false).anchor && !state(trusted: false).anchorDrag && !state(trusted: false, mirror: true).anchorMirror)
        #expect(!state(drag: false).anchorDrag && state(drag: false).anchor)
        #expect(state(mirror: true).anchorMirror)
        #expect(state(suspended: true).anchorPaused && state(paused: true).anchorPaused && !state().anchorPaused)
        #expect(!state(enabled: false, paused: true).anchorPaused)
        #expect(FeatureState.off.anchor == false)
    }

    /// A full-screen app in front: the window is left alone, its live copy stays over the app.
    @Test func fullScreenPausesTheWindowNotItsCopy() {
        let away = state(mirror: true, away: true)
        #expect(away.anchorPaused && !away.anchorMirrorPaused)
        #expect(FeatureState.actions(from: state(mirror: true), to: away) == [.setAnchorPaused(true)])
        #expect(state(mirror: true, away: true, suspended: true).anchorMirrorPaused)
        #expect(state(mirror: true, paused: true).anchorMirrorPaused)
    }

    @Test func startsBeforeItsPartsAndStopsAfterThem() {
        let none = state(enabled: false)
        let on = FeatureState.actions(from: none, to: state(mirror: true)).filter { if case .setAnchor = $0 { true } else if case .setAnchorDrag = $0 { true } else if case .setAnchorMirror = $0 { true } else { false } }
        #expect(on == [.setAnchor(true), .setAnchorDrag(true), .setAnchorMirror(true)])
        let off = FeatureState.actions(from: state(mirror: true), to: none)
        #expect(off.suffix(3) == [.setAnchorDrag(false), .setAnchorMirror(false), .setAnchor(false)])
        #expect(FeatureState.actions(from: state(), to: state()).isEmpty)
        #expect(FeatureState.actions(from: state(), to: state(paused: true)) == [.setAnchorPaused(true), .setAnchorMirrorPaused(true)])
        // Accessibility taken away: everything of it stops.
        #expect(FeatureState.actions(from: state(), to: state(trusted: false)).contains(.setAnchor(false)))
    }

    @Test func linksParse() {
        #expect(AppCommand.parse(URL(string: "notchisland://anchor/front")!) == .anchorFrontWindow)
        #expect(AppCommand.parse(URL(string: "notchisland://anchor/release")!) == .releaseAnchoredWindow)
        #expect(AppCommand.parse(URL(string: "notchisland://demo/anchortarget")!) == .demo(.anchorTarget(true)))
        #expect(AppCommand.parse(URL(string: "notchisland://demo/anchortarget?on=0")!) == .demo(.anchorTarget(false)))
    }

    @Test func aTargetedWindowShowsItsBannerBelowAFileDrag() {
        var inputs = IslandInputs()
        inputs.isAnchorTargeted = true
        inputs.nowPlayingActive = true
        #expect(IslandResolver.resolve(inputs) == .banner(.anchorTarget))
        inputs.isDragInProgress = true
        #expect(IslandResolver.resolve(inputs) == .banner(.dropTarget))
        inputs.isDragInProgress = false
        inputs.isHidden = true
        #expect(IslandResolver.resolve(inputs) == .idle)
        #expect(!BannerKind.anchorTarget.isInteractive && !BannerKind.anchorTarget.showsWhileHidden)
    }
}

/// The live copy leaves out a frame that is the same as the one shown in its changed rectangles.
@Suite struct MirrorFrameTests {
    private func buffer(width: Int = 40, height: Int = 30, fill: UInt8 = 0x20) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixels = buffer!
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), Int32(fill), CVPixelBufferGetBytesPerRow(pixels) * height)
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return pixels
    }

    private func set(_ pixels: CVPixelBuffer, x: Int, y: Int, to value: UInt8) {
        CVPixelBufferLockBaseAddress(pixels, [])
        let row = CVPixelBufferGetBaseAddress(pixels)! + y * CVPixelBufferGetBytesPerRow(pixels)
        row.storeBytes(of: value, toByteOffset: x * 4, as: UInt8.self)
        CVPixelBufferUnlockBaseAddress(pixels, [])
    }

    @Test func onlyAFrameTheSameEverywhereIsLeftOut() {
        let old = buffer(), new = buffer()
        #expect(MirrorOutput.difference(new, old) == nil)
        #expect(MirrorOutput.difference(new, old, hint: 7, rects: [CGRect(x: 0, y: 0, width: 10, height: 10)]) == nil)
        // A difference outside the changed rectangles counts too (Safari's video is not in them).
        set(new, x: 30, y: 20, to: 0xFF)
        #expect(MirrorOutput.difference(new, old, rects: [CGRect(x: 0, y: 0, width: 10, height: 10)]) == 20)
        #expect(MirrorOutput.difference(new, old, hint: 20) == 20)
        #expect(MirrorOutput.difference(new, old, hint: 500) == 20)
    }

    @Test func anythingUnsureIsShown() {
        // Another size: shown. A rectangle reaching past the frame is clipped to it.
        #expect(MirrorOutput.difference(buffer(width: 40), buffer(width: 41)) == 0)
        #expect(MirrorOutput.difference(buffer(), buffer(), rects: [CGRect(x: 30, y: 20, width: 100, height: 100)]) == nil)
    }
}

@Suite struct AppInfoEnergyTests {
    /// What the ⓘ page says: about 25 J a day, about a hundredth of a percent of the battery.
    @Test func anAverageDayIsNextToNothing() {
        #expect(abs(AppInfoEnergy.totalJoules - 24.9) < 0.1)
        #expect(abs(AppInfoEnergy.batteryShare * 100 - 0.013) < 0.001)
    }

    @Test func theNowPlayingPillMovesOnlyItsOwnEars() {
        let notch = CGSize(width: 180, height: 32)
        let usual = IslandLayout(notch: notch, scale: .standard)
        var wide = usual
        wide.nowPlayingWidth = 1.2
        var narrow = usual
        narrow.nowPlayingWidth = 0.9
        // Each ear: 38 pt usually, 46 at its widest, 34 at its narrowest.
        #expect(usual.size(for: .compact(.nowPlaying)).width == 256)
        #expect(wide.size(for: .compact(.nowPlaying)).width == 272)
        #expect(narrow.size(for: .compact(.nowPlaying)).width == 248)
        #expect(wide.size(for: .compact(.timer)) == usual.size(for: .compact(.timer)))
        // The cover stays clear of the notch at the narrowest.
        let split = NotchSplit(layout: narrow, presentation: .compact(.nowPlaying), outerInset: Metrics.Compact.inset,
                               clearance: Metrics.Compact.notchClearance)
        #expect(split.earWidth + Metrics.Compact.notchClearance >= narrow.notch.height - 2 * Metrics.Compact.inset)
    }

    @Test func theAppInfoPageIsNeverStoredOrPicked() {
        #expect(!ExpandedPage.allCases.contains(.appInfo) && !ExpandedPage.appInfo.isBoard)
        #expect(ExpandedPage(rawValue: "appInfo") == nil)
        #expect(AppCommand.parse(URL(string: "notchisland://appinfo")!) == .showAppInfo)
    }
}
