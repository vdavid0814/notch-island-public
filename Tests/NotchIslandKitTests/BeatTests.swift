import CoreAudio
import Foundation
import Synchronization
import Testing
@testable import NotchIslandKit

/// The equalizer's beat, found in synthesized music run through the real analyser: a kick drum on
/// every beat, hi-hats on the eighths, a held chord and a little noise.
@Suite(.serialized) nonisolated struct BeatTests {
    final class Collector: SpectrumSink, @unchecked Sendable {
        let slices = Mutex<[OnsetSample]>([])
        func spectrumDidUpdate(_ batch: [SpectrumLevels], onsets: [OnsetSample], interval: CFTimeInterval) {
            slices.withLock { $0.append(contentsOf: onsets) }
        }
    }

    /// `seconds` of music at `bpm`, as the analyser hears it (48 kHz mono).
    static func music(bpm: Double, seconds: Double, hats: Bool = true, rate: Double = 48_000) -> [Float] {
        let count = Int(seconds * rate), beat = 60 / bpm
        var generator = Noise()
        return (0..<count).map { index in
            let t = Double(index) / rate
            let sinceBeat = t.truncatingRemainder(dividingBy: beat)
            let sinceEighth = t.truncatingRemainder(dividingBy: beat / 2)
            var x = 0.0
            // Kick: a falling sine, 90 → 50 Hz, ~120 ms.
            let kickFrequency = 50 + 40 * exp(-sinceBeat / 0.03)
            x += 0.8 * sin(2 * .pi * kickFrequency * sinceBeat) * exp(-sinceBeat / 0.12)
            if hats {
                x += 0.15 * Double.random(in: -1...1, using: &generator) * exp(-sinceEighth / 0.02)
            }
            // A held chord and some noise.
            x += 0.08 * (sin(2 * .pi * 220 * t) + sin(2 * .pi * 277 * t) + sin(2 * .pi * 330 * t))
            x += 0.01 * Double.random(in: -1...1, using: &generator)
            return Float(x)
        }
    }

    /// A cheap, repeatable noise source (a linear congruential generator).
    struct Noise: RandomNumberGenerator {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    static func slices(_ samples: [Float], rate: Double = 48_000) -> [OnsetSample] {
        let analyzer = SpectrumAnalyzer(sampleRate: rate)!
        analyzer.block = 2048
        let collector = Collector()
        AudioSpectrumTap.addSink(collector)
        defer { AudioSpectrumTap.removeSink(collector) }
        let frames = 8192
        var copy = samples
        copy.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            while offset + frames <= buffer.count {
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: UnsafeMutableRawPointer(buffer.baseAddress! + offset)))
                // Host time in ticks for `offset` samples.
                let host = UInt64(Double(offset) / rate * 1e9 / SpectrumAnalyzer.hostTick)
                analyzer.consume(&list, hostTime: host)
                offset += frames
            }
        }
        return collector.slices.withLock { $0 }
    }

    @Test(arguments: [95.0, 120.0, 128.0, 140.0])
    func kickTempoAndPhase(bpm: Double) {
        let onsets = Self.slices(Self.music(bpm: bpm, seconds: 10.5))
        let period = 60 / bpm
        // Every 3-second window from the second second on.
        var found = 0
        for start in stride(from: 1.0, to: 9.5, by: 3.0) {
            let window = onsets.filter { $0.time >= start && $0.time < start + 3 }
            guard let beat = BeatFinder.beat(window.map { ($0.time, $0.bass) }, range: 0.33...0.9, previous: nil) else { continue }
            found += 1
            #expect(abs(beat.period - period) < period * 0.02, "period \(beat.period) for \(period)")
            // The found beat lands on a kick (within 25 ms), up to one slice of lateness.
            let offset = beat.beat.truncatingRemainder(dividingBy: period)
            let distance = min(offset, period - offset)
            #expect(distance < 0.035, "phase off by \(distance)")
            // A kick over a quiet mix stands out clearly.
            #expect(beat.strength > 3, "strength \(beat.strength)")
        }
        #expect(found == 3)
    }

    @Test func hatsOnTheEighths() {
        let bpm = 120.0
        let onsets = Self.slices(Self.music(bpm: bpm, seconds: 8))
        let window = onsets.filter { $0.time >= 1 && $0.time < 4 }
        let beat = BeatFinder.beat(window.map { ($0.time, $0.treble) }, range: 0.2...0.9, previous: nil)
        #expect(beat != nil)
        if let beat {
            // Eighths (0.25 s) or quarters (0.5 s): either reads as the hats' beat.
            let eighth = 60 / bpm / 2
            let ratio = beat.period / eighth
            #expect(abs(ratio - ratio.rounded()) < 0.04, "hat period \(beat.period)")
        }
    }

    @Test func noBeatInAHeldChord() {
        let rate = 48_000.0
        let samples = (0..<Int(8 * rate)).map { index -> Float in
            let t = Double(index) / rate
            return Float(0.2 * (sin(2 * .pi * 220 * t) + sin(2 * .pi * 330 * t)) + 0.01 * sin(Double(index) * 12.9898).truncatingRemainder(dividingBy: 1))
        }
        let onsets = Self.slices(samples)
        let window = onsets.filter { $0.time >= 1 && $0.time < 4 }
        #expect(BeatFinder.beat(window.map { ($0.time, $0.bass) }, range: 0.33...0.9, previous: nil) == nil)
    }
}
