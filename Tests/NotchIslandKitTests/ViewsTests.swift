import AppKit
import SwiftUI
import Testing
@testable import NotchIslandKit

// MARK: - IslandShape

@Suite("IslandShape")
struct IslandShapeTests {
    let rect = CGRect(x: 0, y: 0, width: 600, height: 212)

    @Test func pathStaysInsideItsRect() {
        for (bottom, shoulder, top) in [(30.0, 10.0, 24.0), (0, 0, 0), (500, 500, 24), (14, 6, 0)] {
            let path = IslandShape(bottomRadius: bottom, shoulderRadius: shoulder, topInset: top).path(in: rect)
            let bounds = path.boundingRect
            #expect(bounds.minX >= rect.minX - 0.001 && bounds.maxX <= rect.maxX + 0.001)
            #expect(bounds.minY >= rect.minY - 0.001 && bounds.maxY <= rect.maxY + 0.001)
        }
    }

    @Test func topIsFlushAcrossTheFullWidth() {
        let path = IslandShape(bottomRadius: 30, shoulderRadius: 10, topInset: 24).path(in: rect)
        // The overdraw strip is full width: both top corners are inside.
        #expect(path.contains(CGPoint(x: 0.5, y: 0.5)))
        #expect(path.contains(CGPoint(x: rect.maxX - 0.5, y: 0.5)))
        #expect(path.contains(CGPoint(x: 0.5, y: 23.5)))
    }

    @Test func shouldersAreConcave() {
        let shape = IslandShape(bottomRadius: 30, shoulderRadius: 10, topInset: 24)
        let path = shape.path(in: rect)
        // Just below the visible top edge, beside the body, is outside (the shoulder curves inward)…
        #expect(!path.contains(CGPoint(x: 1, y: 24 + 9)))
        // …while the body itself is inside.
        #expect(path.contains(CGPoint(x: 11, y: 24 + 12)))
        #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY)))
    }

    @Test func bottomCornersAreRounded() {
        let path = IslandShape(bottomRadius: 30, shoulderRadius: 10).path(in: rect)
        // The body's bottom-left corner point is cut away by the curve.
        #expect(!path.contains(CGPoint(x: 11, y: rect.maxY - 1)))
        #expect(path.contains(CGPoint(x: rect.midX, y: rect.maxY - 1)))
    }

    @Test func geometryClampsRadii() {
        let small = CGRect(x: 0, y: 0, width: 100, height: 28)
        let g = IslandShapeGeometry(rect: small, bottomRadius: 400, shoulderRadius: 400, topInset: 0)
        #expect(g.shoulder <= small.width / 4)
        #expect(g.shoulder <= small.height / 2)
        #expect(g.radius * IslandShapeGeometry.continuousExtent <= (small.width - 2 * g.shoulder) / 2 + 0.001)
        #expect(g.radius * IslandShapeGeometry.continuousExtent <= small.height - g.shoulder + 0.001)

        let negative = IslandShapeGeometry(rect: small, bottomRadius: -5, shoulderRadius: -5, topInset: -5)
        #expect(negative.radius == 0 && negative.shoulder == 0 && negative.top == 0)
    }

    @Test func emptyRectMakesEmptyPath() {
        #expect(IslandShape(bottomRadius: 10, shoulderRadius: 6).path(in: .zero).isEmpty)
    }

    @Test func animatesRadiiOnly() {
        var shape = IslandShape(bottomRadius: 14, shoulderRadius: 6, topInset: 24)
        #expect(shape.animatableData == AnimatablePair(14, 6))
        shape.animatableData = AnimatablePair(30, 10)
        #expect(shape.bottomRadius == 30 && shape.shoulderRadius == 10 && shape.topInset == 24)
    }

