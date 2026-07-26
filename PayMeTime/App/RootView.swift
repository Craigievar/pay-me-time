import DeviceActivity
import SwiftUI

struct RootView: View {
    let store: AppStore

    var body: some View {
        ZStack {
            Group {
                if store.fixtureName == "protection" {
                    NavigationStack {
                        ProtectionView(store: store)
                    }
                } else if store.fixtureName == "progress" {
                    NavigationStack {
                        ProgressScreen(store: store)
                    }
                } else if store.fixtureName == "settings" {
                    NavigationStack {
                        SettingsView(store: store)
                    }
                } else if store.fixtureName == "shield" || store.fixtureName == "empty-shield" {
                    ShieldSurface(
                        mode: store.fixtureName == "empty-shield" ? .empty : .freeTime,
                        appName: "TikTok",
                        rate: 3,
                        freeMinutes: 42,
                        balance: store.creditMicrocents,
                        proceed: {},
                        pass: {},
                        disable: {}
                    )
                } else if store.onboardingComplete {
                    AppShell(store: store)
                } else {
                    OnboardingView(store: store)
                }
            }

            if let request = store.analyticsMilestoneRequest,
                !store.activitySelection.applicationTokens.isEmpty {
                AnalyticsMilestoneTrigger(store: store, request: request)
            }
        }
    }
}

private struct AppShell: View {
    let store: AppStore

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(store: store)
            }
            .tabItem { Label("Home", systemImage: "hourglass") }

            NavigationStack {
                ProtectionView(store: store)
            }
            .tabItem { Label("Protection", systemImage: "shield") }

            NavigationStack {
                ProgressScreen(store: store)
            }
            .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }

            NavigationStack {
                SettingsView(store: store)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

private struct AnalyticsMilestoneTrigger: View {
    let store: AppStore
    let request: AnalyticsMilestoneRequest

    var body: some View {
        DeviceActivityReport(.payMeTimeAnalyticsMilestone, filter: filter)
            .id(request.id)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: request.id) {
                for _ in 0..<4 {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    store.applicationBecameActive()
                    if store.analyticsMilestoneRequest?.id != request.id {
                        return
                    }
                }
            }
    }

    private var filter: DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .daily(
                during: DateInterval(
                    start: request.periodStart,
                    end: request.periodEnd
                )
            ),
            devices: .all,
            applications: store.activitySelection.applicationTokens
        )
    }
}
