import SwiftUI

/// Today's usage hour by hour (#6): 24 bars, the hour it is now in the accent color, hours still to
/// come left empty, and faint bars behind them for the same hours on the earlier days that had usage
/// — the rhythm of a coding day at a glance.
///
/// It reads like `MonthDailyTrend`: the same track height, spacing and minimum bar, a caption with the
/// highlighted column's readout and the peak, and a hover tooltip. Everything it draws comes in
/// `series`, built once per refresh (`LocalUsageReader.hourlySeries`, summed in
/// `UsageStore.todayHourlyTotals`); nothing here scans or reads the clock.
@MainActor
struct TodayHourlyChart: View {
    let series: HourlySeries
    let showsCost: Bool
    /// The hour it is now (0–23).
    let currentHour: Int
    let l: L
    /// The visualization switch dots (`PageDots`), as in the other charts.
    var trailing = AnyView(EmptyView())

    @State private var hovered: Int?

    var body: some View {
        let average = series.averageTokens
        let peak = TodayHourlyMetrics.peak(series, average: average)
        VStack(alignment: .leading, spacing: 3) {
            captionRow
            barRow(average: average, peak: peak)
                .overlay(alignment: .bottomLeading) { hoverTooltip(average: average) }
                .zIndex(1)   // the tooltip rises over the caption and the rows above
            axisRow
            if !series.earlierActiveDays.isEmpty {
                legend.padding(.top, 2)
            }
        }
        .padding(.top, 4)
    }

    /// Title, the current hour's readout, the busiest hour today, and the dots.
    private var captionRow: some View {
        HStack(spacing: 5) {
            Text(l.todayByHour)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(TodayHourlyMetrics.readout(series, hour: currentHour, showsCost: showsCost, l: l))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            if let peakHour = TodayHourlyMetrics.peakHour(series) {
                Text(l.peakDay)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(TodayHourlyMetrics.stamp(peakHour))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            trailing
        }
    }

    private func barRow(average: [Double], peak: Int) -> some View {
        HStack(alignment: .bottom, spacing: DailyTrendMetrics.spacing) {
            ForEach(0..<24, id: \.self) { hour in
                let tokens = series.hours.indices.contains(hour) ? series.hours[hour].totalTokens : 0
                let averageTokens = average.indices.contains(hour) ? average[hour] : 0
                ZStack(alignment: .bottom) {
                    // The earlier days' same hour: a pale bar behind, drawn for later hours too so
                    // today can be read against the usual day ahead of it.
                    if averageTokens > 0 {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.secondary.opacity(0.16))
                            .frame(height: DailyTrendMetrics.barHeight(tokens: Int(averageTokens.rounded()), peak: peak))
                    }
                    if hour <= currentHour {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Self.fill(hour: hour, tokens: tokens, currentHour: currentHour,
                                            hovered: hovered == hour))
                            .frame(height: DailyTrendMetrics.barHeight(tokens: tokens, peak: peak))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())   // a low bar still hovers over its whole column
                .onHover { inside in hovered = inside ? hour : (hovered == hour ? nil : hovered) }
            }
        }
        .frame(height: DailyTrendMetrics.track, alignment: .bottom)
    }

    /// The hour now in the accent color; hours with no use a shade fainter than hours with a little,
    /// as in the day bars.
    private static func fill(hour: Int, tokens: Int, currentHour: Int, hovered: Bool) -> Color {
        if hour == currentHour { return .accentColor }
        return Color.secondary.opacity(hovered ? 0.8 : tokens == 0 ? 0.18 : 0.45)
    }

