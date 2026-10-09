import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import NotchIslandKit

// MARK: - Resolver

@Suite struct IslandResolverTests {
    @Test func nothingActiveIsIdle() {
        #expect(IslandResolver.resolve(IslandInputs()) == .idle)
    }

    @Test func priorityOrderIsExpandedDragBannerCountdownStopwatchNowPlaying() {
        var inputs = IslandInputs()
        inputs.nowPlayingActive = true
        #expect(IslandResolver.resolve(inputs) == .compact(.nowPlaying))
        inputs.stopwatchActive = true
        #expect(IslandResolver.resolve(inputs) == .compact(.stopwatch))
        inputs.countdownActive = true
        #expect(IslandResolver.resolve(inputs) == .compact(.timer))
        inputs.banner = .power(.connected)
        #expect(IslandResolver.resolve(inputs) == .banner(.power(.connected)))
        inputs.isDragInProgress = true
        #expect(IslandResolver.resolve(inputs) == .banner(.dropTarget))
        inputs.wantsExpanded = true
        inputs.page = .timer
        #expect(IslandResolver.resolve(inputs) == .expanded(.timer))
    }

    /// Recording outranks the ongoing activities but not a notice; the pointer opens its card, the
    /// panel only when asked for.
    @Test func recordingShowsRoundTheNotchAndItsCardOnOpen() {
        var inputs = IslandInputs(countdownActive: true, stopwatchActive: true, nowPlayingActive: true, recordingActive: true)
        #expect(IslandResolver.resolve(inputs) == .compact(.recording))
        inputs.banner = .power(.connected)
        #expect(IslandResolver.resolve(inputs) == .banner(.power(.connected)))
        inputs.wantsExpanded = true
        inputs.page = .shelf
        #expect(IslandResolver.resolve(inputs) == .expanded(.recording))
        inputs.wantsPanelWhileRecording = true
        #expect(IslandResolver.resolve(inputs) == .expanded(.shelf))
        // The card is no page of the picker, and a little larger than the pill.
        #expect(!ExpandedPage.allCases.contains(.recording) && !ExpandedPage.recording.isBoard)
        let layout = IslandLayout(notch: CGSize(width: 185, height: 32), scale: .standard)
        let pill = layout.size(for: .compact(.recording)), card = layout.size(for: .expanded(.recording))
        #expect(pill.height == 32 && pill.width > layout.size(for: .compact(.timer)).width)
        #expect(card.width >= pill.width && card.height > pill.height && card.height < layout.size(for: .expanded(.home)).height)
    }

    @Test(arguments: ExpandedPage.allCases)
    func expandedCarriesThePage(page: ExpandedPage) {
        let inputs = IslandInputs(wantsExpanded: true, page: page, banner: .level(.volume))
        #expect(IslandResolver.resolve(inputs) == .expanded(page))
    }

    @Test func bannerKindPassesThrough() {
        for kind: BannerKind in [.level(.volume), .level(.brightness), .power(.low(threshold: 10)), .timerFinished] {
            #expect(IslandResolver.resolve(IslandInputs(banner: kind, countdownActive: true)) == .banner(kind))
        }
    }
}

// MARK: - Layout

@Suite struct IslandLayoutTests {
    nonisolated static let notches = [CGSize(width: 156, height: 28), CGSize(width: 185, height: 32), CGSize(width: 180, height: 24)]

    @Test func scaleFactorsAndTitles() {
        #expect(IslandScale.compact.factor == 0.9)
        #expect(IslandScale.standard.factor == 1.0)
        #expect(IslandScale.large.factor == 1.15)
        #expect(IslandScale.extraSmall.factor < IslandScale.small.factor)
        #expect(IslandScale.small.factor < IslandScale.compact.factor)
        #expect(IslandScale.allCases.map(\.title) == ["Extra Small", "Small", "Standard", "Large", "Extra Large"])
        #expect(IslandScale.large.id == "large")
    }

