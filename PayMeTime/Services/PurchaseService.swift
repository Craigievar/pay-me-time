import Foundation
import OSLog
import StoreKit

enum CreditProductCatalog: String, CaseIterable, Sendable {
    case oneDollar = "com.nonagon.screenbump.credit.100"
    case fiveDollars = "com.nonagon.screenbump.credit.500"
    case tenDollars = "com.nonagon.screenbump.credit.1000"
    case twentyFiveDollars = "com.nonagon.screenbump.credit.2500"

    var creditCents: Int {
        switch self {
        case .oneDollar:
            100
        case .fiveDollars:
            500
        case .tenDollars:
            1_000
        case .twentyFiveDollars:
            2_500
        }
    }

    var fixtureDisplayPrice: String {
        switch self {
        case .oneDollar:
            "$0.99"
        case .fiveDollars:
            "$4.99"
        case .tenDollars:
            "$9.99"
        case .twentyFiveDollars:
            "$24.99"
        }
    }

    static var productIDs: [String] {
        allCases.map(\.rawValue)
    }
}

struct CreditProduct: Identifiable, Equatable, Sendable {
    let id: String
    let creditCents: Int
    let displayPrice: String
}

struct VerifiedCreditTransaction: Sendable {
    let id: UInt64
    let productID: String
    let purchasedQuantity: Int
    let purchaseDate: Date
    let revocationDate: Date?
    private let finishHandler: @Sendable () async -> Void

    init(
        id: UInt64,
        productID: String,
        purchasedQuantity: Int = 1,
        purchaseDate: Date = .now,
        revocationDate: Date? = nil,
        finish: @escaping @Sendable () async -> Void = {}
    ) {
        self.id = id
        self.productID = productID
        self.purchasedQuantity = purchasedQuantity
        self.purchaseDate = purchaseDate
        self.revocationDate = revocationDate
        finishHandler = finish
    }

    func finish() async {
        await finishHandler()
    }
}

enum CreditPurchaseOutcome: Sendable {
    case success(VerifiedCreditTransaction)
    case pending
    case userCancelled
}

@MainActor
protocol PurchaseServicing {
    func products() async throws -> [CreditProduct]
    func purchase(productID: String) async throws -> CreditPurchaseOutcome
    func unfinishedTransactions() async -> [VerifiedCreditTransaction]
    func transactionUpdates() -> AsyncStream<VerifiedCreditTransaction>
}

enum PurchaseServiceError: LocalizedError {
    case productUnavailable
    case productMetadataMismatch
    case noValidProducts(returnedProductIDs: [String])
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            "This purchase is temporarily unavailable."
        case .productMetadataMismatch, .noValidProducts:
            "Screenbump couldn’t load its App Store products. Try again."
        case .failedVerification:
            "The purchase could not be verified by the App Store."
        }
    }
}

@MainActor
final class StoreKitPurchaseService: PurchaseServicing {
    private static let logger = Logger(
        subsystem: "com.nonagon.Screenbump",
        category: "StoreKit"
    )
    private var productsByID: [String: Product] = [:]

    func products() async throws -> [CreditProduct] {
        let requestedProductIDs = CreditProductCatalog.productIDs
        Self.logDiagnostic(
            "Requesting products: \(requestedProductIDs.joined(separator: ", "))"
        )

        let storeProducts: [Product]
        do {
            storeProducts = try await Product.products(
                for: requestedProductIDs
            )
        } catch {
            let storeError = error as NSError
            Self.logDiagnostic(
                "Product request failed: domain=\(storeError.domain) code=\(storeError.code) message=\(storeError.localizedDescription)",
                isError: true
            )
            throw error
        }

        let returnedProducts = storeProducts.map { product in
            "\(product.id) [\(String(describing: product.type))]"
        }
        Self.logDiagnostic(
            "Returned \(storeProducts.count) products: \(returnedProducts.joined(separator: ", "))"
        )
        let validProducts = storeProducts.filter { product in
            CreditProductCatalog(rawValue: product.id) != nil
                && product.type == .consumable
        }
        productsByID = Dictionary(
            uniqueKeysWithValues: validProducts.map { ($0.id, $0) }
        )

        guard !validProducts.isEmpty else {
            Self.logDiagnostic(
                "Returned no valid consumable credit products.",
                isError: true
            )
            throw PurchaseServiceError.noValidProducts(
                returnedProductIDs: storeProducts.map(\.id)
            )
        }

        let missingProductIDs = Set(CreditProductCatalog.productIDs)
            .subtracting(validProducts.map(\.id))
            .sorted()
        if !missingProductIDs.isEmpty {
            Self.logDiagnostic(
                "Catalog is missing product IDs: \(missingProductIDs.joined(separator: ", "))"
            )
        }

        return validProducts.compactMap { product in
            guard let catalogProduct = CreditProductCatalog(rawValue: product.id)
            else {
                return nil
            }
            return CreditProduct(
                id: product.id,
                creditCents: catalogProduct.creditCents,
                displayPrice: product.displayPrice
            )
        }
        .sorted { $0.creditCents < $1.creditCents }
    }

