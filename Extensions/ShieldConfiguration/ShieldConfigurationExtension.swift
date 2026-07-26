import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration()
    }

    private func configuration() -> ShieldConfiguration {
        let rate = 1
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: UIColor(red: 0.965, green: 0.945, blue: 0.91, alpha: 1),
            icon: UIImage(systemName: "exclamationmark.shield"),
            title: .init(
                text: "Use your time carefully. It costs you!",
                color: UIColor(red: 0.153, green: 0.145, blue: 0.129, alpha: 1)
            ),
            subtitle: .init(
                text: "You decided to charge yourself \(rate)¢ per hour to use this app.\n\nYour time is worth way more than those pennies.\n\nYou currently have 42 minutes of time left before you're charged credits.",
                color: .secondaryLabel
            ),
            primaryButtonLabel: .init(text: "Proceed", color: .white),
            primaryButtonBackgroundColor: UIColor(red: 0.784, green: 0.475, blue: 0.122, alpha: 1),
            secondaryButtonLabel: .init(text: "I’ll pass", color: .label)
        )
    }
}