    @Test func scaleRoundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(IslandScale.large)
        #expect(try JSONDecoder().decode(IslandScale.self, from: data) == .large)
    }

    @Test(arguments: notches)
    func idleIsTheNotch(notch: CGSize) {
        let layout = IslandLayout(notch: notch, scale: .large)
        #expect(layout.size(for: .idle) == notch)
        #expect(layout.shoulderRadius(for: .idle) == 0)
    }

    @Test(arguments: notches, IslandScale.allCases)
    func compactHugsTheNotchAndNeverScales(notch: CGSize, scale: IslandScale) {
        let layout = IslandLayout(notch: notch, scale: scale)
        let size = layout.size(for: .compact(.nowPlaying))
        #expect(size.height == notch.height)
        #expect(size.width == notch.width + 2 * (notch.height + 6))
        #expect(layout.bottomRadius(for: .compact(.timer)) == notch.height / 2)
        #expect(layout.shoulderRadius(for: .compact(.timer)) == 6)
    }

    @Test(arguments: notches, IslandScale.allCases)
    func bannerNeverScales(notch: CGSize, scale: IslandScale) {
        let layout = IslandLayout(notch: notch, scale: scale)
        let size = layout.size(for: .banner(.level(.volume)))
        #expect(size.width == max(notch.width + 2 * (notch.height + 6), 380))
        #expect(size.height == notch.height + 48)
        #expect(layout.bottomRadius(for: .banner(.timerFinished)) == 24)
        #expect(layout.shoulderRadius(for: .banner(.dropTarget)) == 8)
    }

    @Test func expandedIsItsBoardAndTheInsetsRoundIt() {
        let notch = CGSize(width: 156, height: 28)
        for scale in IslandScale.allCases {
            let layout = IslandLayout(notch: notch, scale: scale)
            let size = layout.size(for: .expanded(.timer))
            // The board's cells and gaps at the scale, the insets round them; the header band is
            // always exactly the notch's height.
            // So many pitches (a cell and its gap) at the reference gap, the insets round them.
            let pitch = (48 * scale.factor).rounded()
            #expect(layout.pitch == pitch && layout.cell == pitch - 8)
            #expect(size.width == 12 * pitch - IslandLayout.referenceGap + 2 * IslandLayout.boardSideInset)
            #expect(size.height - notch.height
                    == IslandLayout.boardTopInset + 3 * pitch - IslandLayout.referenceGap + IslandLayout.boardBottomInset)
        }
        let large = IslandLayout(notch: notch, scale: .large)
        #expect(large.bottomRadius(for: .expanded(.shelf)) == 28 * 1.15)
        #expect(large.shoulderRadius(for: .expanded(.shelf)) == 10)
        // The insets are the page's (`Metrics.Expanded`).
        #expect(IslandLayout.boardSideInset == 10 + Metrics.Expanded.horizontalInset)
        #expect(IslandLayout.boardTopInset == Metrics.Expanded.pageTopInset)
        #expect(IslandLayout.boardBottomInset == Metrics.Expanded.pageBottomInset)
    }

    @Test func expandedSizeDoesNotDependOnThePage() {
        let layout = IslandLayout(notch: CGSize(width: 156, height: 28), scale: .standard)
        let sizes = Set(ExpandedPage.allCases.map { "\(layout.size(for: .expanded($0)))" })
        #expect(sizes.count == 1)
    }

    @Test(arguments: [IslandPresentation.idle, .compact(.timer), .banner(.power(.charged)), .expanded(.home)])
    func islandRectIsCentredAndFlushWithTheTop(presentation: IslandPresentation) {
        let layout = IslandLayout(notch: CGSize(width: 156, height: 28), scale: .large)
        let stage = CGSize(width: 900, height: 300)
        let rect = layout.islandRect(for: presentation, inStage: stage)
        #expect(rect.size == layout.size(for: presentation))
        #expect(rect.midX == stage.width / 2)
        // AppKit coordinates: bottom-left origin, so "flush top" means maxY == stage height.
        #expect(rect.maxY == stage.height)
    }
}

// MARK: - Notch metrics & stage geometry

@Suite struct NotchMetricsTests {
    static let screen = CGRect(x: 0, y: 0, width: 1280, height: 832)

    @Test func physicalNotchComesFromSafeAreaAndAuxiliaryAreas() {
        let m = NotchMetrics.derive(
            displayID: 1, screenFrame: Self.screen, safeAreaTop: 32,
            auxiliaryTopLeftWidth: 562, auxiliaryTopRightWidth: 562, menuBarThickness: 24
        )
        #expect(m.isPhysical)
        #expect(m.notchRect == CGRect(x: 562, y: 800, width: 156, height: 32))
        #expect(m.notchSize == CGSize(width: 156, height: 32))
        #expect(m.displayID == 1)
    }

    @Test func physicalNotchFollowsTheScreenOrigin() {
        let frame = CGRect(x: -1280, y: 200, width: 1280, height: 832)
        let m = NotchMetrics.derive(
            displayID: 2, screenFrame: frame, safeAreaTop: 32,
            auxiliaryTopLeftWidth: 562, auxiliaryTopRightWidth: 562, menuBarThickness: 24
        )
        #expect(m.notchRect == CGRect(x: -718, y: 1000, width: 156, height: 32))
        #expect(m.notchRect.maxY == frame.maxY)
    }

    @Test func noCameraHousingSynthesisesACentredPill() {
        let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let m = NotchMetrics.derive(
            displayID: 3, screenFrame: frame, safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarThickness: 30
        )
        #expect(!m.isPhysical)
        #expect(m.notchRect == CGRect(x: 1190, y: 1410, width: 180, height: 30))
    }

    @Test func synthesisedHeightHasAFloor() {
        let m = NotchMetrics.derive(
            displayID: 3, screenFrame: Self.screen, safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarThickness: 22
        )
        #expect(m.notchRect.height == 24)
        #expect(m.notchRect.maxY == Self.screen.maxY)
    }

