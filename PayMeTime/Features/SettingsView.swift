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
                LabeledContent("Default access rate", value: "\(store.globalRateCents)¢ / hour")
            }

            Section("Access balance") {
                LabeledContent("Available", value: Money.balance(store.creditMicrocents))
            }

            Section {
                Button {
                    sheet = .refill
                } label: {
                    Label("Add access balance", systemImage: "plus.circle.fill")
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
