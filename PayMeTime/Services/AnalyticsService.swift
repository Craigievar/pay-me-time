import Foundation
import PostHog

@MainActor
protocol AnalyticsTracking: AnyObject {
    var isAvailable: Bool { get }
    var collectionEnabled: Bool { get }

    func capture(_ event: AnalyticsEvent)
    func flushSharedEvents()
}

@MainActor
final class NoopAnalyticsTracker: AnalyticsTracking {
    let isAvailable = false
    let collectionEnabled = false

    func capture(_ event: AnalyticsEvent) {}
    func flushSharedEvents() {}
}

@MainActor
final class PostHogAnalyticsTracker: AnalyticsTracking {
    private static let legacyCollectionPreferenceKey =
        "anonymous-analytics-enabled-v1"

    let isAvailable: Bool
    let collectionEnabled: Bool

    private init(projectToken: String?) {
        guard
            let projectToken,
            !projectToken.isEmpty,
            !projectToken.hasPrefix("$(")
        else {
            isAvailable = false
            collectionEnabled = false
            AnalyticsSharedRepository.setCollectionEnabled(false)
            return
        }

        isAvailable = true
        collectionEnabled = true
        let config = PostHogConfig(
            projectToken: projectToken,
            host: "https://us.i.posthog.com"
        )
        config.appGroupIdentifier = AnalyticsSharedRepository.appGroupID
        config.personProfiles = .never
        config.setDefaultPersonProperties = false
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = true
        config.captureElementInteractions = true
        config.enableSwizzling = true
        config.sessionReplay = false
        config.errorTrackingConfig.autoCapture = false
        config.surveys = false
        config.preloadFeatureFlags = false
        config.optOut = false
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.optIn()

        UserDefaults.standard.removeObject(
            forKey: Self.legacyCollectionPreferenceKey
        )
        AnalyticsSharedRepository.setCollectionEnabled(true)
        flushSharedEvents()
    }

    static func bootstrap(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        bundle: Bundle = .main
    ) -> any AnalyticsTracking {
        if arguments.contains("--ui-testing")
            || arguments.contains(where: { $0.hasPrefix("--fixture=") }) {
            return NoopAnalyticsTracker()
        }

        let projectToken = bundle.object(
            forInfoDictionaryKey: "PostHogProjectToken"
        ) as? String
        return PostHogAnalyticsTracker(projectToken: projectToken)
    }

    func capture(_ event: AnalyticsEvent) {
        guard isAvailable, collectionEnabled else { return }
        var properties = event.properties.mapValues(\.foundationValue)
        properties["analytics_schema_version"] = 1
        properties["event_created_at"] = ISO8601DateFormatter().string(from: event.createdAt)
        PostHogSDK.shared.capture(event.name, properties: properties)
    }

    func flushSharedEvents() {
        guard isAvailable, collectionEnabled else { return }
        for event in AnalyticsSharedRepository.drainQueuedEvents() {
            capture(event)
        }
        PostHogSDK.shared.flush()
    }
}
