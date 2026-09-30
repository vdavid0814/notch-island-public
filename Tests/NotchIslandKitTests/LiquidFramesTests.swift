import CoreGraphics
import Foundation
import Testing
@testable import NotchIslandKit

// Off the main actor: tracing takes a while in a debug build, and timed tests wait on the main actor.
@Suite nonisolated struct LiquidFramesTests {
    // A 1280 × 832 screen with its notch; macOS's card where the desktop puts it.
    private let metrics = NotchMetrics.derive(displayID: 1, screenFrame: CGRect(x: 0, y: 0, width: 1280, height: 832),
                                              safeAreaTop: 28, auxiliaryTopLeftWidth: 562, auxiliaryTopRightWidth: 562,
                                              menuBarThickness: 24)
    private var window: CGRect {
        SystemVolumeCard.guess(fullscreenApps: 0, notch: metrics.notchRect, screen: metrics.screenFrame)
    }

    /// Every element's kind and the exact bits of its point.
    private static func bits(_ paths: [CGPath]) -> [[UInt64]] {
        paths.map { path in
            var values: [UInt64] = []
            path.applyWithBlock { element in
                values.append(UInt64(element.pointee.type.rawValue))
                if element.pointee.type != .closeSubpath {
                    values += [UInt64(element.pointee.points[0].x.bitPattern), UInt64(element.pointee.points[0].y.bitPattern)]
                }
            }
            return values
        }
    }

    private static func temporaryStore() -> LiquidFrames.Store {
        LiquidFrames.Store(root: FileManager.default.temporaryDirectory.appendingPathComponent("LiquidFrames-\(UUID().uuidString)"))
    }

    @Test func framesReadBackFromDiskAreTheFreshOnesBitForBit() throws {
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        #expect(LiquidCard.prewarmMoves(cards: [.volume, .airPods], towards: window, metrics: metrics).count == 4)
        for (key, move) in LiquidCard.prewarmMoves(cards: [.volume], towards: window, metrics: metrics) {
            // Worked out and kept, then worked out again (at another time): the same bits.
            let fresh = store.frames(move, key: key)
            #expect(fresh.count > 30)
            #expect(Self.bits(move.paths()) == Self.bits(fresh))
            #expect(FileManager.default.fileExists(atPath: store.file(for: key).path))
            let loaded = try #require(store.load(key))
            #expect(Self.bits(loaded) == Self.bits(fresh))
            #expect(Self.bits(store.frames(move, key: key)) == Self.bits(fresh))
        }
        #expect(LiquidFrames.decode(Data([1, 2, 3])) == nil)
    }

    @Test func theFileChangesWithEveryConstantThatShapesTheFrames() {
        let base = LiquidFrames.Recipe()
        var changed: [LiquidFrames.Recipe] = []
        var recipe = base
        recipe.smoothing += 1
        changed.append(recipe)
        recipe = base
        recipe.cell = 1
        changed.append(recipe)
        recipe = base
        recipe.curves[0].overshoot += 0.01
        changed.append(recipe)
        recipe = base
        recipe.curves[1].duration += 0.05
        changed.append(recipe)
        recipe = base
        recipe.overdraw += 1
        changed.append(recipe)
        recipe = base
        recipe.absorb += 0.1
        changed.append(recipe)
        recipe = base
        recipe.rate = 60
        changed.append(recipe)
        recipe = base
        recipe.build = "999@0.0"
        changed.append(recipe)
        let ids = Set(([base] + changed).map(\.id))
        #expect(ids.count == changed.count + 1)
        #expect(LiquidFrames.Recipe().id == base.id)

        let root = URL(fileURLWithPath: "/tmp/frames")
        let key = "out|volume|(0, 0, 1, 1)"
        #expect(LiquidFrames.Store(root: root).file(for: key) != LiquidFrames.Store(root: root, recipe: changed[0].id).file(for: key))
        #expect(LiquidFrames.Store(root: root).file(for: key) != LiquidFrames.Store(root: root).file(for: key + "x"))
    }

    @Test func aNewRecipeClearsTheFramesOfTheOldOne() throws {
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let (key, move) = try #require(LiquidCard.prewarmMoves(cards: [.volume], towards: window, metrics: metrics).first)
        _ = store.frames(move, key: key)
        var next = store
        next.recipe = "another"
        _ = next.frames(move, key: key)
        #expect(!FileManager.default.fileExists(atPath: store.file(for: key).path))
        #expect(FileManager.default.fileExists(atPath: next.file(for: key).path))
    }

    @Test func nothingIsWorkedOutAheadWhileNeitherCardFlows() {
        #expect(LiquidCard.flowingCards(volume: false, airPods: false).isEmpty)
        #expect(LiquidCard.flowingCards(volume: true, airPods: false) == [.volume])
        #expect(LiquidCard.flowingCards(volume: false, airPods: true) == [.airPods])
        #expect(LiquidCard.flowingCards(volume: true, airPods: true) == [.volume, .airPods])
        #expect(LiquidCard.prewarmMoves(cards: [], towards: window, metrics: metrics).isEmpty)
    }

    /// `NI_BENCH=1`: the four moves `prewarm` works out, traced and kept (a first launch) against
    /// read back (every launch after).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NI_BENCH"] == "1"))
    func benchmarkPrewarmColdAgainstCached() {
        let store = Self.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let moves = LiquidCard.prewarmMoves(cards: [.volume, .airPods], towards: window, metrics: metrics)
        let clock = ContinuousClock()
        let cold = clock.measure { for (key, move) in moves { _ = store.frames(move, key: key) } }
        var cached: [Duration] = []
        for _ in 0..<5 {
            cached.append(clock.measure { for (key, move) in moves { _ = store.frames(move, key: key) } })
        }
        let bytes = moves.compactMap { try? FileManager.default.attributesOfItem(atPath: store.file(for: $0.key).path)[.size] as? Int }
            .reduce(0, +)
        print("BENCH liquid prewarm: cold \(cold), cached \(cached.min()!) (best of 5), \(bytes / 1024) KB on disk for \(moves.count) moves")
    }
}
