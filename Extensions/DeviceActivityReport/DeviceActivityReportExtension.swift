import DeviceActivity
import ExtensionKit
import FamilyControls
import ManagedSettings
import SwiftUI

@main
struct PayMeTimeDeviceActivityReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        ApplicationUsageReport { rows in
            ApplicationUsageReportView(rows: rows)
        }
        ProgressReport { summary in
            ProgressSummaryView(summary: summary)
        }
        AnalyticsMilestoneReport { completed in
            AnalyticsMilestoneReportView(completed: completed)
        }
    }
}

struct AnalyticsMilestoneReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .payMeTimeAnalyticsMilestone
    let content: (Bool) -> AnalyticsMilestoneReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> Bool {
        guard let request = AnalyticsSharedRepository.loadCohort()?.pendingRequest else {
            return false
        }

        var durationByTokenKey: [String: Int] = [:]
        for await activityData in data {
            for await segment in activityData.activitySegments {
                for await category in segment.categories {
                    for await application in category.applications {
                        guard let token = application.application.token else { continue }
                        let key = ScreenTimeSharedRepository.tokenKey(token)
                        durationByTokenKey[key, default: 0] += Int(
                            application.totalActivityDuration
                        )
                    }
                }
            }
        }

        AnalyticsSharedRepository.completeMilestone(
            requestID: request.id,
            durationSecondsByTokenKey: durationByTokenKey
        )
        return true
    }
}

struct ProgressReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .payMeTimeProgress
    let content: (ProgressSummary) -> ProgressSummaryView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ProgressSummary {
        let calendar = Calendar.current
        let generatedAt = Date.now
        let today = calendar.startOfDay(for: generatedAt)
        let currentStart = calendar.date(
            byAdding: .day,
            value: -6,
            to: today
        ) ?? today
        let selectionDate =
            ScreenTimeSharedRepository.load().selectionDate ?? generatedAt
        let selectionDay = calendar.startOfDay(for: selectionDate)
        let baselineStart = calendar.date(
            byAdding: .day,
            value: -7,
            to: selectionDay
        ) ?? selectionDay

        var dailyTotals: [Date: TimeInterval] = [:]
        for await activityData in data {
            for await segment in activityData.activitySegments {
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                var selectedAppDuration: TimeInterval = 0
                for await category in segment.categories {
                    for await application in category.applications {
                        selectedAppDuration += application.totalActivityDuration
                    }
                }
                dailyTotals[day, default: 0] += selectedAppDuration
            }
        }

        let currentDays = (0..<7).compactMap { index -> ProgressDailyUsage? in
            guard let day = calendar.date(
                byAdding: .day,
                value: index,
                to: currentStart
            ) else {
                return nil
            }
            return ProgressDailyUsage(
                day: day,
                seconds: dailyTotals[day] ?? 0
            )
        }

        let baselineSeconds = (0..<7).reduce(0.0) { total, index in
            guard let day = calendar.date(
                byAdding: .day,
                value: index,
                to: baselineStart
            ) else {
                return total
            }
            return total + (dailyTotals[day] ?? 0)
        }

        return ProgressSummary(
            dailyUsage: currentDays,
            baselineSeconds: baselineSeconds,
            selectionDate: selectionDate,
            generatedAt: generatedAt
        )
    }
}

struct AnalyticsMilestoneReportView: View {
    let completed: Bool

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
    }
}

struct ApplicationUsageRow: Identifiable {
    let token: ApplicationToken
    let duration: TimeInterval
    let rateCentsPerHour: Int
    let costMicrocents: Int64

    var id: String {
        ScreenTimeSharedRepository.tokenKey(token)
    }
}

struct ApplicationUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .payMeTimeApplications
    let content: ([ApplicationUsageRow]) -> ApplicationUsageReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> [ApplicationUsageRow] {
        var durationByApplication: [ApplicationToken: TimeInterval] = [:]

        for await activityData in data {
            for await segment in activityData.activitySegments {
                for await category in segment.categories {
                    for await application in category.applications {
                        guard let token = application.application.token else { continue }
                        durationByApplication[token, default: 0] += application.totalActivityDuration
                    }
                }
            }
        }

        let snapshot = ScreenTimeSharedRepository.load()
        return durationByApplication
            .map { token, duration in
                ApplicationUsageRow(
                    token: token,
                    duration: duration,
                    rateCentsPerHour: snapshot.rate(for: token),
                    costMicrocents: snapshot.costMicrocents(for: token)
                )
            }
            .sorted { lhs, rhs in
                if lhs.duration == rhs.duration {
                    return lhs.id < rhs.id
                }
                return lhs.duration > rhs.duration
            }
    }
}

struct ApplicationUsageReportView: View {
    let rows: [ApplicationUsageRow]

    var body: some View {
        if rows.isEmpty {
            ContentUnavailableView {
                Label("No activity yet", systemImage: "clock")
            } description: {
                Text("Use a selected app, then return here to see today’s time.")
            }
        } else {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        Label(row.token)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        metric(title: "Time spent", value: duration(row.duration))
                        metric(title: "Cost", value: cost(row.costMicrocents))
                    }
                    .padding(.vertical, 10)

                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(minutes)m"
    }

    private func cost(_ microcents: Int64) -> String {
        let cents = Double(microcents) / 1_000_000
        let rounded = (cents * 10).rounded() / 10
        if microcents > 0, rounded == 0 {
            return "<0.1¢"
        }
        return String(
            format: rounded == rounded.rounded() ? "%.0f¢" : "%.1f¢",
            rounded
        )
    }
}
