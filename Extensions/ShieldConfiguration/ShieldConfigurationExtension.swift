import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration(for: application.token)
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(for: application.token)
    }

    private func configuration(for token: ApplicationToken?) -> ShieldConfiguration {
        let snapshot = ScreenTimeSharedRepository.load()
        let rate = token.map { snapshot.rate(for: $0) }
            ?? HourlyRatePolicy.clamped(snapshot.globalRateCents)
        let windowMinutes = max(1, snapshot.defaultWindowMinutes ?? 15)
        let cost = Money.windowCost(
            rateCentsPerHour: rate,
            minutes: windowMinutes
        )
        let hasCredit = (snapshot.creditMicrocents ?? 0) >= cost
        let title = hasCredit
            ? "Protection started"
            : "No access balance available"
        let subtitle = hasCredit
            ? "Start an optional \(windowMinutes)-minute access window. Uses \(Money.compactCost(cost)) from your \(Money.balance(snapshot.creditMicrocents ?? 0)) access balance."
            : "Open Screenbump to add access or manage protection."
        let primaryLabel = hasCredit
            ? "Start \(windowMinutes) min · \(Money.compactCost(cost))"
            : "Not enough credit"

        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: UIColor(red: 0.965, green: 0.945, blue: 0.91, alpha: 1),
            icon: UIImage(systemName: "exclamationmark.shield"),
            title: .init(
                text: title,
                color: UIColor(red: 0.153, green: 0.145, blue: 0.129, alpha: 1)
            ),
            subtitle: .init(
                text: subtitle,
                color: .secondaryLabel
            ),
            primaryButtonLabel: .init(text: primaryLabel, color: .white),
            primaryButtonBackgroundColor: UIColor(red: 0.784, green: 0.475, blue: 0.122, alpha: 1),
            secondaryButtonLabel: .init(text: "Go Back", color: .label)
        )
    }
}