    private static func logDiagnostic(
        _ message: String,
        isError: Bool = false
    ) {
        if isError {
            logger.error("\(message, privacy: .public)")
        } else {
            logger.notice("\(message, privacy: .public)")
        }
#if DEBUG
        print("SCREENBUMP_STOREKIT \(message)")
#endif
    }

    func purchase(productID: String) async throws -> CreditPurchaseOutcome {
        guard CreditProductCatalog(rawValue: productID) != nil else {
            throw PurchaseServiceError.productUnavailable
        }
        if productsByID[productID] == nil {
            _ = try await products()
        }
        guard let product = productsByID[productID] else {
            throw PurchaseServiceError.productUnavailable
        }

        switch try await product.purchase() {
        case .success(let verificationResult):
            switch verificationResult {
            case .verified(let transaction):
                return .success(Self.creditTransaction(from: transaction))
            case .unverified:
                throw PurchaseServiceError.failedVerification
            }
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            throw PurchaseServiceError.productUnavailable
        }
    }

    func unfinishedTransactions() async -> [VerifiedCreditTransaction] {
        var transactions: [VerifiedCreditTransaction] = []
        for await verificationResult in Transaction.unfinished {
            guard case .verified(let transaction) = verificationResult else {
                continue
            }
            guard CreditProductCatalog(rawValue: transaction.productID) != nil
            else {
                await transaction.finish()
                continue
            }
            transactions.append(Self.creditTransaction(from: transaction))
        }
        return transactions
    }

    func transactionUpdates() -> AsyncStream<VerifiedCreditTransaction> {
        AsyncStream { continuation in
            let task = Task(priority: .background) {
                for await verificationResult in Transaction.updates {
                    guard !Task.isCancelled else { break }
                    guard case .verified(let transaction) = verificationResult
                    else {
                        continue
                    }
                    guard
                        CreditProductCatalog(rawValue: transaction.productID)
                            != nil
                    else {
                        await transaction.finish()
                        continue
                    }
                    continuation.yield(
                        Self.creditTransaction(from: transaction)
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func creditTransaction(
        from transaction: Transaction
    ) -> VerifiedCreditTransaction {
        VerifiedCreditTransaction(
            id: transaction.id,
            productID: transaction.productID,
            purchasedQuantity: transaction.purchasedQuantity,
            purchaseDate: transaction.purchaseDate,
            revocationDate: transaction.revocationDate,
            finish: {
                await transaction.finish()
            }
        )
    }
}

@MainActor
final class FixturePurchaseService: PurchaseServicing {
    private var nextTransactionID: UInt64 = 1
    private let availableCatalog: [CreditProductCatalog]
    private let productsError: PurchaseServiceError?

    init(
        availableCatalog: [CreditProductCatalog] = CreditProductCatalog.allCases,
        productsError: PurchaseServiceError? = nil
    ) {
        self.availableCatalog = availableCatalog
        self.productsError = productsError
    }

    func products() async throws -> [CreditProduct] {
        if let productsError {
            throw productsError
        }
        return availableCatalog.map { product in
            CreditProduct(
                id: product.rawValue,
                creditCents: product.creditCents,
                displayPrice: product.fixtureDisplayPrice
            )
        }
    }

    func purchase(productID: String) async throws -> CreditPurchaseOutcome {
        guard CreditProductCatalog(rawValue: productID) != nil else {
            throw PurchaseServiceError.productUnavailable
        }
        defer { nextTransactionID += 1 }
        return .success(
            VerifiedCreditTransaction(
                id: nextTransactionID,
                productID: productID
            )
        )
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