    @Test func reportsFlatTopAndRoundBottomForConcentricChildren() {
        let corners = IslandShape(bottomRadius: 30, shoulderRadius: 10).corners(in: nil)
        #expect(corners == RoundedRectangularShapeCorners(topLeading: 0, topTrailing: 0, bottomLeading: .fixed(30), bottomTrailing: .fixed(30)))
        let inset = IslandShape(bottomRadius: 30, shoulderRadius: 10).inset(by: 8).corners(in: nil)
        #expect(inset == RoundedRectangularShapeCorners(topLeading: 0, topTrailing: 0, bottomLeading: .fixed(22), bottomTrailing: .fixed(22)))
    }
}

// MARK: - Notch split

@Suite("NotchSplit")
struct NotchSplitTests {
    /// Spec geometry for the three non-idle presentations (standard scale).
    static func frames(notch n: CGSize) -> [(width: CGFloat, shoulder: CGFloat)] {
        let ear = n.height + 14
        return [
            (n.width + 2 * ear, 6),
            (max(n.width + 2 * ear, 380), 8),
            (max(n.width + 380, 600), 10),
        ]
    }

    @Test(arguments: [CGSize(width: 156, height: 28), CGSize(width: 185, height: 32), CGSize(width: 180, height: 24)])
    func earsNeverReachTheNotch(notch: CGSize) {
        for frame in Self.frames(notch: notch) {
            for clearance in [Metrics.Compact.notchClearance, Metrics.notchClearance] {
                let split = NotchSplit(
                    islandWidth: frame.width, notchWidth: notch.width, shoulder: frame.shoulder,
                    outerInset: Metrics.Compact.inset, clearance: clearance
                )
                #expect(split.leadingEar.upperBound <= split.notchGap.lowerBound - clearance + 0.001)
                #expect(split.trailingEar.lowerBound >= split.notchGap.upperBound + clearance - 0.001)
                #expect(split.leadingEar.lowerBound >= frame.shoulder)
                #expect(split.trailingEar.upperBound <= frame.width - frame.shoulder)
                // The band's pieces add up to exactly the island width.
                let total = 2 * split.contentInset + 2 * split.earWidth + split.gapWidth
                #expect(abs(total - frame.width) < 0.001)
            }
        }
    }

    @Test func earWidthNeverNegative() {
        let split = NotchSplit(islandWidth: 150, notchWidth: 156, shoulder: 6, outerInset: 4, clearance: 4)
        #expect(split.earWidth == 0)
        #expect(Metrics.earWidth(islandWidth: 100, notchWidth: 156, shoulder: 6) == 0)
        #expect(Metrics.earWidth(islandWidth: 240, notchWidth: 156, shoulder: 6) == 36)
    }
}

// MARK: - Formatting

@Suite("IslandFormat")
struct IslandFormatTests {
    @Test func clockShowsHoursOnlyWhenNeeded() {
        let short = IslandFormat.clock(65)
        #expect(short.hasPrefix("1") && short.hasSuffix("05") && short.count == 4)
        let zero = IslandFormat.clock(0)
        #expect(zero.hasPrefix("0") && zero.hasSuffix("00"))
        let long = IslandFormat.clock(3723)
        #expect(long.hasPrefix("1") && long.hasSuffix("03") && long.count == 7)
        #expect(IslandFormat.clock(-5) == zero)
        #expect(IslandFormat.clock(.nan) == zero)
    }

    @Test func percentClamps() {
        #expect(IslandFormat.percent(0.62).contains("62"))
        #expect(IslandFormat.percent(1.7).contains("100"))
        #expect(IslandFormat.percentValue(0.625) == 63)
        #expect(IslandFormat.percentValue(-1) == 0)
    }

    @Test func batterySymbols() {
        #expect(IslandFormat.batterySymbol(level: 5, charging: false) == "battery.0percent")
        #expect(IslandFormat.batterySymbol(level: 25, charging: false) == "battery.25percent")
        #expect(IslandFormat.batterySymbol(level: 50, charging: false) == "battery.50percent")
        #expect(IslandFormat.batterySymbol(level: 76, charging: false) == "battery.75percent")
        #expect(IslandFormat.batterySymbol(level: 95, charging: false) == "battery.100percent")
        #expect(IslandFormat.batterySymbol(level: 30, charging: true) == "battery.100percent.bolt")
    }

