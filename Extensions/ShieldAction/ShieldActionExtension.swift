import DeviceActivity
import Foundation
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let tokenKey = ScreenTimeSharedRepository.tokenKey(application)
        var properties: [String: AnalyticsPropertyValue] = [
            "source": .string("system_shield"),
        ]
        if let anonymousAppID = AnalyticsSharedRepository.anonymousAppID(
            forTokenKey: tokenKey
        ) {
            properties["anonymous_app_id"] = .string(anonymousAppID)
        }

        switch action {
        case .primaryButtonPressed:
            properties["action"] = .string("pay")
            let now = Date.now
            var snapshot = ScreenTimeSharedRepository.load()
            snapshot.normalizeDay(at: now)
            let rate = snapshot.rate(for: application)
            let windowMinutes = max(1, snapshot.defaultWindowMinutes ?? 15)
            let cost = Money.windowCost(
                rateCentsPerHour: rate,
                minutes: windowMinutes
            )
            let window = SharedAccessWindow(
                id: UUID(),
                token: application,
                startedAt: now.addingTimeInterval(2),
                endsAt: now.addingTimeInterval(TimeInterval(windowMinutes * 60)),
                reservedMicrocents: cost,
                rateCentsPerHour: rate
            )

            do {
                try ScreenTimeMonitoringService.scheduleAccessWindow(window)
            } catch {
                properties["result"] = .string("schedule_failed")
                AnalyticsSharedRepository.enqueue(
                    AnalyticsEvent(
                        name: "shield action selected",
                        properties: properties
                    )
                )
                completionHandler(.close)
                return
            }

            let reserved = ScreenTimeSharedRepository.update { snapshot in
                let tokenKey = ScreenTimeSharedRepository.tokenKey(application)
                guard
                    !(snapshot.activeAccessWindows ?? []).contains(
                        where: { $0.token == application && $0.endsAt > now }
                    ),
                    snapshot.reserve(
                        costMicrocents: cost,
                        forTokenKey: tokenKey,
                        at: now
                    )
                else {
                    return false
                }
                snapshot.activeAccessWindows = (snapshot.activeAccessWindows ?? []) + [window]
                return true
            }

            guard reserved else {
                DeviceActivityCenter().stopMonitoring([
                    ScreenTimePolicy.accessActivityName(for: window.id)
                ])
                properties["result"] = .string("insufficient_credit")
                AnalyticsSharedRepository.enqueue(
                    AnalyticsEvent(
                        name: "shield action selected",
                        properties: properties
                    )
                )
                completionHandler(.close)
                return
            }

            let updatedSnapshot = ScreenTimeSharedRepository.load()
            ManagedSettingsStore(named: ScreenTimePolicy.storeName)
                .shield
                .applications = ScreenTimePolicy.shieldedApplications(
                    in: updatedSnapshot,
                    now: now
                )
            properties["result"] = .string("window_started")
            properties["window_minutes"] = .integer(windowMinutes)
            properties["reserved_microcents"] = .integer(Int(cost))
            AnalyticsSharedRepository.enqueue(
                AnalyticsEvent(
                    name: "shield action selected",
                    properties: properties
                )
            )
            completionHandler(.defer)
        case .secondaryButtonPressed:
            properties["action"] = .string("go_back")
            AnalyticsSharedRepository.enqueue(
                AnalyticsEvent(
                    name: "shield action selected",
                    properties: properties
                )
            )
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }
}
