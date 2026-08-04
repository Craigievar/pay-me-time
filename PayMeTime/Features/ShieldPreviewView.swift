import SwiftUI

struct ShieldPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let store: AppStore
    @State private var mode: ShieldMode

    init(store: AppStore) {
        self.store = store
        _mode = State(initialValue: store.creditMicrocents == 0 ? .empty : .freeTime)
    }

    private var app: AppRule {
        store.protectedApps.first(where: { $0.name == "TikTok" }) ?? store.protectedApps[0]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Shield state", selection: $mode) {
                    Text("Free").tag(ShieldMode.freeTime)
                    Text("Access").tag(ShieldMode.credit)
                    Text("No balance").tag(ShieldMode.empty)
                }
                .pickerStyle(.segmented)
                .padding()

                ShieldSurface(
                    mode: mode,
                    appName: app.name,
                    rate: store.effectiveRate(for: app),
                    freeMinutes: 42,
                    balance: store.creditMicrocents,
                    proceed: {
                        if mode == .empty {
                            mode = .credit
                        } else {
                            _ = store.startWindow(for: app)
                            dismiss()
                        }
                    },
                    pass: {
                        store.trackShieldBack(source: "app_shield_preview")
                        dismiss()
                    },
                    disable: {
                        store.disableProtection()
                        dismiss()
                    }
                )
            }
            .background(PMTTheme.canvas)
            .navigationTitle("App shield")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ShieldSurface: View {
    let mode: ShieldMode
    let appName: String
    let rate: Int
    let freeMinutes: Int
    let balance: Int64
    let proceed: () -> Void
    let pass: () -> Void
    let disable: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            ZStack {
                Circle()
                    .fill((mode == .empty ? PMTTheme.stone : PMTTheme.amber).opacity(0.12))
                    .frame(width: 104, height: 104)
                Image(systemName: mode == .empty ? "hourglass" : "exclamationmark.shield")
                    .font(.system(size: 43, weight: .medium))
                    .foregroundStyle(mode == .empty ? PMTTheme.stone : PMTTheme.amber)
            }

            VStack(spacing: 14) {
                Text(mode == .empty ? "No access balance available" : "Use your time carefully.")
                    .font(.system(.title, design: .serif, weight: .bold))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("shield.title")

                if mode == .empty {
                    Text("Go back, wait for your daily time to reset, or manage protection in Screenbump.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    Text("You set your protection at \(rate)¢ per hour.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Text("Your time is worth way more than pennies.")
                        .font(.title3.italic())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if mode == .freeTime {
                        Text("\(freeMinutes) minutes remain before protection begins.")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(PMTTheme.sage)
                    } else {
                        Text("\(Money.balance(balance)) left")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .foregroundStyle(PMTTheme.sage)
                    }
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button(mode == .empty ? "Manage access" : "Start access window", action: proceed)
                    .pmtPrimaryButton()
                    .accessibilityIdentifier("shield.proceed")

                Button("Go back", action: pass)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(PMTTheme.surface)
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.primary.opacity(0.25))
                    }

                if mode == .empty {
                    Button("Or, disable this block and stop protecting your time", action: disable)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .accessibilityIdentifier("shield.disable")
                }
            }
        }
        .padding(24)
        .background(PMTTheme.canvas)
    }
}
