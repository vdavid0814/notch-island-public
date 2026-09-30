import SwiftUI

/// The stretch of time a battery chart shows.
nonisolated enum BatteryChartRange: String, CaseIterable, Codable, Sendable {
    case today, last24Hours, last48Hours

    /// iPhone's: a quarter of an hour, half an hour for two days.
    var bucketSeconds: TimeInterval { self == .last48Hours ? 1800 : 900 }

    /// Hours between two axis ticks, on the clock's multiples (0, 6, 12, 18).
    var tickHours: Int { self == .last48Hours ? 12 : 6 }

    /// Today is the calendar day (23 or 25 hours across a DST change). The others end at the bucket
    /// boundary after `now`, counted from local midnight so buckets fall on the clock's quarters.
    func interval(now: Date, calendar: Calendar) -> DateInterval {
        switch self {
        case .today:
            return calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 86_400)
        case .last24Hours, .last48Hours:
            let midnight = calendar.startOfDay(for: now)
            let buckets = (now.timeIntervalSince(midnight) / bucketSeconds).rounded(.up)
            let end = midnight.addingTimeInterval(buckets * bucketSeconds)
            let hours: TimeInterval = self == .last48Hours ? 48 : 24
            return DateInterval(start: end.addingTimeInterval(-hours * 3600), end: end)
        }
    }
}

nonisolated enum BatteryChartStyle: String, CaseIterable, Codable, Sendable {
    case bars, area, line
}

nonisolated struct BatteryChartPoint: Sendable, Equatable {
    var date: Date
    /// 0...100.
    var level: Double
}

/// A stretch of the chart. Normal and charging stretches carry the level line and follow each
/// other; gaps (the Mac asleep or the app not running) break it; display-off stretches overlap
/// the others.
nonisolated struct BatteryChartSegment: Sendable, Equatable {
    nonisolated enum Kind: Sendable, Equatable {
        case normal, charging, gap, displayOff
    }

    var kind: Kind
    var start: Date
    var end: Date
    /// The level line, from `start` to `end` (normal and charging only).
    var points: [BatteryChartPoint] = []

    var carriesLevel: Bool { kind == .normal || kind == .charging }

    /// Linear between the points.
    func level(at date: Date) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        if date <= first.date { return first.level }
        if date >= last.date { return last.level }
        guard let index = points.firstIndex(where: { $0.date >= date }) else { return last.level }
        let (a, b) = (points[index - 1], points[index])
        let span = b.date.timeIntervalSince(a.date)
        guard span > 0 else { return b.level }
        return a.level + (b.level - a.level) * date.timeIntervalSince(a.date) / span
    }

    func overlap(_ start: Date, _ end: Date) -> TimeInterval {
        max(0, min(end, self.end).timeIntervalSince(max(start, self.start)))
    }

    /// Cut to `start...end`, the level interpolated at the cuts; nil when nothing is left.
    func clipped(to start: Date, _ end: Date) -> BatteryChartSegment? {
        let from = max(start, self.start), to = min(end, self.end)
        guard to > from else { return nil }
        var result = BatteryChartSegment(kind: kind, start: from, end: to)
        guard carriesLevel else { return result }
        if let level = level(at: from) { result.points.append(BatteryChartPoint(date: from, level: level)) }
        result.points += points.filter { $0.date > from && $0.date < to }
        if let level = level(at: to) { result.points.append(BatteryChartPoint(date: to, level: level)) }
        return result
    }
}

/// One bar of the iPhone-style chart.
nonisolated struct BatteryChartBucket: Sendable, Equatable {
    var start: Date
    var end: Date
    /// The level at the last moment of the bucket the history covers; nil for the future and
    /// where nothing is known.
    var level: Double?
    /// Charged at any time in it.
    var isCharging: Bool
    /// Half of it or more (of the part already past) lies in a gap.
    var isGap: Bool
    /// Half of it or more (of the part already past) had the displays off.
    var isDisplayOff: Bool
}

