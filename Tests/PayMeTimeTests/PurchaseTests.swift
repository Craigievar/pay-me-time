import Foundation
import StoreKitTest
import Testing
@testable import PayMeTime

@MainActor
private final class FinishRecorder {
    private(set) var transactionIDs: [UInt64] = []

    func record(_ transactionID: UInt64) {
        transactionIDs.append(transactionID)
    }
}

@MainActor
private final class TestPurchaseService: PurchaseServicing {
    var loadedProducts: [CreditProduct]
    var outcomes: [CreditPurchaseOutcome]
    var productsError: PurchaseServiceError?

    init(
        loadedProducts: [CreditProduct] = CreditProductCatalog.allCases.map {
            CreditProduct(
                id: $0.rawValue,
                creditCents: $0.creditCents,
                displayPrice: $0.fixtureDisplayPrice
            )
        },
        outcomes: [CreditPurchaseOutcome],
        productsError: PurchaseServiceError? = nil
    ) {
        self.loadedProducts = loadedProducts
        self.outcomes = outcomes
        self.productsError = productsError
    }

    func products() async throws -> [CreditProduct] {
        if let productsError {
            throw productsError
        }
        return loadedProducts
    }

    func purchase(productID: String) async throws -> CreditPurchaseOutcome {
        guard !outcomes.isEmpty else {
            throw PurchaseServiceError.productUnavailable
        }
        return outcomes.removeFirst()
    }

    func unfinishedTransactions() async -> [VerifiedCreditTransaction] {
        []
    }