    @Test func insetWithoutAuxiliaryAreasOrWithoutGapIsNotANotch() {
        let missing = NotchMetrics.derive(
            displayID: 4, screenFrame: Self.screen, safeAreaTop: 32,
            auxiliaryTopLeftWidth: 562, auxiliaryTopRightWidth: nil, menuBarThickness: 24
        )
        #expect(!missing.isPhysical)
        let noGap = NotchMetrics.derive(
            displayID: 4, screenFrame: Self.screen, safeAreaTop: 32,
            auxiliaryTopLeftWidth: 640, auxiliaryTopRightWidth: 639.5, menuBarThickness: 24
        )
        #expect(!noGap.isPhysical)
    }
}

@Suite struct StageGeometryTests {
    static let metrics = NotchMetrics.derive(
        displayID: 1, screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 832), safeAreaTop: 32,
        auxiliaryTopLeftWidth: 562, auxiliaryTopRightWidth: 562, menuBarThickness: 24
    )
    static let layout = IslandLayout(notch: metrics.notchSize, scale: .standard)

    @Test func idleRestsExactlyOnTheNotch() {
        #expect(StageGeometry.islandFrame(for: .idle, layout: Self.layout, metrics: Self.metrics) == Self.metrics.notchRect)
        #expect(StageGeometry.restingFrame(for: .idle, layout: Self.layout, metrics: Self.metrics) == Self.metrics.notchRect)
    }

    @Test(arguments: [IslandPresentation.compact(.nowPlaying), .banner(.level(.volume)), .expanded(.shelf)])
    func restingFrameKeepsAMarginAndTheIslandInPlace(presentation: IslandPresentation) {
        let island = StageGeometry.islandFrame(for: presentation, layout: Self.layout, metrics: Self.metrics)
        let frame = StageGeometry.restingFrame(for: presentation, layout: Self.layout, metrics: Self.metrics)
        let m = StageGeometry.restingMargin(for: presentation)
        #expect(m == (presentation.isExpanded || presentation.isSettings ? IslandLayout.stageMargin : IslandLayout.restingMargin))
        #expect(frame == CGRect(x: island.minX - m, y: island.minY - m, width: island.width + 2 * m, height: island.height + m))
        #expect(frame.maxY == Self.metrics.screenFrame.maxY)
        #expect(island.midX == Self.metrics.notchRect.midX)
        // The views' top-centred layout and the window controller's rect agree.
        #expect(Self.layout.islandRect(for: presentation, inStage: frame.size) == StageGeometry.local(island, in: frame))
    }

    @Test func transitionFrameCoversBothEndsWithTheStageMargin() {
        let from = StageGeometry.islandFrame(for: .compact(.timer), layout: Self.layout, metrics: Self.metrics)
        let to = StageGeometry.islandFrame(for: .expanded(.home), layout: Self.layout, metrics: Self.metrics)
        let frame = StageGeometry.transitionFrame(covering: from.union(to), metrics: Self.metrics)
        #expect(frame.contains(from) && frame.contains(to))
        #expect(frame.maxY == Self.metrics.screenFrame.maxY)
        #expect(frame.minX == to.minX - IslandLayout.stageMargin)
        #expect(frame.minY == to.minY - IslandLayout.stageMargin)
        #expect(frame.midX == Self.metrics.notchRect.midX)
    }
}

// MARK: - Banners

@Suite struct BannerScheduleTests {
    let t0 = ContinuousClock.Instant.now

    @Test func postShowsAndExpiresAtTheDeadline() {
        var s = BannerSchedule()
        s.post(.level(.volume), duration: .seconds(1.6), now: t0)
        #expect(s.current == .level(.volume))
        #expect(s.deadline == t0 + .seconds(1.6))
        #expect(s.expire(now: t0 + .seconds(1.5)) == nil)
        #expect(s.expire(now: t0 + .seconds(1.6)) == .level(.volume))
        #expect(s.current == nil && s.deadline == nil)
    }

    @Test func differentKindReplacesWithItsOwnDeadline() {
        var s = BannerSchedule()
        s.post(.timerFinished, duration: .seconds(30), now: t0)
        s.post(.level(.brightness), duration: .seconds(1.6), now: t0 + .seconds(1))
        #expect(s.current == .level(.brightness))
        #expect(s.deadline == t0 + .seconds(2.6))
    }

    @Test func sameKindExtendsButNeverShortens() {
        var s = BannerSchedule()
        s.post(.level(.volume), duration: .seconds(1.6), now: t0)
        s.post(.level(.volume), duration: .seconds(1.6), now: t0 + .seconds(1))
        #expect(s.deadline == t0 + .seconds(2.6))
        s.post(.level(.volume), duration: .seconds(0.1), now: t0 + .seconds(1.2))
        #expect(s.deadline == t0 + .seconds(2.6))
    }