/// The history laid out for one range: pure, built off the main thread by `BatteryCenter`.
nonisolated struct BatteryChartModel: Sendable, Equatable {
    var range: BatteryChartRange
    var interval: DateInterval
    var now: Date
    /// By start time.
    var segments: [BatteryChartSegment]
    var buckets: [BatteryChartBucket]
    /// Axis ticks on the clock's multiples of `range.tickHours`, both ends included.
    var ticks: [Date]

    init(records: [BatteryRecord], range: BatteryChartRange, now: Date, calendar: Calendar) {
        self.range = range
        self.now = now
        let interval = range.interval(now: now, calendar: calendar)
        self.interval = interval
        let visibleEnd = min(interval.end, now)

        var timeline = Timeline()
        for record in records.sorted(by: { $0.time < $1.time }) where record.date <= visibleEnd {
            timeline.add(record)
        }
        timeline.finish(at: visibleEnd)

        let clipped = timeline.segments.compactMap { $0.clipped(to: interval.start, visibleEnd) }
        segments = clipped.sorted { $0.start < $1.start }

        let lines = segments.filter(\.carriesLevel)
        let gaps = segments.filter { $0.kind == .gap }
        let dark = segments.filter { $0.kind == .displayOff }
        var buckets: [BatteryChartBucket] = []
        var start = interval.start
        while start < interval.end {
            let end = min(start.addingTimeInterval(range.bucketSeconds), interval.end)
            let past = min(end, visibleEnd)
            var bucket = BatteryChartBucket(start: start, end: end, level: nil, isCharging: false, isGap: false, isDisplayOff: false)
            if past > start {
                let elapsed = past.timeIntervalSince(start)
                let covering = lines.filter { $0.overlap(start, past) > 0 }
                bucket.level = covering.last.flatMap { $0.level(at: min(past, $0.end)) }
                bucket.isCharging = covering.contains { $0.kind == .charging }
                bucket.isGap = gaps.reduce(0) { $0 + $1.overlap(start, past) } * 2 >= elapsed
                bucket.isDisplayOff = dark.reduce(0) { $0 + $1.overlap(start, past) } * 2 >= elapsed
            }
            buckets.append(bucket)
            start = end
        }
        self.buckets = buckets

        var ticks: [Date] = []
        calendar.enumerateDates(startingAfter: interval.start.addingTimeInterval(-1),
                                matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) { date, _, stop in
            guard let date, date <= interval.end else { stop = true; return }
            if calendar.component(.hour, from: date) % range.tickHours == 0 { ticks.append(date) }
        }
        self.ticks = ticks
    }

    /// Walks the records in time order into level stretches, gaps and display-off stretches.
    private struct Timeline {
        var segments: [BatteryChartSegment] = []
        /// The level stretch being drawn.
        var line: BatteryChartSegment?
        var lastRecord: Date?
        /// Since the last reading, and only while the sleep may still be a gap: a short one is
        /// forgotten at its wake.
        var sleptAt: Date?
        var wokeAt: Date?
        var displayOffAt: Date?

        mutating func add(_ record: BatteryRecord) {
            let date = record.date
            defer { lastRecord = date }
            switch record.kind {
            case .systemSleep:
                if sleptAt == nil { sleptAt = date }
                wokeAt = nil
            case .systemWake:
                guard let sleptAt else { break }
                if date.timeIntervalSince(sleptAt) > BatteryHistory.gapThreshold {
                    wokeAt = date
                } else {
                    self.sleptAt = nil
                    wokeAt = nil
                }
            case .displayOff:
                if displayOffAt == nil { displayOffAt = date }
            case .displayOn:
                // Displays that come back after a long sleep were off only until the gap began.
                let end = min(date, sleptAt ?? date)
                if let displayOffAt, end > displayOffAt {
                    segments.append(BatteryChartSegment(kind: .displayOff, start: displayOffAt, end: end))
                }
                displayOffAt = nil
            case .appQuit:
                break
            case .sample, .appStart:
                let point = BatteryChartPoint(date: date, level: Double(record.level))
                let kind: BatteryChartSegment.Kind = record.isCharging ? .charging : .normal
                var resume = date
                if record.flags.contains(.gapBefore), let lastRecord {
                    // Asleep: from the sleep to the wake. Not running: from the last sign of life.
                    let start = sleptAt ?? lastRecord
                    resume = max(start, wokeAt ?? date)
                    breakLine(from: start, to: resume)
                }
                if var current = line {
                    current.points.append(point)
                    current.end = date
                    if current.kind == kind {
                        line = current
                    } else {
                        segments.append(current)
                        line = BatteryChartSegment(kind: kind, start: date, end: date, points: [point])
                    }
                } else {
                    // After a gap the reading's level holds from the wake on.
                    var points = [BatteryChartPoint(date: resume, level: point.level)]
                    if date > resume { points.append(point) }
                    line = BatteryChartSegment(kind: kind, start: resume, end: date, points: points)
                }
                sleptAt = nil
                wokeAt = nil
            }
        }

        /// A gap from `start` to `end`.
        mutating func breakLine(from start: Date, to end: Date) {
            closeLine(at: start)
            if let displayOffAt, start > displayOffAt {
                segments.append(BatteryChartSegment(kind: .displayOff, start: displayOffAt, end: start))
            }
            displayOffAt = nil
            if end > start { segments.append(BatteryChartSegment(kind: .gap, start: start, end: end)) }
        }

        /// Holds the last level until `date`.
        mutating func closeLine(at date: Date) {
            guard var current = line, let last = current.points.last else { return }
            if date > last.date { current.points.append(BatteryChartPoint(date: date, level: last.level)) }
            current.end = max(current.end, date)
            segments.append(current)
            line = nil
        }

        mutating func finish(at end: Date) {
            if let sleptAt {
                if let wokeAt, wokeAt.timeIntervalSince(sleptAt) > BatteryHistory.gapThreshold {
                    // Awake after a long sleep, with no reading yet: the level from before holds.
                    let last = line
                    breakLine(from: sleptAt, to: wokeAt)
                    if let last, let level = last.points.last?.level {
                        line = BatteryChartSegment(kind: last.kind, start: wokeAt, end: wokeAt,
                                                   points: [BatteryChartPoint(date: wokeAt, level: level)])
                    }
                } else if wokeAt == nil {
                    // Asleep as far as the history knows.
                    closeLine(at: sleptAt)
                }
            }
            closeLine(at: end)
            if let displayOffAt, end > displayOffAt {
                segments.append(BatteryChartSegment(kind: .displayOff, start: displayOffAt, end: end))
            }
        }
    }
}

