import SwiftUI

// The battery page's chart and words, drawn by its widgets (`BatteryFigures`): the page itself is a
// board of widgets now (`WidgetPages.batterySeed`).

extension BatteryChartColors {
    /// The chart's colours as the settings have them.
    init(_ settings: BatteryDisplaySettings, artwork: Color?) {
        // The iPhone's grey bars.
        self.init(normal: Self.resolve(settings.normalColor, Color(white: 0.62), artwork: artwork),
                  charging: Self.resolve(settings.chargingColor, .green, artwork: artwork),
                  low: Self.resolve(settings.lowColor, .red, artwork: artwork))
    }

    /// A chart colour: automatic is the slot's own; the accent is the theme's, as nowhere else on
    /// the page has one.
    private static func resolve(_ color: StyleColor, _ automatic: Color, artwork: Color?) -> AnyShapeStyle {
        switch color {
        case .automatic: AnyShapeStyle(automatic)
        case .accent, .theme: AnyShapeStyle(Color.islandAccent)
        case .artwork: AnyShapeStyle(artwork ?? automatic)
        case .semantic(let semantic):
            switch semantic {
            case .primary: AnyShapeStyle(.primary)
            case .secondary: AnyShapeStyle(.secondary)
            case .tertiary: AnyShapeStyle(.tertiary)
            case .positive: AnyShapeStyle(Color.green)
            case .warning: AnyShapeStyle(Color.orange)
            case .critical: AnyShapeStyle(Color.red)
            }
        case .named(let tint): AnyShapeStyle(tint.color ?? automatic)
        case .rgb(let rgb, let alpha): AnyShapeStyle(rgb.color.opacity(alpha))
        case .valueScale(let scale):
            // Over the chart's height: a charge red at the bottom, green at the top.
            AnyShapeStyle(LinearGradient(colors: scale == .rising ? [.green, .red] : [.red, .green],
                                         startPoint: .top, endPoint: .bottom))
        }
    }
}

struct BatteryChartColors {
    var normal: AnyShapeStyle
    var charging: AnyShapeStyle
    var low: AnyShapeStyle
}

/// The shapes, the percentages and the hours, at `size` (the plot's own).
struct BatteryChartPlot: View {
    let geometry: BatteryChartGeometry?
    let settings: BatteryDisplaySettings
    let colors: BatteryChartColors
    let size: CGSize
    /// The hours under the plot (a short widget leaves them out).
    var showsHours = true

    static let hoursHeight: CGFloat = 14
    /// The percentages beside the plot, where the captions are shown.
    static let percentWidth: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if let geometry { shapes(geometry) }
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                if settings.showsCaptions {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: IslandFormat.percent(1))
                        Spacer(minLength: 0)
                        Text(verbatim: IslandFormat.percent(0.5))
                        Spacer(minLength: 0)
                        Text(verbatim: IslandFormat.percent(0))
                    }
                    .frame(width: Self.percentWidth, height: size.height, alignment: .trailing)
                }
            }
            if showsHours {
            ZStack(alignment: .topLeading) {
                // Each hour just after its line, as the iPhone has them; one too near the end is left out.
                ForEach(geometry?.ticks ?? [], id: \.x) { tick in
                    if tick.x <= size.width - 16 {
                        Text(BatteryPageText.hour(tick.date))
                            .offset(x: tick.x + 2)
                    }
                }
            }
            .frame(width: size.width, height: Self.hoursHeight, alignment: .bottomLeading)
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder private func shapes(_ geometry: BatteryChartGeometry) -> some View {
        if settings.shadesDisplayOff {
            ChartShape(path: geometry.displayOff).fill(.white.opacity(0.06))
        }
        ChartShape(path: geometry.axis).stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 0.5, dash: [1.5, 2.5]))
        if settings.showsGaps {
            ChartShape(path: geometry.gaps).stroke(.white.opacity(0.2), lineWidth: 1)
        }
        switch geometry.style {
        case .bars, .area:
            let opacity = geometry.style == .area ? 0.55 : 1
            // Charging: a faint column up to full behind the bar, a cap along the top of the run.
            ChartShape(path: geometry.chargingBand).fill(colors.charging).opacity(0.18)
            ChartShape(path: geometry.chargingCap).fill(colors.charging)
            ChartShape(path: geometry.level).fill(colors.normal).opacity(opacity)
            ChartShape(path: geometry.charging).fill(colors.charging).opacity(opacity)
            ChartShape(path: geometry.low).fill(colors.low).opacity(opacity)
        case .line:
            let line = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            ChartShape(path: geometry.level).stroke(colors.normal, style: line)
            ChartShape(path: geometry.charging).stroke(colors.charging, style: line)
            ChartShape(path: geometry.low).stroke(colors.low, style: line)
        }
    }
}

/// A prebuilt path as a shape: equal paths are not drawn again.
nonisolated private struct ChartShape: Shape, Equatable {
    let path: Path

    func path(in rect: CGRect) -> Path { path }
}

/// What the battery page says, kept out of the views so it can be tested.
nonisolated enum BatteryPageText {
    /// An axis hour: "00", "06", "12", "18".
    static func hour(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))
    }
}
