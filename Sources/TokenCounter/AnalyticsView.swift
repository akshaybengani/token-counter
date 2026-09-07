import Charts
import SwiftUI

/// Daily usage as bars, against the same target the dial measures.
///
/// One series, so there is no series legend: the heading names it. Bars take the
/// dial's progress bands so the chart teaches the vocabulary the panel already uses
/// (std-29 cl-8). Because those are status colours they never carry meaning alone,
/// so the target line gives the same reading positionally, the bands are labelled,
/// and hovering a bar prints its exact figure.
struct AnalyticsView: View {
    @EnvironmentObject var store: UsageStore

    @State private var span = 14
    @State private var hovered: DailyRecord?

    private let spans = [7, 30, 90]

    private var rows: [(record: DailyRecord, total: Int)] {
        store.dailyTotals(days: span)
    }

    private var recorded: [(record: DailyRecord, total: Int)] {
        rows.filter { $0.record.recorded }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if recorded.isEmpty {
                emptyState
            } else {
                chart
                bands
                summary
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        // Redraw when a scan writes a new row.
        .id(store.historyRevision)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tokens per day")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Picker("", selection: $span) {
                    ForEach(spans, id: \.self) { Text("\($0)d").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }

            // On hover this line becomes the readout for the day under the cursor,
            // which is how an exact figure stays reachable without a label on
            // every bar.
            if let hovered, hovered.recorded {
                let total = hovered.total(includeCacheReads: store.includeCacheReads,
                                          providers: Set(store.countingProviders))
                Text("\(Self.longDate(hovered.date)) · \(Fmt.grouped(total)) tokens · \(store.percentText(Double(total) / Double(max(1, store.combinedTarget))))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if let hovered {
                Text("\(Self.longDate(hovered.date)) · not recorded")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Against a target of \(Fmt.compactTight(store.combinedTarget)) tokens a day. Hover a bar for its figure.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Chart

    private var maxY: Int {
        max(store.combinedTarget, recorded.map(\.total).max() ?? 0)
    }

    private var chart: some View {
        Chart {
            // A day the app never saw is shaded rather than drawn as a zero bar,
            // so an absence cannot be misread as a quiet day (std-30 cl-5).
            ForEach(rows.filter { !$0.record.recorded }, id: \.record.id) { row in
                RectangleMark(
                    x: .value("Day", row.record.date, unit: .day),
                    yStart: .value("From", 0),
                    yEnd: .value("To", maxY)
                )
                .foregroundStyle(Color.primary.opacity(0.05))
            }

            ForEach(recorded, id: \.record.id) { row in
                BarMark(
                    x: .value("Day", row.record.date, unit: .day),
                    y: .value("Tokens", row.total)
                )
                .foregroundStyle(UsageLevel(fraction: Double(row.total) / Double(max(1, store.combinedTarget))).color)
                .cornerRadius(3)
                .opacity(hovered == nil || hovered?.id == row.record.id ? 1 : 0.45)
            }

            RuleMark(y: .value("Target", store.combinedTarget))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.primary.opacity(0.35))
                .annotation(position: .top, alignment: .trailing) {
                    Text("target \(Fmt.compactTight(store.combinedTarget))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.07))
                AxisValueLabel {
                    if let n = value.as(Int.self) {
                        Text(Fmt.compactTight(n)).font(.system(size: 9))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: span > 30 ? 4 : 5)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.shortDate(date)).font(.system(size: 9))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            hovered = row(at: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .frame(height: 190)
    }

    /// Maps a cursor position to the nearest day, so the whole column is a hit target
    /// rather than the bar's own width.
    private func row(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> DailyRecord? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let x = location.x - geometry[plotFrame].origin.x
        guard let date: Date = proxy.value(atX: x) else { return nil }
        return rows.min { a, b in
            abs(a.record.date.timeIntervalSince(date)) < abs(b.record.date.timeIntervalSince(date))
        }?.record
    }

    // MARK: - Bands, so a status colour never stands alone

    private var bands: some View {
        HStack(spacing: 12) {
            band("Under 60%", .low)
            band("60%", .medium)
            band("85%", .high)
            band("Over target", .over)
            Spacer(minLength: 0)
        }
    }

    private func band(_ label: String, _ level: UsageLevel) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(level.color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Summary

    private var summary: some View {
        let totals = recorded.map(\.total)
        let average = totals.isEmpty ? 0 : totals.reduce(0, +) / totals.count
        let peak = totals.max() ?? 0
        let over = totals.filter { $0 > store.combinedTarget }.count
        let missing = rows.count - recorded.count

        return VStack(alignment: .leading, spacing: 3) {
            Text([
                "\(Fmt.compact(average)) a day on average",
                "peak \(Fmt.compact(peak))",
                over == 1 ? "1 day over target" : "\(over) days over target",
            ].joined(separator: " · "))
                .font(.system(size: 11))
                .monospacedDigit()

            Text(missing == 0
                 ? "\(recorded.count == 1 ? "1 day" : "\(recorded.count) days") recorded."
                 : "\(recorded.count) of \(rows.count) days recorded. The shaded columns are days the app wasn't running.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing recorded yet")
                .font(.system(size: 13, weight: medium))
            Text("A day's figures are saved as they're counted, and a new bar appears after each midnight. Leave the app running and the first bar shows up here today.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 30)
    }

    private var medium: Font.Weight { .medium }

    // MARK: - Dates

    private static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private static let long: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    static func shortDate(_ d: Date) -> String { short.string(from: d) }
    static func longDate(_ d: Date) -> String { long.string(from: d) }
}
