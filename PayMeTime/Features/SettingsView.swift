import SwiftUI

private enum SettingsSheet: Identifiable {
    case refill

    var id: String { "refill" }
}

struct SettingsView: View {
    let store: AppStore
    @State private var sheet: SettingsSheet?

    var body: some View {
        Form {
            Section("Protection") {
                Toggle("Protection enabled", isOn: Binding(
                    get: { store.protectionEnabled },
                    set: { $0 ? store.enableProtection() : store.disableProtection() }
                ))
                LabeledContent("Daily free time", value: "\(store.freeMinutesPerDay) min")
                LabeledContent("Default charge rate", value: "\(store.globalRateCents)¢ / hour")
            }

            Section("Credit") {
                LabeledContent("Balance", value: Money.balance(store.creditMicrocents))
            }

            if store.analyticsAvailable {
                Section {
                    Toggle(
                        "Share anonymous analytics",
                        isOn: Binding(
                            get: { store.anonymousAnalyticsEnabled },
                            set: { store.setAnonymousAnalyticsEnabled($0) }
                        )
                    )
                } footer: {
                    Text("Includes app interactions and aggregate Screen Time trends. App names and Screen Time tokens are never sent.")
                }
            }

            Section {
                Button {
                    sheet = .refill
                } label: {
                    Label("Buy more credits", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .pmtPrimaryButton()
                .accessibilityIdentifier("settings.buyCredits")
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PMTTheme.canvas)
        .navigationTitle("Settings")
        .sheet(item: $sheet) { item in
            switch item {
            case .refill:
                RefillView(store: store, source: "settings")
            }
        }
        .task {
            store.trackScreen("settings")
        }
    }
}