    @Test func powerEventsAreDifferentBanners() {
        var s = BannerSchedule()
        s.post(.power(.connected), duration: .seconds(3), now: t0)
        s.post(.power(.disconnected), duration: .seconds(3), now: t0 + .seconds(1))
        #expect(s.current == .power(.disconnected))
    }

    @Test func dismissTargetsOnlyTheMatchingKind() {
        var s = BannerSchedule()
        s.post(.timerFinished, duration: .seconds(30), now: t0)
        s.dismiss(.level(.volume))
        #expect(s.current == .timerFinished)
        s.dismiss(.timerFinished)
        #expect(s.current == nil)
        s.post(.dropTarget, duration: .seconds(3), now: t0)
        s.dismiss(nil)
        #expect(s.current == nil && s.deadline == nil)
    }

    @Test func holdPausesAndReleaseResumesWithAtLeastTheGrace() {
        var s = BannerSchedule()
        s.post(.level(.volume), duration: .seconds(1.6), now: t0)
        s.setHeld(true, now: t0 + .seconds(1.5))
        #expect(s.deadline == nil)
        #expect(s.expire(now: t0 + .seconds(60)) == nil)
        s.setHeld(false, now: t0 + .seconds(10))
        // 0.1 s were left; the release grace wins.
        #expect(s.deadline == t0 + .seconds(10) + BannerSchedule.releaseGrace)
    }

    @Test func releaseKeepsALongerRemainder() {
        var s = BannerSchedule()
        s.post(.power(.charged), duration: .seconds(3), now: t0)
        s.setHeld(true, now: t0)
        s.setHeld(false, now: t0 + .seconds(5))
        #expect(s.deadline == t0 + .seconds(8))
    }

    @Test func aNonPreemptingPostNeverBuriesAnotherBanner() {
        // An external volume change must not replace the power banner that is up (it did, and the
        // charger notice was lost behind a volume HUD).
        var s = BannerSchedule()
        s.post(.power(.connected), duration: .seconds(3), now: t0)
        s.post(.level(.volume), duration: .seconds(1.6), now: t0 + .seconds(0.1), preempting: false)
        #expect(s.current == .power(.connected))
        #expect(s.deadline == t0 + .seconds(3))
        // It still shows when nothing else is up, and still extends its own kind.
        s.dismiss(nil)
        s.post(.level(.volume), duration: .seconds(1.6), now: t0 + .seconds(1), preempting: false)
        #expect(s.current == .level(.volume))
        s.post(.level(.volume), duration: .seconds(1.6), now: t0 + .seconds(2), preempting: false)
        #expect(s.deadline == t0 + .seconds(3.6))
        // A preempting post (a key press) replaces as before.
        s.post(.level(.brightness), duration: .seconds(1.6), now: t0 + .seconds(2))
        #expect(s.current == .level(.brightness))
    }

    @Test func postingWhileHeldWaitsForTheRelease() {
        var s = BannerSchedule()
        s.setHeld(true, now: t0)
        s.post(.level(.volume), duration: .seconds(1.6), now: t0)
        #expect(s.current == .level(.volume) && s.deadline == nil)
        s.post(.level(.volume), duration: .seconds(2), now: t0 + .seconds(1))
        s.setHeld(false, now: t0 + .seconds(3))
        #expect(s.deadline == t0 + .seconds(5))
    }
}

@Suite struct BannerCenterTests {
    @Test func autoDismissesAndReportsExpiry() async throws {
        let center = BannerCenter()
        var expired: [BannerKind] = []
        center.onExpire = { expired.append($0) }
        center.post(.level(.volume), duration: 0.05)
        #expect(center.current == .level(.volume))
        // Waited for in turns of the main actor, not in wall-clock time: with every suite on the
        // main actor at once, 10 s passed before the expiry's turn came (and the wait gave up).
        for _ in 0..<1000 where center.current != nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(center.current == nil)
        #expect(expired == [.level(.volume)])
    }

    @Test func replacingCancelsTheOldDeadline() async throws {
        let center = BannerCenter()
        center.post(.level(.volume), duration: 0.05)
        center.post(.power(.connected), duration: 5)
        try await Task.sleep(for: .milliseconds(300))
        #expect(center.current == .power(.connected))
    }

    @Test func dismissIsNotAnExpiry() async throws {
        let center = BannerCenter()
        var expired: [BannerKind] = []
        center.onExpire = { expired.append($0) }
        center.post(.timerFinished, duration: 0.05)
        center.dismiss()
        try await Task.sleep(for: .milliseconds(300))
        #expect(center.current == nil)
        #expect(expired.isEmpty)
    }

    @Test func nonPreemptingPostIsDroppedWhileAnotherBannerShows() {
        let center = BannerCenter()
        center.post(.power(.connected), duration: 5)
        center.post(.level(.volume), duration: 1.6, preempting: false)
        #expect(center.current == .power(.connected))
        center.dismiss()
    }

