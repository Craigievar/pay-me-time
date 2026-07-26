import DeviceActivity

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        AnalyticsSharedRepository.enqueue(
            AnalyticsEvent(
                name: "free allowance reached",
                properties: [
                    "source": .string("device_activity_monitor"),
                ]
            )
        )
        // The physical-device slice will apply the configured ManagedSettings
        // shield and publish the latest App Group snapshot here.
    }
}
