import DeviceActivity
import SwiftUI

struct ProgressScreen: View {
    let store: AppStore

    var body: some View {
        Group {
            if store.fixtureName != nil {
                ProgressSummaryView(summary: .fixture())
            } else if store.activitySelection.applicationTokens.isEmpty {
                ContentUnavailableView {
                    Label("Choose protected apps", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Progress appears after you choose apps in Protection.")
                }
            } else {
                ZStack {
                    SwiftUI.ProgressView("Loading your progress…")
                        .foregroundStyle(.secondary)

                    DeviceActivityReport(
                        .payMeTimeProgress,
                        filter: reportFilter
                    )
                    .id(store.reportRevision)
                    .background(PMTTheme.canvas.opacity(0.001))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PMTTheme.canvas)
        .navigationTitle("Progress")
        .task {
            store.trackScreen("progress")
        }
    }

    private var reportFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let end = Date.now
        let today = calendar.startOfDay(for: end)
        let currentStart = calendar.date(
            byAdding: .day,
            value: -6,
            to: today
        ) ?? today
        let selectionDate = ScreenTimeSharedRepository.load().selectionDate ?? end
        let selectionDay = calendar.startOfDay(for: selectionDate)
        let baselineStart = calendar.date(
            byAdding: .day,
            value: -7,
            to: selectionDay
        ) ?? selectionDay

        return DeviceActivityFilter(
            segment: .daily(
                during: DateInterval(
                    start: min(baselineStart, currentStart),
                    end: end
                )
            ),
            devices: .all,
            applications: store.activitySelection.applicationTokens
        )
    }
}