/// A chart's shapes for one size, prebuilt off the main thread: the view only fills and strokes
/// them, so a redraw costs no layout work.
nonisolated struct BatteryChartGeometry: Sendable {
    nonisolated struct Tick: Sendable, Equatable {
        var x: CGFloat
        var date: Date
    }

    var size: CGSize
    var style: BatteryChartStyle
    /// By `style`: the bars on battery, or the area under the level on battery, except what is
    /// `low`; or the whole level line, to stroke.
    var level: Path
    /// The same shape while charging: bars, area or line.
    var charging: Path
    /// What lies below `PowerState.lowLevel` on battery: the bars below it, the area or the line
    /// where the level is under it. Bars and areas of the three never overlap (each is filled in
    /// its own colour); the line's lie on the whole line.
    var low: Path
    /// Diagonal hatching over the gaps, to stroke.
    var gaps: Path
    /// Full-height bands where the displays were off.
    var displayOff: Path
    /// The 0, 50 and 100 % lines and the tick lines, to stroke.
    var axis: Path
    var ticks: [Tick]

    static let hatchSpacing: CGFloat = 4

    init(model: BatteryChartModel, style: BatteryChartStyle, size: CGSize) {
        self.size = size
        self.style = style
        let duration = model.interval.duration
        func x(_ date: Date) -> CGFloat {
            duration > 0 ? size.width * CGFloat(date.timeIntervalSince(model.interval.start) / duration) : 0
        }
        func y(_ level: Double) -> CGFloat { size.height * (1 - CGFloat(min(max(level, 0), 100)) / 100) }

        var level = Path(), charging = Path(), low = Path()
        let lowLevel = Double(PowerState.lowLevel)
        switch style {
        case .bars:
            for bucket in model.buckets {
                guard let value = bucket.level, !bucket.isGap else { continue }
                let left = x(bucket.start), right = x(bucket.end)
                let inset = min((right - left) * 0.15, 1.5)
                let rect = CGRect(x: left + inset, y: y(value), width: max(right - left - 2 * inset, 0),
                                  height: size.height - y(value))
                let radius = min(rect.width / 2, 1.5)
                let corner = CGSize(width: radius, height: radius)
                if bucket.isCharging {
                    charging.addRoundedRect(in: rect, cornerSize: corner, style: .continuous)
                } else if value < lowLevel {
                    low.addRoundedRect(in: rect, cornerSize: corner, style: .continuous)
                } else {
                    level.addRoundedRect(in: rect, cornerSize: corner, style: .continuous)
                }
            }
        case .area, .line:
            // On battery, the columns where the level is below the line: the area under the level
            // there, or the level line itself, goes to `low`.
            var onBattery = Path(), lowColumns = Path()
            for segment in model.segments where segment.carriesLevel {
                let points = segment.points.map { CGPoint(x: x($0.date), y: y($0.level)) }
                guard let first = points.first, let last = points.last else { continue }
                var shape = Path()
                if style == .area {
                    shape.move(to: CGPoint(x: first.x, y: size.height))
                    points.forEach { shape.addLine(to: $0) }
                    shape.addLine(to: CGPoint(x: last.x, y: size.height))
                    shape.closeSubpath()
                } else {
                    shape.addLines(points)
                }
                if style == .line { level.addPath(shape) }
                guard segment.kind == .normal else {
                    charging.addPath(shape)
                    continue
                }
                onBattery.addPath(shape)
                for (a, b) in zip(segment.points, segment.points.dropFirst()) where min(a.level, b.level) < lowLevel {
                    // Where the level crosses the line between the two readings (linear, as drawn).
                    let crossing = a.level == b.level ? a.date : a.date.addingTimeInterval(
                        b.date.timeIntervalSince(a.date) * (lowLevel - a.level) / (b.level - a.level))
                    let from = a.level < lowLevel ? a.date : crossing
                    let to = b.level < lowLevel ? b.date : crossing
                    guard to > from else { continue }
                    lowColumns.addRect(CGRect(x: x(from), y: 0, width: x(to) - x(from), height: size.height))
                }
            }
            if style == .area {
                low = lowColumns.isEmpty ? Path() : onBattery.intersection(lowColumns)
                level = lowColumns.isEmpty ? onBattery : onBattery.subtracting(lowColumns)
            } else if !lowColumns.isEmpty {
                low = onBattery.lineIntersection(lowColumns)
            }
        }
        self.level = level
        self.charging = charging
        self.low = low

        var gaps = Path(), displayOff = Path()
        for segment in model.segments {
            let left = x(segment.start), right = x(segment.end)
            switch segment.kind {
            case .gap:
                // 45° lines, cut to the band's sides.
                let width = right - left, height = size.height
                var offset = -height
                while offset < width {
                    let from = max(0, -offset), to = min(height, width - offset)
                    if to > from {
                        gaps.move(to: CGPoint(x: left + offset + from, y: height - from))
                        gaps.addLine(to: CGPoint(x: left + offset + to, y: height - to))
                    }
                    offset += Self.hatchSpacing
                }
            case .displayOff:
                displayOff.addRect(CGRect(x: left, y: 0, width: right - left, height: size.height))
            case .normal, .charging:
                break
            }
        }
        self.gaps = gaps
        self.displayOff = displayOff

        var axis = Path()
        for value in [0.0, 50, 100] {
            axis.move(to: CGPoint(x: 0, y: y(value)))
            axis.addLine(to: CGPoint(x: size.width, y: y(value)))
        }
        ticks = model.ticks.map { Tick(x: x($0), date: $0) }
        for tick in ticks {
            axis.move(to: CGPoint(x: tick.x, y: 0))
            axis.addLine(to: CGPoint(x: tick.x, y: size.height))
        }
        self.axis = axis
    }
}