    func transactionUpdates() -> AsyncStream<VerifiedCreditTransaction> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
struct PurchaseTests {
    @Test
    func catalogMatchesPermanentAppStoreConnectProductIDs() {
        #expect(CreditProductCatalog.productIDs == [
            "com.nonagon.screenbump.credit.100",
            "com.nonagon.screenbump.credit.500",
            "com.nonagon.screenbump.credit.1000",
            "com.nonagon.screenbump.credit.2500",
        ])
    }

    @Test
    func localStoreKitConfigurationLoadsTheLaunchCatalog() async throws {
        let session = try SKTestSession(
            configurationFileNamed: "Screenbump"
        )
        session.disableDialogs = true
        session.clearTransactions()

        let service = StoreKitPurchaseService()
        let products = try await service.products()

        #expect(products.map(\.id) == CreditProductCatalog.productIDs)
        #expect(products.map(\.creditCents) == [100, 500, 1_000, 2_500])
    }

    @Test
    func localStoreKitPurchaseReturnsVerifiedCreditTransaction() async throws {
        let session = try SKTestSession(
            configurationFileNamed: "Screenbump"
        )
        session.disableDialogs = true
        session.clearTransactions()

        let service = StoreKitPurchaseService()
        _ = try await service.products()
        let outcome = try await service.purchase(
            productID: CreditProductCatalog.oneDollar.rawValue
        )

        switch outcome {
        case .success(let transaction):
            #expect(
                transaction.productID
                    == CreditProductCatalog.oneDollar.rawValue
            )
            #expect(transaction.purchasedQuantity == 1)
            await transaction.finish()
        case .pending, .userCancelled:
            Issue.record("The local StoreKit purchase did not complete.")
        }
    }

    @Test
    func verifiedPurchaseAddsCreditThenFinishes() async {
        let recorder = FinishRecorder()
        let transaction = VerifiedCreditTransaction(
            id: 101,
            productID: CreditProductCatalog.oneDollar.rawValue,
            finish: {
                await recorder.record(101)
            }
        )
        let service = TestPurchaseService(
            outcomes: [.success(transaction)]
        )
        let store = AppStore(
            arguments: ["PayMeTime", "--fixture=standard"],
            purchaseService: service
        )
        let initialBalance = store.creditMicrocents

        await store.loadCreditProducts()
        let purchased = await store.purchaseCredit(cents: 100)

        #expect(purchased)
        #expect(
            store.creditMicrocents
                == initialBalance + 100 * Money.microcentsPerCent
        )
        #expect(recorder.transactionIDs == [101])
    }

    @Test
    func partialCatalogKeepsAvailableProductsPurchasable() async {
        let transaction = VerifiedCreditTransaction(
            id: 111,
            productID: CreditProductCatalog.fiveDollars.rawValue
        )
        let availableProduct = CreditProduct(
            id: CreditProductCatalog.fiveDollars.rawValue,
            creditCents: CreditProductCatalog.fiveDollars.creditCents,
            displayPrice: CreditProductCatalog.fiveDollars.fixtureDisplayPrice
        )
        let service = TestPurchaseService(
            loadedProducts: [availableProduct],
            outcomes: [.success(transaction)]
        )
        let store = AppStore(
            arguments: ["PayMeTime", "--fixture=standard"],
            purchaseService: service
        )
        let initialBalance = store.creditMicrocents

        await store.loadCreditProducts()

        #expect(store.creditProducts == [availableProduct])
        guard case .partial(let message) = store.creditPurchaseState else {
            Issue.record("A partial catalog should remain usable.")
            return
        }
        #expect(message.contains("returned only some purchase options"))
        #expect(await store.purchaseCredit(cents: 500))
        #expect(
            store.creditMicrocents
                == initialBalance + 500 * Money.microcentsPerCent
        )
    }

    @Test
    func catalogFailureDoesNotLeavePurchaseOptionsLoading() async {
        let service = TestPurchaseService(
            outcomes: [],
            productsError: .productMetadataMismatch
        )
        let store = AppStore(
            arguments: ["PayMeTime", "--fixture=standard"],
            purchaseService: service
        )

        await store.loadCreditProducts()

        #expect(store.creditProducts.isEmpty)
        guard case .failed(let message) = store.creditPurchaseState else {
            Issue.record("An empty failed catalog should expose an error.")
            return
        }
        #expect(message.contains("couldn’t load its App Store products"))
    }

    @Test
    func failedRefreshPreservesPreviouslyLoadedProducts() async {
        let availableProduct = CreditProduct(
            id: CreditProductCatalog.oneDollar.rawValue,
            creditCents: CreditProductCatalog.oneDollar.creditCents,
            displayPrice: CreditProductCatalog.oneDollar.fixtureDisplayPrice
        )
        let service = TestPurchaseService(
            loadedProducts: [availableProduct],
            outcomes: []
        )
        let store = AppStore(
            arguments: ["PayMeTime", "--fixture=standard"],
            purchaseService: service
        )

        await store.loadCreditProducts()
        service.productsError = .productUnavailable
        await store.loadCreditProducts(forceReload: true)

        #expect(store.creditProducts == [availableProduct])
        guard case .partial(let message) = store.creditPurchaseState else {
            Issue.record("A failed refresh should preserve usable products.")
            return
        }
        #expect(message.contains("couldn’t refresh every price"))
    }

    @Test
    func duplicateTransactionDoesNotGrantCreditTwice() async {
        let transaction = VerifiedCreditTransaction(
            id: 202,
            productID: CreditProductCatalog.fiveDollars.rawValue
        )
        let service = TestPurchaseService(
            outcomes: [.success(transaction), .success(transaction)]
        )
        let store = AppStore(
            arguments: ["PayMeTime", "--fixture=standard"],
            purchaseService: service
        )
        let initialBalance = store.creditMicrocents

        await store.loadCreditProducts()
        #expect(await store.purchaseCredit(cents: 500))
        #expect(await store.purchaseCredit(cents: 500))

        #expect(
            store.creditMicrocents
                == initialBalance + 500 * Money.microcentsPerCent
        )
    }

    @Test
    func pendingPurchaseDoesNotGrantCredit() async {
        let service = TestPurchaseService(outcomes: [.pending])
        let store = AppStore(
            arguments: ["PayMeTime", "--fixture=standard"],
            purchaseService: service
        )
        let initialBalance = store.creditMicrocents

        await store.loadCreditProducts()
        let purchased = await store.purchaseCredit(cents: 100)

        #expect(!purchased)
        #expect(store.creditMicrocents == initialBalance)
        #expect(store.creditPurchaseState == .pending)
    }

    @Test
    func ledgerAppliesGrantAndRefundOnce() {
        let initialBalance = Int64(200) * Money.microcentsPerCent
        let purchaseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let refundDate = purchaseDate.addingTimeInterval(60)
        var snapshot = SharedScreenTimeSnapshot(
            creditMicrocents: initialBalance
        )
        let amount = Int64(100) * Money.microcentsPerCent

        #expect(
            snapshot.applyStoreKitCredit(
                transactionID: 303,
                productID: CreditProductCatalog.oneDollar.rawValue,
                amountMicrocents: amount,
                purchaseDate: purchaseDate,
                revocationDate: nil
            ) == .granted(amountMicrocents: amount)
        )
        #expect(
            snapshot.applyStoreKitCredit(
                transactionID: 303,
                productID: CreditProductCatalog.oneDollar.rawValue,
                amountMicrocents: amount,
                purchaseDate: purchaseDate,
                revocationDate: nil
            ) == .duplicate
        )
        #expect(snapshot.creditMicrocents == initialBalance + amount)

        #expect(
            snapshot.applyStoreKitCredit(
                transactionID: 303,
                productID: CreditProductCatalog.oneDollar.rawValue,
                amountMicrocents: amount,
                purchaseDate: purchaseDate,
                revocationDate: refundDate
            ) == .reversed(amountMicrocents: amount)
        )
        #expect(
            snapshot.applyStoreKitCredit(
                transactionID: 303,
                productID: CreditProductCatalog.oneDollar.rawValue,
                amountMicrocents: amount,
                purchaseDate: purchaseDate,
                revocationDate: refundDate
            ) == .duplicate
        )
        #expect(snapshot.creditMicrocents == initialBalance)
        #expect(snapshot.storeKitCreditLedger?.count == 2)
    }
}
