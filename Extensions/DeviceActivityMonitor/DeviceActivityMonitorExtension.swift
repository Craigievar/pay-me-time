import DeviceActivity
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == ScreenTimePolicy.dailyActivity else { return }

        let startedNewDay = ScreenTimeSharedRepository.update { snapshot in
            let calendar = Calendar.current
            let isNewDay =
                snapshot.costDay.map {
                    calendar.isDate($0, inSameDayAs: .now)
                } != true
            snapshot.normalizeDay()
            return isNewDay
        }
        if startedNewDay {
            ManagedSettingsStore(named: ScreenTimePolicy.storeName).clearAllSettings()
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard let windowID = ScreenTimePolicy.accessWindowID(from: activity) else {
            return
        }

        let snapshot = ScreenTimeSharedRepository.update { snapshot in
            snapshot.activeAccessWindows = (snapshot.activeAccessWindows ?? []).filter {
                $0.id != windowID && $0.endsAt > .now
            }
            return snapshot
        }
        let store = ManagedSettingsStore(named: ScreenTimePolicy.storeName)
        guard
            snapshot.protectionEnabled ?? true,
            snapshot.allowanceReached()
        else {
            store.shield.applications = nil
            return
        }
        store.shield.applications = ScreenTimePolicy.shieldedApplications(in: snapshot)
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        guard
            activity == ScreenTimePolicy.dailyActivity,
            event == ScreenTimePolicy.allowanceEvent
        else {
            return
        }

        let snapshot = ScreenTimeSharedRepository.update { snapshot in
            snapshot.normalizeDay()
            snapshot.allowanceReachedDay = .now
            return snapshot
        }
        if snapshot.protectionEnabled ?? true {
            ManagedSettingsStore(named: ScreenTimePolicy.storeName)
                .shield
                .applications = ScreenTimePolicy.shieldedApplications(in: snapshot)
        }

        AnalyticsSharedRepository.enqueue(
            AnalyticsEvent(
                name: "free allowance reached",
                properties: [
                    "source": .string("device_activity_monitor"),
                ]
            )
        )
    }
}
