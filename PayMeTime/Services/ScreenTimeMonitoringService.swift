import DeviceActivity
import Foundation
import ManagedSettings

enum ScreenTimeMonitoringService {
    static func refresh(
        using snapshot: SharedScreenTimeSnapshot,
        now: Date = .now
    ) throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring([ScreenTimePolicy.dailyActivity])

        let store = ManagedSettingsStore(named: ScreenTimePolicy.storeName)
        guard
            snapshot.protectionEnabled ?? true,
            !snapshot.selection.applicationTokens.isEmpty
        else {
            stopAccessMonitoring(center: center)
            store.clearAllSettings()
            return
        }

        let freeMinutes = max(0, snapshot.freeMinutesPerDay ?? 60)
        if freeMinutes == 0 {
            store.shield.applications = ScreenTimePolicy.shieldedApplications(
                in: snapshot,
                now: now
            )
            return
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: snapshot.selection.applicationTokens,
            threshold: DateComponents(minute: freeMinutes),
            includesPastActivity: true
        )
        try center.startMonitoring(
            ScreenTimePolicy.dailyActivity,
            during: schedule,
            events: [ScreenTimePolicy.allowanceEvent: event]
        )

        store.shield.applications = snapshot.allowanceReached(at: now)
            ? ScreenTimePolicy.shieldedApplications(in: snapshot, now: now)
            : nil
    }

    static func stopAll() {
        let center = DeviceActivityCenter()
        center.stopMonitoring([ScreenTimePolicy.dailyActivity])
        stopAccessMonitoring(center: center)
        ManagedSettingsStore(named: ScreenTimePolicy.storeName).clearAllSettings()
    }

    static func scheduleAccessWindow(_ window: SharedAccessWindow) throws {
        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                from: window.startedAt
            ),
            intervalEnd: calendar.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                from: window.endsAt
            ),
            repeats: false
        )
        try DeviceActivityCenter().startMonitoring(
            ScreenTimePolicy.accessActivityName(for: window.id),
            during: schedule
        )
    }

    private static func stopAccessMonitoring(center: DeviceActivityCenter) {
        let accessActivities = center.activities.filter {
            $0.rawValue.hasPrefix(ScreenTimePolicy.accessActivityPrefix)
        }
        if !accessActivities.isEmpty {
            center.stopMonitoring(accessActivities)
        }
    }
}