    /// Hour marks at 0, 6, 12, 18 and the hour now; a fixed mark next to the current one gives way
    /// so the two never overlap.
    private var axisRow: some View {
        HStack(spacing: DailyTrendMetrics.spacing) {
            ForEach(0..<24, id: \.self) { hour in
                Group {
                    if let label = TodayHourlyMetrics.axisLabel(hour: hour, currentHour: currentHour) {
                        Text(label)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(hour == currentHour ? AnyShapeStyle(Color.accentColor)
                                                                 : AnyShapeStyle(.secondary))
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)
            Text(l.hourlyAverageLegend(days: series.earlierActiveDays.count,
                                       window: LocalUsageReader.hourlyAverageDays))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func hoverTooltip(average: [Double]) -> some View {
        if let hovered, let info = TodayHourlyMetrics.tooltip(series, average: average, hour: hovered,
                                                              currentHour: currentHour,
                                                              showsCost: showsCost, l: l) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let column = (width + DailyTrendMetrics.spacing) / 24
                let center = column * (CGFloat(hovered) + 0.5)
                tooltipCard(info)
                    .fixedSize()
                    .alignmentGuide(.leading) { d in -min(max(center - d.width / 2, 0), max(0, width - d.width)) }
                    .alignmentGuide(.bottom) { d in d.height + geometry.size.height + 4 }
                    .frame(width: width, height: geometry.size.height, alignment: .bottomLeading)
            }
            .allowsHitTesting(false)
        }
    }

    private func tooltipCard(_ info: TodayHourlyMetrics.Tooltip) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(info.range).fontWeight(.semibold)
                if let tokens = info.tokens { Text(tokens) }
                if let cost = info.cost { Text(cost).foregroundStyle(.secondary) }
            }
            .font(.caption)
            if let average = info.average {
                Text(average).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
    }
}

/// The chart's arithmetic and words, kept apart from the view so tests can check them directly.
enum TodayHourlyMetrics {
    /// "14:00".
    static func stamp(_ hour: Int) -> String { String(format: "%02d:00", hour) }

    /// "14:00–15:00" (the last hour ends at 24:00).
    static func range(_ hour: Int) -> String { String(format: "%02d:00–%02d:00", hour, hour + 1) }

    /// One scale for today's bars and the average behind them, so both can be compared.
    static func peak(_ series: HourlySeries, average: [Double]) -> Int {
        max(series.hours.map(\.totalTokens).max() ?? 0, Int((average.max() ?? 0).rounded()))
    }

    /// Today's busiest hour, when more than one hour had use — with a single hour it is the readout.
    static func peakHour(_ series: HourlySeries) -> Int? {
        let used = series.hours.filter { $0.totalTokens > 0 }
        guard used.count > 1, let top = used.max(by: { $0.totalTokens < $1.totalTokens }) else { return nil }
        return top.hour
    }

    /// The caption's readout for the hour it is now: "14:00 1.2M $0.40".
    static func readout(_ series: HourlySeries, hour: Int, showsCost: Bool, l: L) -> String {
        guard series.hours.indices.contains(hour) else { return "" }
        let slot = series.hours[hour]
        let text = "\(stamp(hour)) \(TokenFormatter.compact(slot.totalTokens))"
        return showsCost ? "\(text) \(slot.usageCost.text(l))" : text
    }

    static func axisLabel(hour: Int, currentHour: Int) -> String? {
        if hour == currentHour { return "\(hour)" }
        guard hour % 6 == 0, abs(hour - currentHour) > 2 else { return nil }
        return "\(hour)"
    }

    struct Tooltip: Equatable {
        var range: String
        /// Today's tokens, `nil` for an hour that has not come yet.
        var tokens: String?
        var cost: String?
        /// "Avg 800K", `nil` when the earlier days had nothing in this hour.
        var average: String?
    }

    static func tooltip(_ series: HourlySeries, average: [Double], hour: Int, currentHour: Int,
                        showsCost: Bool, l: L) -> Tooltip? {
        guard series.hours.indices.contains(hour) else { return nil }
        let slot = series.hours[hour]
        let past = hour <= currentHour
        let averageTokens = average.indices.contains(hour) ? average[hour] : 0
        let averageText = averageTokens > 0
            ? "\(l.hourlyAverageShort) \(TokenFormatter.compact(Int(averageTokens.rounded())))" : nil
        guard past || averageText != nil else { return nil }
        return Tooltip(range: range(hour),
                       tokens: past ? TokenFormatter.compact(slot.totalTokens) : nil,
                       cost: past && showsCost ? slot.usageCost.text(l) : nil,
                       average: averageText)
    }
}
