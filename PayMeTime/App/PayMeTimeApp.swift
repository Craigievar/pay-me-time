import SwiftUI

@main
struct PayMeTimeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: AppStore

    init() {
        let analytics = PostHogAnalyticsTracker.bootstrap()
        _store = State(initialValue: AppStore(analytics: analytics))
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .tint(PMTTheme.amber)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.applicationBecameActive()
            }
        }
    }
}