    @Test func holdingKeepsTheBanner() async throws {
        let center = BannerCenter()
        center.post(.level(.brightness), duration: 0.05)
        center.isHeld = true
        try await Task.sleep(for: .milliseconds(300))
        #expect(center.current == .level(.brightness))
        center.isHeld = false
        #expect(center.current == .level(.brightness))
    }
}

// MARK: - Motion

@Suite struct MotionTests {
    @Test func opensClosesMorphsAndSwapsContent() {
        #expect(Motion.animation(from: .idle, to: .expanded(.home), reduceMotion: false) == Motion.open)
        #expect(Motion.animation(from: .banner(.dropTarget), to: .expanded(.shelf), reduceMotion: false) == Motion.open)
        #expect(Motion.animation(from: .expanded(.home), to: .compact(.nowPlaying), reduceMotion: false) == Motion.close)
        #expect(Motion.animation(from: .expanded(.timer), to: .idle, reduceMotion: false) == Motion.close)
        #expect(Motion.animation(from: .expanded(.home), to: .expanded(.shelf), reduceMotion: false) == Motion.content)
        #expect(Motion.animation(from: .idle, to: .compact(.timer), reduceMotion: false) == Motion.morph)
        #expect(Motion.animation(from: .compact(.timer), to: .banner(.level(.volume)), reduceMotion: false) == Motion.morph)
        #expect(Motion.animation(from: .banner(.timerFinished), to: .idle, reduceMotion: false) == Motion.morph)
    }

    @Test func reduceMotionAlwaysFades() {
        let pairs: [(IslandPresentation, IslandPresentation)] = [
            (.idle, .expanded(.home)), (.expanded(.home), .idle), (.compact(.timer), .banner(.timerFinished)),
            (.expanded(.home), .expanded(.timer)),
        ]
        for (from, to) in pairs {
            #expect(Motion.animation(from: from, to: to, reduceMotion: true) == Motion.reduced)
        }
    }

    /// The largest move the island makes: idle notch → expanded at the large scale.
    static var largestTravel: (perSide: Double, height: Double) {
        let layout = IslandLayout(notch: CGSize(width: 156, height: 28), scale: .large)
        let expanded = layout.size(for: .expanded(.home))
        return ((expanded.width - 156) / 2, expanded.height - 28)
    }

    /// Both ends of the user's animation-length range and the default.
    static let durations = [Motion.durationRange.lowerBound, Motion.defaultDuration, Motion.durationRange.upperBound]

    static func springs(_ duration: Double) -> [Spring] {
        [Motion.openSpring(duration: duration), Motion.closeSpring(duration: duration), Motion.morphSpring(duration: duration)]
    }

    @Test func animationLengthFollowsThePreference() {
        #expect(Motion.animation(from: .idle, to: .expanded(.home), reduceMotion: false, duration: 1.0)
            == .lean(Motion.openSpring(duration: 1.0)))
        #expect(Motion.animation(from: .expanded(.home), to: .idle, reduceMotion: false, duration: 1.0)
            == .lean(Motion.closeSpring(duration: 1.0)))
        #expect(Motion.animation(from: .idle, to: .expanded(.home), reduceMotion: true, duration: 1.0) == Motion.reduced)
    }

    /// The lean spring ends long before SwiftUI's own (which ran a 0.3 s close for 1.4 s), yet only
    /// once what is left of the move is below a point on every edge — and about when
    /// the window shrinks to its resting frame (the resting margin absorbs the last fraction).
    @Test func leanSpringsEndOnceSettled() {
        let travel = max(Self.largestTravel.perSide * 2, Self.largestTravel.height)
        for duration in Self.durations {
            for spring in Self.springs(duration) {
                let end = spring.settlingDuration(target: travel, epsilon: travel * LeanSpring.settledFraction)
                #expect(end < Motion.settleDuration(for: duration) + 0.05, "\(spring) ends at \(end)")
                // The spring moves every component alike, so each edge is left with its own share:
                // half the width change per side, the whole height change at the bottom.
                #expect(max(Self.largestTravel.perSide, Self.largestTravel.height) * LeanSpring.settledFraction < 1)
            }
        }
    }

    @Test func settleLeavesLessThanAPointOfMotion() {
        let travel = max(Self.largestTravel.perSide * 2, Self.largestTravel.height)
        for duration in Self.durations {
            for spring in Self.springs(duration) {
                let residual = abs(1 - spring.value(target: 1.0, time: Motion.settleDuration(for: duration)))
                #expect(residual * travel < 1)
            }
        }
    }

    @Test func stageMarginContainsTheOvershoot() {
        let travel = max(Self.largestTravel.perSide, Self.largestTravel.height)
        for duration in Self.durations {
            for spring in Self.springs(duration) {
                let peak = stride(from: 0.0, through: Motion.settleDuration(for: duration), by: 1.0 / 240)
                    .map { spring.value(target: 1.0, time: $0) - 1 }
                    .max() ?? 0
                #expect(peak * travel < Double(IslandLayout.stageMargin))
            }
        }
    }
}