    @Test func levelSymbolsFollowKindAndValue() {
        let at: (Double, Bool) -> LevelReading = { LevelReading(value: $0, isMuted: $1, isAvailable: true) }
        #expect(IslandFormat.levelSymbol(.volume, reading: at(0.6, true)) == "speaker.slash.fill")
        #expect(IslandFormat.levelSymbol(.volume, reading: at(0, false)) == "speaker.slash.fill")
        #expect(IslandFormat.levelSymbol(.volume, reading: at(0.2, false)) == "speaker.wave.1.fill")
        #expect(IslandFormat.levelSymbol(.volume, reading: at(0.5, false)) == "speaker.wave.2.fill")
        #expect(IslandFormat.levelSymbol(.volume, reading: at(0.9, false)) == "speaker.wave.3.fill")
        #expect(IslandFormat.levelSymbol(.brightness, reading: at(0.2, false)) == "sun.min.fill")
        #expect(IslandFormat.levelSymbol(.brightness, reading: at(0.8, false)) == "sun.max.fill")
    }

    @Test func allSymbolsExist() {
        let names = [
            "battery.0percent", "battery.25percent", "battery.50percent", "battery.75percent",
            "battery.100percent", "battery.100percent.bolt", "powerplug.fill", "speaker.slash.fill",
            "speaker.wave.1.fill", "speaker.wave.2.fill", "speaker.wave.3.fill", "speaker.fill",
            "sun.min.fill", "sun.max.fill", "bell.fill", "tray.and.arrow.down.fill", "tray.and.arrow.down",
            "timer", "stopwatch", "pause.fill", "play.fill", "backward.fill", "forward.fill", "pin", "pin.fill",
            "gearshape", "dot.radiowaves.up.forward", "square.and.arrow.up", "music.note", "tray.full.fill",
        ]
        for name in names {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "missing symbol \(name)")
        }
    }
}

@Suite("PowerCopy")
struct PowerCopyTests {
    func state(_ level: Int, charging: Bool = false, plugged: Bool = false, minutes: Int? = nil, lowPower: Bool = false) -> PowerState {
        PowerState(hasBattery: true, level: level, isCharging: charging, isPluggedIn: plugged || charging,
                   isCharged: level == 100, minutesRemaining: minutes, isLowPowerMode: lowPower)
    }

    @Test func pluggedInButHeldIsNotCharging() {
        let copy = PowerCopy(event: .connected, state: state(80, plugged: true))
        #expect(copy.title == "Plugged In")
        #expect(copy.systemImage == "powerplug.fill")
        #expect(copy.tint == .none)
    }

    @Test func chargingShowsTimeToFullAndGreen() {
        let copy = PowerCopy(event: .connected, state: state(76, charging: true, minutes: 72))
        #expect(copy.title == "Charging")
        #expect(copy.tint == .charging)
        #expect(!copy.detail.isEmpty)
        #expect(PowerCopy(event: .connected, state: state(76, charging: true)).detail.isEmpty)
    }

    @Test func lowIsRedAndAlwaysSaysSomething() {
        let copy = PowerCopy(event: .low(threshold: 10), state: state(10))
        #expect(copy.title == "Low Battery")
        #expect(copy.tint == .low)
        #expect(!copy.detail.isEmpty)
        #expect(copy.systemImage == "battery.0percent")
    }

    @Test func onBatteryInLowPowerModeIsOrange() {
        #expect(PowerCopy(event: .disconnected, state: state(60, lowPower: true)).tint == .lowPower)
        #expect(PowerCopy(event: .disconnected, state: state(60)).tint == .none)
    }

    @Test func percentIsNotRepeatedInTheDetail() {
        let copy = PowerCopy(event: .disconnected, state: state(76, minutes: 320))
        #expect(!copy.detail.contains("76"))
    }

    @Test func glyphTint() {
        #expect(state(50, charging: true).tint == .charging)
        #expect(state(8).tint == .low)
        #expect(state(50, lowPower: true).tint == .lowPower)
        #expect(state(50).tint == .none)
    }
}

// MARK: - Equalizer

