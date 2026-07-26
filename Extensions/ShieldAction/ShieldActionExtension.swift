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
            AnalyticsSharedRepository.enqueue(
                AnalyticsEvent(
                    name: "shield action selected",
                    properties: properties
                )
            )
            // The physical-device slice will atomically reserve credit and remove
            // this token from the named ManagedSettingsStore before returning.
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