// MARK: - Model & policy

@Suite struct IslandModelTests {
    @Test func applyBracketsTheChangeWithTheHooks() {
        let model = IslandModel()
        var log: [String] = []
        model.willTransition = { from, to in
            log.append("will \(from.contentKey)→\(to.contentKey) seen \(model.presentation.contentKey)")
        }
        model.didTransition = { from, to in
            log.append("did \(from.contentKey)→\(to.contentKey) seen \(model.presentation.contentKey)")
        }
        model.apply(.compact(.timer), animation: Motion.morph)
        #expect(log == [
            "will idle→compact.timer seen idle",
            "did idle→compact.timer seen compact.timer",
        ])
        model.apply(.compact(.timer), animation: nil)
        #expect(log.count == 2)
    }

    @Test func aTransitionRequestedFromAHookRunsAfterItNotInsideIt() async throws {
        let model = IslandModel()
        var log: [String] = []
        model.willTransition = { from, to in
            log.append("will \(from.contentKey)→\(to.contentKey)")
            // A hook that ends up asking for another presentation (twice: the latest wins).
            if to == .compact(.timer) {
                model.apply(.expanded(.shelf), animation: nil)
                model.apply(.expanded(.home), animation: nil)
            }
        }
        model.didTransition = { from, to in log.append("did \(from.contentKey)→\(to.contentKey)") }
        model.apply(.compact(.timer), animation: nil)
        // The first transition finished untouched, its hooks strictly bracketed.
        #expect(model.presentation == .compact(.timer))
        #expect(log == ["will idle→compact.timer", "did idle→compact.timer"])
        for _ in 0..<50 where model.presentation != .expanded(.home) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.presentation == .expanded(.home))
        #expect(log.suffix(2) == ["will compact.timer→expanded.home", "did compact.timer→expanded.home"])
    }

    @Test func aDirectRequestSupersedesADeferredOne() async throws {
        let model = IslandModel()
        model.willTransition = { _, to in
            if to == .compact(.timer) { model.apply(.expanded(.shelf), animation: nil) }
        }
        model.apply(.compact(.timer), animation: nil)
        // Newer than the deferred request, so the deferred one must not undo it.
        model.apply(.idle, animation: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.presentation == .idle)
    }

    @Test func hoveringIsSetThroughTheSetter() {
        let model = IslandModel()
        model.setHovering(true)
        #expect(model.isHovering)
        model.setHovering(false)
        #expect(!model.isHovering)
    }
}

@Suite struct AutoClosePolicyTests {
    @Test func onlyAnExpandedIslandCloses() {
        #expect(AutoCloseDecision.decide(AutoCloseInputs(pointerHasVisited: true)) == .notApplicable)
    }

    @Test func anyReasonToStayKeepsItOpen() {
        let reasons: [WritableKeyPath<AutoCloseInputs, Bool>] = [
            \.isPinned, \.isInteracting, \.isMenuOpen, \.isDropTargeted, \.isLingeringAfterDrop, \.isPointerInside,
        ]
        for reason in reasons {
            var inputs = AutoCloseInputs(isExpanded: true, pointerHasVisited: true)
            inputs[keyPath: reason] = true
            #expect(AutoCloseDecision.decide(inputs) == .keepOpen)
        }
    }

    @Test func leavingAfterAVisitUsesTheGraceElseTheTimeout() {
        #expect(AutoCloseDecision.decide(AutoCloseInputs(isExpanded: true, pointerHasVisited: true)) == .closeAfterGrace)
        #expect(AutoCloseDecision.decide(AutoCloseInputs(isExpanded: true, pointerHasVisited: false)) == .closeIfNeverVisited)
    }

    @Test func policyTimings() {
        #expect(IslandController.closeGrace == Preferences.defaultCloseDelay)
        #expect(IslandController.unvisitedTimeout == 6)
        #expect(IslandController.dropLinger == 1.5)
        #expect(IslandController.dragEndClearDelay == 0.45)
    }

    @Test func bannerHoldFollowsTheDragAndThePointerOverABanner() {
        // Nothing showing: never held, whatever else is true.
        #expect(!BannerHold.isHeld(hasBanner: false, isBannerShowing: false, isPointerInside: true, isInteracting: true))
        // The pointer holds a banner it is over, not one behind the expanded panel.
        #expect(BannerHold.isHeld(hasBanner: true, isBannerShowing: true, isPointerInside: true, isInteracting: false))
        #expect(!BannerHold.isHeld(hasBanner: true, isBannerShowing: false, isPointerInside: true, isInteracting: false))
        // A drag holds whatever is current; once it and the pointer are gone, the banner runs out.
        #expect(BannerHold.isHeld(hasBanner: true, isBannerShowing: false, isPointerInside: false, isInteracting: true))
        #expect(!BannerHold.isHeld(hasBanner: true, isBannerShowing: true, isPointerInside: false, isInteracting: false))
    }

