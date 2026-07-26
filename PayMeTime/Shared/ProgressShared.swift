import Charts
import Foundation
import SwiftUI

struct ProgressDailyUsage: Codable, Equatable, Identifiable, Sendable {
    let day: Date
    let seconds: TimeInterval

    var id: Date { day }
}

struct ProgressSummary: Codable, Equatable, Sendable {
    let dailyUsage: [ProgressDailyUsage]
    let baselineSeconds: TimeInterval
    let selectionDate: Date
    let generatedAt: Date

    var orderedDailyUsage: [ProgressDailyUsage] {
        dailyUsage.sorted { $0.day < $1.day }
    }

    var lastSevenDaysSeconds: TimeInterval {
        orderedDailyUsage.suffix(7).reduce(0) { $0 + $1.seconds }
    }

    var changeSeconds: TimeInterval {
        lastSevenDaysSeconds - baselineSeconds
    }

    var percentChange: Double? {
        guard baselineSeconds > 0 else { return nil }
        return changeSeconds / baselineSeconds * 100
    }

    var baselineDailyAverageSeconds: TimeInterval {
        baselineSeconds / 7
    }

    func comparisonIsReady(calendar: Calendar = .current) -> Bool {
        let selectionDay = calendar.startOfDay(for: selectionDate)
        let generatedDay = calendar.startOfDay(for: generatedAt)
        let elapsedDays = calendar.dateComponents(
            [.day],
            from: selectionDay,
            to: generatedDay
        ).day ?? 0
        return elapsedDays >= 7
    }

    func daysUntilComparison(calendar: Calendar = .current) -> Int {
        let selectionDay = calendar.startOfDay(for: selectionDate)
        let generatedDay = calendar.startOfDay(for: generatedAt)
        let elapsedDays = calendar.dateComponents(
            [.day],
            from: selectionDay,
            to: generatedDay
        ).day ?? 0
        return max(0, 7 - elapsedDays)
    }

    static func fixture(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ProgressSummary {
        let today = calendar.startOfDay(for: now)
        let minutes = [44, 50, 38, 35, 41, 31, 28]
        let usage = minutes.enumerated().compactMap { index, minutes in
            calendar.date(
                byAdding: .day,
                value: index - 6,
                to: today
            ).map {
                ProgressDailyUsage(
                    day: $0,
                    seconds: TimeInterval(minutes * 60)
                )
            }
        }
        return ProgressSummary(
            dailyUsage: usage,
            baselineSeconds: 6.5 * 60 * 60,
            selectionDate: calendar.date(
                byAdding: .day,
                value: -21,
                to: today
            ) ?? today,
            generatedAt: now
        )
    }
}

struct ProgressSummaryView: View {
    let summary: ProgressSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                chartCard
                comparisonCard
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PMTTheme.canvas)
    }

    private var hero: some View {
        VStack(spacing: 6) {
            Text("LAST 7 DAYS")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text(duration(summary.lastSevenDaysSeconds))
                .font(.system(size: 58, weight: .medium, design: .serif))
                .foregroundStyle(PMTTheme.sage)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text("in protected apps")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .pmtCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(duration(summary.lastSevenDaysSeconds)) in protected apps over the last seven days"
        )
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily time")
                .font(.headline)

            ProgressLineChart(summary: summary)
                .frame(height: 190)
                .accessibilityLabel("Daily protected app time over the last seven days")

            HStack(spacing: 18) {
                chartKey(color: PMTTheme.sage, title: "Daily time")
                chartKey(color: PMTTheme.stone, title: "Baseline average", dashed: true)
            }
        }
        .pmtCard()
    }

    @ViewBuilder
    private var comparisonCard: some View {
        if summary.comparisonIsReady() {
            VStack(alignment: .leading, spacing: 10) {
                Text("Compared with baseline")
                    .font(.headline)

                if let percentChange = summary.percentChange {
                    let roundedPercent = Int(abs(percentChange).rounded())
                    Label {
                        if abs(percentChange) < 1 {
                            Text("About the same as baseline")
                        } else {
                            Text(
                                "\(roundedPercent)% " +
                                "\(percentChange < 0 ? "less" : "more") than baseline"
                            )
                        }
                    } icon: {
                        Image(systemName: comparisonSymbol(percentChange))
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(comparisonColor(percentChange))

                    if abs(percentChange) >= 1 {
                        Text(
                            "\(duration(abs(summary.changeSeconds))) " +
                            "\(percentChange < 0 ? "less" : "more") " +
                            "across the same seven-day span."
                        )
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No baseline activity to compare yet.")
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    comparisonMetric(
                        title: "Last 7 days",
                        value: summary.lastSevenDaysSeconds
                    )
                    Spacer()
                    comparisonMetric(
                        title: "Baseline",
                        value: summary.baselineSeconds,
                        alignment: .trailing
                    )
                }
            }
            .pmtCard()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Baseline saved", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(PMTTheme.sage)
                Text(comparisonReadyMessage)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pmtCard()
        }
    }

    private var comparisonReadyMessage: String {
        let days = summary.daysUntilComparison()
        return days == 1
            ? "Your first seven-day comparison will be ready tomorrow."
            : "Your first seven-day comparison will be ready in \(days) days."
    }

    private func comparisonMetric(
        title: String,
        value: TimeInterval,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(duration(value))
                .font(.headline)
        }
    }

    private func chartKey(
        color: Color,
        title: String,
        dashed: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(color)
                .frame(width: 20, height: dashed ? 1 : 3)
                .overlay {
                    if dashed {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule()
                                    .fill(PMTTheme.canvas)
                                    .frame(width: 3, height: 2)
                            }
                        }
                    }
                }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func comparisonSymbol(_ percent: Double) -> String {
        if abs(percent) < 1 {
            return "minus"
        }
        return percent < 0 ? "arrow.down.right" : "arrow.up.right"
    }

    private func comparisonColor(_ percent: Double) -> Color {
        percent <= 0 ? PMTTheme.sage : PMTTheme.amber
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

private struct ProgressLineChart: View {
    let summary: ProgressSummary

    private var usage: [ProgressDailyUsage] {
        summary.orderedDailyUsage
    }

    private var maximumMinutes: Double {
        let usageMaximum = usage.map(\.seconds).max() ?? 0
        return max(usageMaximum, summary.baselineDailyAverageSeconds, 60) / 60
    }

    var body: some View {
        Chart {
            ForEach(usage) { item in
                AreaMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Minutes", item.seconds / 60)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            PMTTheme.sage.opacity(0.28),
                            PMTTheme.sage.opacity(0.02),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Minutes", item.seconds / 60)
                )
                .foregroundStyle(PMTTheme.sage)
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 2.5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                PointMark(
                    x: .value("Day", item.day, unit: .day),
                    y: .value("Minutes", item.seconds / 60)
                )
                .foregroundStyle(PMTTheme.sage)
                .symbolSize(24)
            }

            if summary.baselineDailyAverageSeconds > 0 {
                RuleMark(
                    y: .value(
                        "Baseline average",
                        summary.baselineDailyAverageSeconds / 60
                    )
                )
                .foregroundStyle(PMTTheme.stone)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
        }
        .chartYScale(domain: 0...(maximumMinutes * 1.15))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(.primary.opacity(0.08))
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(axisDuration(minutes))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func axisDuration(_ minutes: Double) -> String {
        minutes >= 60
            ? "\(Int((minutes / 60).rounded()))h"
            : "\(Int(minutes.rounded()))m"
    }
}
