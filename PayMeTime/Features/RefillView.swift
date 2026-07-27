import SwiftUI

struct RefillView: View {
    @Environment(\.dismiss) private var dismiss
    let store: AppStore
    let source: String
    @State private var selectedCents = 100
    private let packs = [100, 500, 1_000, 2_500]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 22) {
                    Color.clear
                        .frame(height: 52)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Refill commitment credit")
                        .font(.system(.title, design: .serif, weight: .semibold))
                        .accessibilityIdentifier("refill.title")

                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                        ForEach(packs, id: \.self) { cents in
                            Button {
                                selectedCents = cents
                                store.trackRefillPackSelected(cents: cents)
                            } label: {
                                Text("$\(cents / 100)")
                                    .font(.title2.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 86)
                                    .background(PMTTheme.surface)
                                    .foregroundStyle(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(selectedCents == cents ? PMTTheme.amber : .primary.opacity(0.12), lineWidth: selectedCents == cents ? 2 : 1)
                                    }
                            }
                            .accessibilityIdentifier("refill.\(cents)")
                        }
                    }

                    Text("Commitment credit has no cash value and cannot be transferred or redeemed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("refill.noValueWarning")

                    Spacer()

                    Button("Add $\(selectedCents / 100) credit") {
                        store.addCredit(cents: selectedCents)
                        dismiss()
                    }
                    .pmtPrimaryButton()
                    .accessibilityIdentifier("refill.confirm")
                }
                .padding(20)

                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(PMTTheme.amber)
                    .frame(minWidth: 44, minHeight: 44)
                    .offset(x: -24, y: 52)
                    .accessibilityIdentifier("refill.cancel")
            }
            .background(PMTTheme.canvas)
        }
        .presentationDetents([.medium, .large])
        .task {
            store.trackScreen("refill")
            store.trackRefillOpened(source: source)
        }
    }
}
