import SwiftUI

struct RefillView: View {
    @Environment(\.dismiss) private var dismiss
    let store: AppStore
    let source: String
    @State private var selectedCents = 100
    private let packs = [100, 500, 1_000, 2_500]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Refill commitment credit")
                        .font(.system(.title, design: .serif, weight: .semibold))
                    Text("Keep the money moment in front of mind. Credit never expires.")
                        .foregroundStyle(.secondary)
                }

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

                Spacer()

                Button("Add $\(selectedCents / 100) credit") {
                    store.addCredit(cents: selectedCents)
                    dismiss()
                }
                .pmtPrimaryButton()
                .accessibilityIdentifier("refill.confirm")
            }
            .padding(20)
            .background(PMTTheme.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            store.trackScreen("refill")
            store.trackRefillOpened(source: source)
        }
    }
}