@Suite("Equalizer")
struct EqualizerTests {
    @Test func barsAreStaggered() {
        let bars = EqualizerBarsView.bars
        #expect(bars.count == 4)
        #expect(Set(bars.map(\.period)).count == bars.count)
        #expect(Set(bars.map(\.phase)).count == bars.count)
        #expect(bars.allSatisfy { $0.low > 0 && $0.low < $0.high && $0.high <= 1 })
    }

    @Test func animationsInstallOnceAndSurviveLayout() {
        let view = EqualizerBarsView(frame: CGRect(origin: .zero, size: Metrics.Compact.equalizerSize))
        #expect(view.installedAnimations.allSatisfy { $0 == nil })

        view.isAnimating = true
        let installed = view.installedAnimations.compactMap { $0 }
        #expect(installed.count == 4)
        #expect(installed.allSatisfy { $0.repeatCount == .infinity && $0.autoreverses })

        // Layout (e.g. the island resizing) must not restart the animations.
        view.frame.size = CGSize(width: 20, height: 14)
        view.layout()
        view.isAnimating = true
        for (before, after) in zip(installed, view.installedAnimations) {
            #expect(after === before)
        }

        view.isAnimating = false
        #expect(view.installedAnimations.allSatisfy { $0 == nil })
    }
}

// MARK: - Tokens and keys

@Suite("Tokens")
struct TokenTests {
    @Test func hitTargetSurvivesEightBitAlpha() {
        // Anything below 1/255 quantises to a fully transparent pixel, which the window server
        // passes through (verified by capturing the window: 0.001 → alpha 0).
        #expect(Metrics.hitTargetOpacity >= 1.0 / 255.0)
        #expect(Metrics.hitTargetOpacity < 0.01)
    }

    @Test func controlSizeFollowsScale() {
        #expect(Metrics.controlSize(forScale: 0.9) == .small)
        #expect(Metrics.controlSize(forScale: 1.0) == .regular)
        #expect(Metrics.controlSize(forScale: 1.15) == .large)
    }

    @Test func expandedPagesShareOneSurface() {
        #expect(IslandPresentation.expanded(.home).surfaceKey == IslandPresentation.expanded(.timer).surfaceKey)
        #expect(IslandPresentation.compact(.timer).surfaceKey != IslandPresentation.compact(.nowPlaying).surfaceKey)
        #expect(IslandPresentation.banner(.power(.connected)).surfaceKey == IslandPresentation.banner(.power(.charged)).surfaceKey)
    }
}

// MARK: - Glass controls

@Suite("Glass controls")
struct GlassControlTests {
    @Test func controlHeightsGrowWithSize() {
        let heights = [ControlSize.mini, .small, .regular, .large, .extraLarge].map(Metrics.Control.height)
        #expect(heights == heights.sorted())
        #expect(Set(heights).count == heights.count)
    }

    @Test(arguments: [CGFloat(24), 32, 38])
    func headerControlsLeaveAirInTheBand(band: CGFloat) {
        #expect(band - Metrics.Control.height(Metrics.Control.size(fittingBand: band)) >= 4)
    }

    @Test func primaryIsLargerAndSecondaryNeverTiny() {
        for size in [ControlSize.small, .regular, .large] {
            #expect(Metrics.Control.height(Metrics.Control.larger(size)) > Metrics.Control.height(size))
            #expect(Metrics.Control.height(Metrics.Control.smaller(size)) >= Metrics.Control.height(.small))
        }
    }

    @Test func thumbInsetLeavesAThumb() {
        for size in [ControlSize.mini, .small, .regular, .large] {
            let inset = Metrics.Control.segmentInset(size)
            #expect(inset >= 2)
            #expect(Metrics.Control.height(size) - 2 * inset >= 16)
        }
    }
}

@Suite("Liquid segment geometry")
struct SegmentGeometryTests {
    /// Three 30-pt segments side by side, 20 pt tall.
    let geometry = SegmentGeometry(frames: [
        0: CGRect(x: 0, y: 0, width: 30, height: 20),
        1: CGRect(x: 30, y: 0, width: 30, height: 20),
        2: CGRect(x: 60, y: 0, width: 30, height: 20),
    ])

