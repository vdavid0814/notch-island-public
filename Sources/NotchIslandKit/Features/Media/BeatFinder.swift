import Foundation
import QuartzCore

/// Finds the beat in one band's attack slices (`OnsetSample`), for the equalizer's pulses.
nonisolated enum BeatFinder {
    /// The beat in a band's attack slices: the period (within `range` seconds) at which its
    /// rises repeat most strongly, the time of one beat, and how much the beats stand out
    /// (`strength`: their rises against the band's average rise; ~1 is no beat, a kick drum
    /// over a mix ~4–8). Nil without a clear beat.
    static func beat(_ slices: [(time: CFTimeInterval, energy: Float)], range: ClosedRange<Double>,
                     previous: CFTimeInterval?) -> (period: CFTimeInterval, beat: CFTimeInterval, strength: Double)? {
        guard slices.count > 64 else { return nil }
        let step = (slices.last!.time - slices.first!.time) / Double(slices.count - 1)
        guard step > 0 else { return nil }
        // Rises of the band's loudness (log-compressed against its mean), half-wave rectified.
        let mean = slices.reduce(0.0) { $0 + Double($1.energy) } / Double(slices.count)
        guard mean > 1e-9 else { return nil }
        // A band with a beat pulses: its energy swings well beyond its mean (a kick drum: ~2×),
        // where a held note or noise hardly varies (~0.1–0.3).
        let variance = slices.reduce(0.0) { $0 + pow(Double($1.energy) - mean, 2) } / Double(slices.count)
        guard sqrt(variance) / mean > 0.6 else { return nil }
        let loudness = slices.map { log(1 + 50 * Double($0.energy) / mean) }
        var flux = [Double](repeating: 0, count: loudness.count)
        for i in 1..<loudness.count { flux[i] = max(loudness[i] - loudness[i - 1], 0) }
        let fluxMean = flux.reduce(0, +) / Double(flux.count)
        guard fluxMean > 0 else { return nil }
        flux = flux.map { max($0 - fluxMean * 0.5, 0) }
        // The period: the strongest autocorrelation within the range, refined between samples.
        let lags = max(2, Int(range.lowerBound / step))...min(flux.count / 2, Int(range.upperBound / step))
        guard lags.lowerBound < lags.upperBound else { return nil }
        func correlation(_ lag: Int) -> Double {
            var total = 0.0
            for i in 0..<(flux.count - lag) { total += flux[i] * flux[i + lag] }
            return total / Double(flux.count - lag)
        }
        let zero = correlation(0)
        guard zero > 0 else { return nil }
        var best = lags.lowerBound, bestValue = -1.0
        var values: [Int: Double] = [:]
        for lag in lags {
            var value = correlation(lag)
            // Near the tempo already found, a little preferred: the beat stays steady.
            if let previous, abs(Double(lag) * step - previous) < previous * 0.04 { value *= 1.15 }
            values[lag] = value
            if value > bestValue { bestValue = value; best = lag }
        }
        // A beat worth showing repeats clearly.
        guard bestValue / zero > 0.3 else { return nil }
        let before = values[best - 1] ?? correlation(best - 1), after = values[best + 1] ?? correlation(best + 1)
        let bend = before - 2 * bestValue + after
        let shift = bend < 0 ? min(max(0.5 * (before - after) / bend, -0.5), 0.5) : 0
        var period = (Double(best) + shift) * step
        if let previous, abs(period - previous) < previous * 0.04 { period = (period + previous) / 2 }
        // The phase: where a grid of that period catches the most of the rises.
        let lagSamples = period / step
        var bestPhase = 0.0, bestScore = -1.0
        var phase = 0.0
        while phase < lagSamples {
            var score = 0.0, position = phase
            while position < Double(flux.count - 1) {
                let i = Int(position), t = position - Double(i)
                score += flux[i] * (1 - t) + flux[i + 1] * t
                position += lagSamples
            }
            if score > bestScore { bestScore = score; bestPhase = phase }
            phase += 0.5
        }
        // How much the rises on the beat stand out from the band's average rise.
        let beats = max(1.0, (Double(flux.count - 1) - bestPhase) / lagSamples)
        let strength = bestScore / beats / fluxMean
        return (period, slices.first!.time + bestPhase * step, strength)
    }
}