    @Test func bannersWithControlsAreInteractive() {
        #expect(BannerKind.level(.volume).isInteractive)
        #expect(BannerKind.timerFinished.isInteractive)
        #expect(!BannerKind.power(.connected).isInteractive)
        #expect(!BannerKind.dropTarget.isInteractive)
    }

    @Test func pointerSlackIsTwoPoints() {
        let region = CGRect(x: 100, y: 100, width: 200, height: 50)
        #expect(PointerMonitor.contains(CGPoint(x: 150, y: 120), in: region))
        #expect(PointerMonitor.contains(CGPoint(x: 99, y: 151), in: region))
        #expect(!PointerMonitor.contains(CGPoint(x: 97, y: 120), in: region))
        #expect(!PointerMonitor.contains(CGPoint(x: 150, y: 153), in: region))
        #expect(!PointerMonitor.contains(CGPoint(x: 150, y: 97), in: region))
        #expect(!PointerMonitor.contains(CGPoint(x: 150, y: 120), in: .null))
    }
}

@Suite struct DelayedActionTests {
    @Test func reschedulingReplacesAndCancelPrevents() async throws {
        let action = DelayedAction()
        var fired: [Int] = []
        action.schedule(after: 0.02) { fired.append(1) }
        action.schedule(after: 0.04) { fired.append(2) }
        #expect(action.isPending)
        // Waited for rather than slept on (the main actor may be busy with other suites).
        let deadline = Date.now.addingTimeInterval(10)
        while action.isPending, Date.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(fired == [2])
        #expect(!action.isPending)
        action.schedule(after: 0.02) { fired.append(3) }
        action.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(fired == [2])
    }
}

/// Synchronous only: `AppModel.shared` is process-wide, and a test without
/// suspension points cannot interleave with other main-actor tests.
@Suite struct IslandControllerTests {
    @Test func expandPinAndCollapse() {
        let model = AppModel.shared
        let controller = model.controller!
        controller.expand(page: .timer, userInitiated: false)
        #expect(model.island.presentation == .expanded(.timer))
        #expect(!model.island.isPinned)
        controller.togglePinned()
        #expect(model.island.isPinned)
        #expect(model.island.presentation == .expanded(.timer))
        // A click inside the expanded island never toggles the pin.
        controller.clicked()
        #expect(model.island.isPinned)
        controller.collapse()
        #expect(model.island.presentation == .idle)
        #expect(!model.island.isPinned)
    }

    @Test func collapseClosesTheAssistant() {
        let model = AppModel.shared
        let controller = model.controller!
        controller.openAssistant()
        #expect(model.island.presentation.isAssistant)
        // `close` from a URL or the menu: the assistant must not stay on screen.
        controller.collapse()
        #expect(model.island.presentation == .idle)
    }

    @Test func pinningAClosedIslandOpensIt() {
        let model = AppModel.shared
        let controller = model.controller!
        controller.togglePinned()
        #expect(model.island.presentation.isExpanded)
        #expect(model.island.isPinned)
        controller.togglePinned()
        #expect(!model.island.isPinned)
        controller.collapse()
        #expect(model.island.presentation == .idle)
    }
}

// MARK: - Hover region

@MainActor @Suite struct HoverRegionTests {
    /// The stage rect comes with AppKit's bottom-left origin; the hosting view is flipped. A compact
    /// pill resting in a 10-pt margin must be hovered at the top of the stage, not 10 pt lower.
    @Test func regionIsConvertedIntoTheFlippedHostingView() {
        let view = IslandHostingView(rootView: EmptyView())
        view.frame = CGRect(x: 0, y: 0, width: 260, height: 38)
        #expect(view.isFlipped)
        view.islandRect = CGRect(x: 10, y: 0, width: 240, height: 28)
        #expect(view.region == CGRect(x: 10, y: 10, width: 240, height: 28))
        view.islandRect = CGRect(x: 10, y: 10, width: 240, height: 28)
        #expect(view.region == CGRect(x: 10, y: 0, width: 240, height: 28))
    }
}

// MARK: - MacBook display profiles

@Suite struct DisplayProfileTests {
    private func metrics(points: CGSize, panel: CGSize, builtin: Bool = true) -> NotchMetrics {
        NotchMetrics.derive(displayID: 1, screenFrame: CGRect(origin: .zero, size: points), safeAreaTop: 32,
                            auxiliaryTopLeftWidth: (points.width - 185) / 2, auxiliaryTopRightWidth: (points.width - 185) / 2,
                            menuBarThickness: 24, physicalSize: panel, isBuiltin: builtin)
    }