    @Test func restsOnTheSelectedSegment() {
        #expect(geometry.thumbFrame(selected: 1, dragCentre: nil) == CGRect(x: 30, y: 0, width: 30, height: 20))
        #expect(SegmentGeometry().thumbFrame(selected: 0, dragCentre: nil) == .zero)
    }

    @Test func followsThePointerOneToOneInsideTheTrack() {
        let frame = geometry.thumbFrame(selected: 0, dragCentre: 52)
        #expect(frame.midX == 52)
        #expect(frame.size == CGSize(width: 30, height: 20))
    }

    @Test func rubberBandsPastTheEnds() {
        let limit = Metrics.Control.rubberLimit
        let low: CGFloat = 15, high: CGFloat = 75
        var previous = low
        for pull in stride(from: CGFloat(1), through: 400, by: 13) {
            let x = geometry.rubberBand(low - pull, width: 30)
            #expect(x < previous)
            #expect(low - x < limit)
            previous = x
        }
        #expect(geometry.rubberBand(high + 1000, width: 30) - high < limit)
        #expect(geometry.rubberBand(40, width: 30) == 40)
    }

    @Test func landsOnTheNearestSegment() {
        #expect(geometry.nearestIndex(to: -50) == 0)
        #expect(geometry.nearestIndex(to: 44) == 1)
        #expect(geometry.nearestIndex(to: 76) == 2)
        #expect(geometry.nearestIndex(to: 900) == 2)
        #expect(SegmentGeometry().nearestIndex(to: 10) == nil)
    }
}

// MARK: - Thumbnails and rendering

@Suite("Rendering")
struct RenderingTests {
    @Test func thumbnailCacheFallsBackAndCaches() async {
        let cache = ThumbnailCache()
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).txt")
        let first = await cache.thumbnail(for: missing, side: 52, scale: 2)
        let second = await cache.thumbnail(for: missing, side: 52, scale: 2)
        #expect(first.isIcon)
        #expect(first.image === second.image)
    }

    @Test(arguments: [
        IslandPresentation.idle,
        .compact(.nowPlaying), .compact(.timer), .compact(.stopwatch),
        .banner(.level(.volume)), .banner(.level(.brightness)), .banner(.power(.connected)),
        .banner(.power(.low(threshold: 10))), .banner(.timerFinished), .banner(.dropTarget),
        .expanded(.home), .expanded(.shelf), .expanded(.timer),
    ])
    func everyPresentationRenders(_ presentation: IslandPresentation) {
        let model = AppModel()
        model.island.apply(presentation, animation: nil)
        let host = NSHostingView(rootView: IslandRootView().environment(model))
        host.frame = CGRect(x: 0, y: 0, width: 760, height: 260)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width.isFinite && host.fittingSize.height.isFinite)
    }
}

@Suite struct TickingClockTests {
    let anchor = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func countsUpRoundingDown() {
        #expect(TickingClock.value(at: anchor, anchor: anchor, countsDown: false) == 0)
        #expect(TickingClock.value(at: anchor.addingTimeInterval(59.999), anchor: anchor, countsDown: false) == 60)
        #expect(TickingClock.value(at: anchor.addingTimeInterval(61.5), anchor: anchor, countsDown: false) == 61)
        #expect(TickingClock.value(at: anchor.addingTimeInterval(-3), anchor: anchor, countsDown: false) == 0)
    }

    @Test func countsDownRoundingUp() {
        #expect(TickingClock.value(at: anchor.addingTimeInterval(-0.4), anchor: anchor, countsDown: true) == 1)
        #expect(TickingClock.value(at: anchor.addingTimeInterval(-60.001), anchor: anchor, countsDown: true) == 60)
        #expect(TickingClock.value(at: anchor.addingTimeInterval(-59.5), anchor: anchor, countsDown: true) == 60)
        #expect(TickingClock.value(at: anchor.addingTimeInterval(2), anchor: anchor, countsDown: true) == 0)
    }
}
