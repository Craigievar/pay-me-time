import SwiftUI

struct RefillView: View {
    @Environment(\.dismiss) private var dismiss
    let store: AppStore
    let source: String
    @State private var selectedCents = 100
    private let packs = [100, 500, 1_000, 2_500]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                        ForEach(packs, id: \.self) { cents in
                            let product = store.creditProduct(cents: cents)
                            Button {
                                selectedCents = cents
                                store.trackRefillPackSelected(cents: cents)
                            } label: {
                                VStack(spacing: 6) {
                                    Text(packName(for: cents))
                                        .font(.title2.weight(.semibold))

                                    if let product {
                                        Text(product.displayPrice)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    } else if productsAreLoading {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("Unavailable")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .accessibilityIdentifier(
                                                "refill.unavailable.\(cents)"
                                            )
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 88)
                                .padding(.vertical, 4)
                                .background(PMTTheme.surface)
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            selectedCents == cents && product != nil
                                                ? PMTTheme.amber
                                                : .primary.opacity(0.12),
                                            lineWidth: selectedCents == cents
                                                && product != nil ? 2 : 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("refill.\(cents)")
                            .disabled(product == nil || purchaseIsBusy)
                        }
                    }

                    Text("Purchased access balance is used only for optional access windows. It has no cash value.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("refill.noValueWarning")

                    purchaseStatus
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(PMTTheme.canvas)
            .navigationTitle("Add access")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let confirmButtonTitle {
                    VStack(spacing: 0) {
                        Divider()

                        Button {
                            Task {
                                if await store.purchaseCredit(
                                    cents: selectedCents
                                ) {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if confirmShowsProgress {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(confirmButtonTitle)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .pmtPrimaryButton()
                        .accessibilityIdentifier("refill.confirm")
                        .disabled(selectedProduct == nil || purchaseIsBusy)
                        .padding(20)
                    }
                    .background(PMTTheme.canvas)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Cancel")
                    .accessibilityIdentifier("refill.cancel")
                }
            }
            .toolbarBackground(PMTTheme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            store.trackScreen("refill")
            store.trackRefillOpened(source: source)
            await store.loadCreditProducts()
            selectFirstAvailableProductIfNeeded()
        }
        .onChange(of: store.creditProducts) {
            selectFirstAvailableProductIfNeeded()
        }
    }

    @ViewBuilder
    private var purchaseStatus: some View {
        switch store.creditPurchaseState {
        case .pending:
            Label(
                "Purchase pending. Access balance will be added after approval.",
                systemImage: "clock"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("refill.pending")
        case .partial(let message):
            recoveryStatus(
                message: message,
                systemImage: "exclamationmark.triangle",
                accessibilityIdentifier: "refill.partial"
            )
        case .failed(let message):
            recoveryStatus(
                message: message,
                systemImage: "exclamationmark.circle",
                accessibilityIdentifier: "refill.error"
            )
        case .idle, .loading, .purchasing:
            EmptyView()
        }
    }

    private func recoveryStatus(
        message: String,
        systemImage: String,
        accessibilityIdentifier: String
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(accessibilityIdentifier)

            retryButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var retryButton: some View {
        Button("Try again") {
            Task {
                await store.loadCreditProducts(forceReload: true)
                selectFirstAvailableProductIfNeeded()
            }
        }
        .font(.footnote.weight(.semibold))
        .accessibilityIdentifier("refill.retry")
    }

    private var selectedProduct: CreditProduct? {
        store.creditProduct(cents: selectedCents)
    }

    private var confirmButtonTitle: String? {
        switch store.creditPurchaseState {
        case .failed:
            return nil
        case .pending:
            return "Purchase pending"
        case .idle, .loading, .purchasing, .partial:
            break
        }

        if let selectedProduct {
            return "Buy \(packName(for: selectedCents)) · \(selectedProduct.displayPrice)"
        }

        if case .partial = store.creditPurchaseState {
            return "Choose an available option"
        }

        return "Loading purchase options…"
    }

    private var purchaseIsBusy: Bool {
        switch store.creditPurchaseState {
        case .loading, .purchasing, .pending:
            true
        case .idle, .partial, .failed:
            false
        }
    }

    private var productsAreLoading: Bool {
        if case .loading = store.creditPurchaseState {
            return true
        }
        return store.creditProducts.isEmpty
            && store.creditPurchaseState == .idle
    }

    private var confirmShowsProgress: Bool {
        if case .loading = store.creditPurchaseState {
            return true
        }
        return selectedPurchaseIsProcessing
    }

    private var selectedPurchaseIsProcessing: Bool {
        guard case .purchasing(let creditCents) = store.creditPurchaseState else {
            return false
        }
        return creditCents == selectedCents
    }

    private func selectFirstAvailableProductIfNeeded() {
        guard selectedProduct == nil,
            let firstAvailableProduct = store.creditProducts.first
        else {
            return
        }
        selectedCents = firstAvailableProduct.creditCents
    }

    private func packName(for cents: Int) -> String {
        switch cents {
        case 100:
            "Small Access Pack"
        case 500:
            "Standard Access Pack"
        case 1_000:
            "Large Access Pack"
        case 2_500:
            "Extended Access Pack"
        default:
            "Access Pack"
        }
    }
}