    @Test func eachNotchedMacBookIsRecognised() {
        for profile in DisplayProfile.allCases {
            #expect(DisplayProfile.matching(physicalSize: profile.panelSize, isBuiltin: true) == profile)
        }
        // CGDisplayScreenSize on the reference 13.6-inch Air.
        #expect(DisplayProfile.matching(physicalSize: CGSize(width: 290.29, height: 188.69), isBuiltin: true) == .air13)
    }

    @Test func otherScreensAreLeftAlone() {
        // An external 27-inch display, and a MacBook-sized panel that is not built in.
        #expect(DisplayProfile.factor(for: metrics(points: CGSize(width: 2560, height: 1440), panel: CGSize(width: 597, height: 336), builtin: false)) == 1)
        #expect(DisplayProfile.factor(for: metrics(points: CGSize(width: 1512, height: 982), panel: DisplayProfile.pro14.panelSize, builtin: false)) == 1)
        #expect(DisplayProfile.factor(for: nil) == 1)
    }

    @Test func theReferenceMacKeepsItsSize() {
        #expect(DisplayProfile.factor(for: metrics(points: CGSize(width: 1280, height: 832), panel: DisplayProfile.air13.panelSize)) == 1)
    }

    @Test func largerDensitiesDrawTheIslandLarger() {
        // 14-inch Pro at 1512 × 982: 5.0 pt/mm against the reference's 4.41.
        let pro14 = DisplayProfile.factor(for: metrics(points: CGSize(width: 1512, height: 982), panel: DisplayProfile.pro14.panelSize))
        #expect(abs(pro14 - 1.134) < 0.005)
        let pro16 = DisplayProfile.factor(for: metrics(points: CGSize(width: 1728, height: 1117), panel: DisplayProfile.pro16.panelSize))
        #expect(abs(pro16 - 1.134) < 0.005)
        let air15 = DisplayProfile.factor(for: metrics(points: CGSize(width: 1710, height: 1112), panel: DisplayProfile.air15.panelSize))
        #expect(abs(air15 - 1.188) < 0.005)
    }

    @Test func settingsTakesTheReferenceShareOfAKnownMacBook() {
        let notch = CGSize(width: 185, height: 32)
        var pro14 = IslandLayout(notch: notch, scale: .standard, screen: CGSize(width: 1512, height: 982))
        // Elsewhere: at most 1180 × 740, as before.
        #expect(pro14.size(for: .settings) == CGSize(width: 1180, height: 32 + 740))
        pro14.settingsFillsLikeReference = true
        // 92 % of the width and 89 % of the height, as 1180 × 740 is of 1280 × 832.
        #expect(pro14.size(for: .settings) == CGSize(width: 1394, height: 32 + 873))
        // The reference Mac itself is unchanged.
        var air13 = IslandLayout(notch: CGSize(width: 156, height: 28), scale: .standard, screen: CGSize(width: 1280, height: 832))
        let before = air13.size(for: .settings)
        air13.settingsFillsLikeReference = true
        #expect(air13.size(for: .settings) == before)
    }

    @Test func theFactorScalesTheOpenPanelOnly() {
        let notch = CGSize(width: 185, height: 32)
        let plain = IslandLayout(notch: notch, scale: .standard, screen: CGSize(width: 1512, height: 982))
        var scaled = plain
        scaled.display = 1.134
        #expect(scaled.size(for: .compact(.nowPlaying)) == plain.size(for: .compact(.nowPlaying)))
        // The pitch (a cell and its gap) larger by the factor, the insets as they are.
        let pitch = (48 * 1.134).rounded()
        #expect(abs(scaled.size(for: .expanded(.home)).width - (12 * pitch - 8 + 36)) < 0.01)
        #expect(abs(scaled.size(for: .expanded(.home)).height - (32 + 3 * pitch - 8 + 16)) < 0.01)
    }
}

@Suite struct GalleryIconSizeTests {
    @Test func mediumIsTheGalleryAsItWas() {
        #expect(IslandLayout.galleryCellHeight(icon: SiriGalleryIconSize.medium.points) == IslandLayout.galleryCellHeight)
        #expect(abs(IslandLayout.galleryColumnWidth(icon: 48) * 9 - IslandLayout.assistantGalleryWidth) < 1)
    }

    @Test func largerIconsGrowTheCellsAndTheWindow() {
        let notch = CGSize(width: 156, height: 28)
        var layout = IslandLayout(notch: notch, scale: .standard, screen: CGSize(width: 1280, height: 832))
        let medium = layout.size(for: .assistant(.gallery))
        layout.siri.galleryIcon = SiriGalleryIconSize.large.points
        let large = layout.size(for: .assistant(.gallery))
        // Four rows of 12 pt taller cells, nine columns of 12 pt wider ones.
        #expect(abs(large.height - medium.height - 4 * 12) < 1)
        #expect(abs(large.width - medium.width - 9 * 12) < 1)
    }
}
