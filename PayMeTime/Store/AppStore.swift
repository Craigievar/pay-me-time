import FamilyControls
import Foundation
import ManagedSettings
import Observation

enum CreditPurchaseState: Equatable {
    case idle
    case loading
    case partial(message: String)
    case purchasing(creditCents: Int)
    case pending
    case failed(message: String)
}

enum CreditPurchaseDeliveryError: LocalizedError {
    case invalidTransaction
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidTransaction:
            "The App Store returned an invalid credit transaction."
        case .persistenceFailed:
            "The purchase is verified, but Screenbump could not save the credit. It will retry automatically."
        }
    }
}

@MainActor
@Observable
final class AppStore {
    private struct SavedState: Codable {
        var onboardingComplete: Bool
        var globalRateCents: Int
        var freeMinutesPerDay: Int
        var creditMicrocents: Int64
        var protectedApps: [AppRule]
        var protectionEnabled: Bool
        var activeWindow: ActiveWindow?
        var defaultWindowMinutes: Int
        var starterCreditCentsGranted: Int?
        var starterCreditAnalyticsRecorded: Bool?
        var firstRundownRatingRequestHandled: Bool?
        var hasAddedPaidCredit: Bool?
    }

    private static let persistenceKey = "pay-me-time-state-v2"
    static let starterCreditCents = 200
    static let firstRundownRatingThresholdCents = starterCreditCents / 2
    private let persistenceEnabled: Bool
    private let analytics: any AnalyticsTracking
    private let purchaseService: any PurchaseServicing
    @ObservationIgnored
    private var purchaseUpdatesTask: Task<Void, Never>?
    private var fixtureStoreKitCreditLedger: [StoreKitCreditLedgerEntry] = []
    private var starterCreditCentsGranted: Int
    private var starterCreditAnalyticsRecorded: Bool
    private var firstRundownRatingRequestHandled: Bool
    private var hasAddedPaidCredit: Bool
    let fixtureName: String?
    private(set) var onboardingComplete: Bool
    private(set) var globalRateCents: Int
    private(set) var freeMinutesPerDay: Int
    private(set) var creditMicrocents: Int64
    private(set) var protectedApps: [AppRule]
    private(set) var protectionEnabled: Bool
    private(set) var activeWindow: ActiveWindow?
    private(set) var activitySelection: FamilyActivitySelection
    private(set) var applicationRateOverrides: [String: Int]
    private(set) var screenTimeAuthorizationStatus: AuthorizationStatus
    private(set) var screenTimeErrorMessage: String?
    private(set) var reportRevision = 0
    private(set) var analyticsMilestoneRequest: AnalyticsMilestoneRequest?
    private(set) var creditProducts: [CreditProduct]
    private(set) var creditPurchaseState: CreditPurchaseState

    let availableWindowMinutes = [5, 15, 30]
    private(set) var defaultWindowMinutes: Int

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        analytics: any AnalyticsTracking = NoopAnalyticsTracker(),
        purchaseService: (any PurchaseServicing)? = nil
    ) {
        let fixture = arguments.first(where: { $0.hasPrefix("--fixture=") })?
            .replacingOccurrences(of: "--fixture=", with: "")
        let purchaseFixture = arguments.first(where: {
            $0.hasPrefix("--purchase-fixture=")
        })?
            .replacingOccurrences(of: "--purchase-fixture=", with: "")
        self.analytics = analytics
        if let purchaseService {
            self.purchaseService = purchaseService
        } else if fixture == nil {
            self.purchaseService = StoreKitPurchaseService()
        } else {
            self.purchaseService = switch purchaseFixture {
            case "partial":
                FixturePurchaseService(
                    availableCatalog: [.oneDollar, .fiveDollars]
                )
            case "failed":
                FixturePurchaseService(
                    productsError: .productMetadataMismatch
                )
            default:
                FixturePurchaseService()
            }
        }
        fixtureName = fixture
        persistenceEnabled = fixture == nil

        let savedState: SavedState? = if fixture == nil,
            let data = UserDefaults.standard.data(forKey: Self.persistenceKey) {
            try? JSONDecoder().decode(SavedState.self, from: data)
        } else {
            nil
        }
        let priorStarterCreditCents = savedState?.starterCreditCentsGranted
            ?? (savedState == nil ? Self.starterCreditCents : 100)
        let starterCreditUpgrade = fixture == nil
            ? max(0, Self.starterCreditCents - priorStarterCreditCents)
            : 0
        let sharedSnapshot = ScreenTimeSharedRepository.load()

        starterCreditCentsGranted = Self.starterCreditCents
        starterCreditAnalyticsRecorded =
            savedState?.starterCreditAnalyticsRecorded ?? false
        firstRundownRatingRequestHandled =
            savedState?.firstRundownRatingRequestHandled ?? false
        hasAddedPaidCredit = savedState?.hasAddedPaidCredit ?? false
        onboardingComplete = fixture == "onboarding"
            ? false
            : savedState?.onboardingComplete ?? (fixture != nil)
        globalRateCents = HourlyRatePolicy.clamped(
            savedState?.globalRateCents
                ?? HourlyRatePolicy.defaultCentsPerHour
        )
        freeMinutesPerDay = savedState?.freeMinutesPerDay ?? 60
        let fixtureCreditMicrocents: Int64 = switch fixture {
        case "empty", "empty-shield":
            0
        case "rating":
            Int64(Self.firstRundownRatingThresholdCents)
                * Money.microcentsPerCent
        default:
            Int64(Self.starterCreditCents) * Money.microcentsPerCent
        }
        let existingCreditMicrocents =
            savedState?.creditMicrocents ?? fixtureCreditMicrocents
        creditMicrocents = fixture == nil
            ? sharedSnapshot.creditMicrocents
                ?? (
                    existingCreditMicrocents
                        + Int64(starterCreditUpgrade) * Money.microcentsPerCent
                )
            : (
                existingCreditMicrocents
                    + Int64(starterCreditUpgrade) * Money.microcentsPerCent
            )
        protectionEnabled = savedState?.protectionEnabled ?? true
        protectedApps = (
            savedState?.protectedApps ?? Self.fixtureApps(for: fixture)
        ).map { app in
            var app = app
            app.rateOverride = app.rateOverride.map(HourlyRatePolicy.clamped)
            return app
        }
        activeWindow = savedState?.activeWindow
        defaultWindowMinutes = savedState?.defaultWindowMinutes ?? 15
        activitySelection = fixture == nil ? sharedSnapshot.selection : FamilyActivitySelection()
        applicationRateOverrides = fixture == nil
            ? sharedSnapshot.rateOverrides.mapValues(HourlyRatePolicy.clamped)
            : [:]
        screenTimeAuthorizationStatus = fixture == nil
            ? ScreenTimeAuthorizationService.status
            : .approved
        screenTimeErrorMessage = nil
        analyticsMilestoneRequest = nil
        creditProducts = []
        creditPurchaseState = .idle

        if fixture == nil {
            let snapshot = syncSharedScreenTimeSnapshot()
            refreshScreenTimeMonitoring(using: snapshot)
            bootstrapSelectionAnalyticsIfNeeded()
            refreshAnalyticsMilestone()
            recordStarterCreditAnalyticsIfNeeded()
            if starterCreditUpgrade > 0 || starterCreditAnalyticsRecorded {
                persist()
            }
            startPurchaseMonitoring()
        }
    }

    func completeOnboarding() {
        onboardingComplete = true
        persist()
        refreshScreenTimeMonitoring(using: syncSharedScreenTimeSnapshot())
        analytics.capture(
            AnalyticsEvent(
                name: "onboarding completed",
                properties: [
                    "protected_app_count": .integer(protectedAppCount),
                    "free_minutes_per_day": .integer(freeMinutesPerDay),
                    "global_rate_cents_per_hour": .integer(globalRateCents),
                    "default_window_minutes": .integer(defaultWindowMinutes),
                ]
            )
        )
    }

    func updateGlobalRate(_ value: Int) {
        let previousValue = globalRateCents
        globalRateCents = HourlyRatePolicy.clamped(value)
        persist()
        syncSharedScreenTimeSnapshot()
        reportRevision += 1
        if globalRateCents != previousValue {
            analytics.capture(
                AnalyticsEvent(
                    name: "protection rate changed",
                    properties: [
                        "scope": .string("global"),
                        "previous_cents_per_hour": .integer(previousValue),
                        "cents_per_hour": .integer(globalRateCents),
                    ]
                )
            )
        }
    }

    func updateFreeMinutes(_ value: Int) {
        let previousValue = freeMinutesPerDay
        freeMinutesPerDay = min(max(value, 0), 240)
        persist()
        let snapshot = syncSharedScreenTimeSnapshot(resetAllowance: true)
        refreshScreenTimeMonitoring(using: snapshot)
        if freeMinutesPerDay != previousValue {
            analytics.capture(
                AnalyticsEvent(
                    name: "free allowance changed",
                    properties: [
                        "previous_minutes": .integer(previousValue),
                        "minutes": .integer(freeMinutesPerDay),
                    ]
                )
            )
        }
    }

    func effectiveRate(for app: AppRule) -> Int {
        HourlyRatePolicy.clamped(app.rateOverride ?? globalRateCents)
    }

    var protectedAppsByTimeSpent: [AppRule] {
        protectedApps.sorted {
            if $0.timeSpentTodaySeconds == $1.timeSpentTodaySeconds {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.timeSpentTodaySeconds > $1.timeSpentTodaySeconds
        }
    }

    func costToday(for app: AppRule) -> Int64 {
        app.costTodayMicrocents(rateCentsPerHour: effectiveRate(for: app))
    }

    func setRateOverride(appID: UUID, value: Int?) {
        guard let index = protectedApps.firstIndex(where: { $0.id == appID }) else { return }
        let override = value.map(HourlyRatePolicy.clamped)
        protectedApps[index].rateOverride = override
        persist()
        analytics.capture(
            AnalyticsEvent(
                name: "protection rate changed",
                properties: [
                    "scope": .string("fixture_app"),
                    "uses_global_default": .boolean(override == nil),
                    "cents_per_hour": .integer(override ?? globalRateCents),
                ]
            )
        )
    }

    var selectedApplications: [SelectedApplication] {
        activitySelection.applicationTokens
            .map(SelectedApplication.init(token:))
            .sorted { $0.id < $1.id }
    }

    var protectedAppCount: Int {
        fixtureName == nil ? activitySelection.applicationTokens.count : protectedApps.count
    }

    var shouldShowFirstRundownRatingCTA: Bool {
        onboardingComplete
            && Self.isFirstRundownRatingEligible(
                balanceMicrocents: creditMicrocents,
                hasAddedPaidCredit: hasAddedPaidCredit,
                requestHandled: firstRundownRatingRequestHandled
            )
    }

    static func isFirstRundownRatingEligible(
        balanceMicrocents: Int64,
        hasAddedPaidCredit: Bool,
        requestHandled: Bool
    ) -> Bool {
        let threshold = Int64(firstRundownRatingThresholdCents)
            * Money.microcentsPerCent
        return !hasAddedPaidCredit
            && !requestHandled
            && balanceMicrocents > 0
            && balanceMicrocents <= threshold
    }

    func effectiveRate(for token: ApplicationToken) -> Int {
        HourlyRatePolicy.clamped(
            applicationRateOverrides[
                ScreenTimeSharedRepository.tokenKey(token)
            ] ?? globalRateCents
        )
    }

    func setRateOverride(for token: ApplicationToken, value: Int?) {
        let key = ScreenTimeSharedRepository.tokenKey(token)
        let override = value.map(HourlyRatePolicy.clamped)
        applicationRateOverrides[key] = override
        if applicationRateOverrides[key] == nil {
            applicationRateOverrides.removeValue(forKey: key)
        }
        syncSharedScreenTimeSnapshot()
        reportRevision += 1
        analytics.capture(
            AnalyticsEvent(
                name: "protection rate changed",
                properties: [
                    "scope": .string("anonymized_app"),
                    "uses_global_default": .boolean(override == nil),
                    "cents_per_hour": .integer(override ?? globalRateCents),
                ]
            )
        )
    }

    func updateActivitySelection(_ selection: FamilyActivitySelection) {
        var applicationsOnly = selection
        applicationsOnly.categoryTokens = []
        applicationsOnly.webDomainTokens = []
        activitySelection = applicationsOnly

        let selectedKeys = Set(applicationsOnly.applicationTokens.map(ScreenTimeSharedRepository.tokenKey))
        applicationRateOverrides = applicationRateOverrides.filter { selectedKeys.contains($0.key) }
        syncSharedScreenTimeSnapshot(resetAllowance: true)
        reportRevision += 1
    }

    func finalizeActivitySelection(now: Date = .now) {
        let snapshot = syncSharedScreenTimeSnapshot(resetAllowance: true)
        refreshScreenTimeMonitoring(using: snapshot, now: now)
        guard
            persistenceEnabled,
            analytics.isAvailable,
            analytics.collectionEnabled
        else {
            return
        }
        let tokenKeys = activitySelection.applicationTokens.map(
            ScreenTimeSharedRepository.tokenKey
        )
        let previousCohort = AnalyticsSharedRepository.loadCohort()
        let cohort = AnalyticsSharedRepository.beginSelectionCohort(
            tokenKeys: tokenKeys,
            selectedAt: now
        )
        guard previousCohort?.tokenKeys != cohort?.tokenKeys else { return }

        if let cohort {
            analytics.capture(
                AnalyticsEvent(
                    name: "app selection completed",
                    properties: [
                        "selection_cohort_id": .string(
                            cohort.id.uuidString.lowercased()
                        ),
                        "app_count": .integer(cohort.appCount),
                        "is_initial_selection": .boolean(previousCohort == nil),
                    ]
                )
            )
        } else {
            analytics.capture(
                AnalyticsEvent(
                    name: "app selection cleared",
                    properties: [
                        "previous_app_count": .integer(previousCohort?.appCount ?? 0),
                    ]
                )
            )
        }
        refreshAnalyticsMilestone(now: now)
    }

    @discardableResult
    func requestScreenTimeAuthorization() async -> Bool {
        do {
            try await ScreenTimeAuthorizationService.request()
            screenTimeAuthorizationStatus = ScreenTimeAuthorizationService.status
            screenTimeErrorMessage = nil
            analytics.capture(
                AnalyticsEvent(
                    name: "screen time authorization completed",
                    properties: [
                        "approved": .boolean(
                            screenTimeAuthorizationStatus == .approved
                        ),
                    ]
                )
            )
            refreshScreenTimeMonitoring(using: syncSharedScreenTimeSnapshot())
            return screenTimeAuthorizationStatus == .approved
        } catch {
            screenTimeAuthorizationStatus = ScreenTimeAuthorizationService.status
            screenTimeErrorMessage = error.localizedDescription
            analytics.capture(
                AnalyticsEvent(
                    name: "screen time authorization completed",
                    properties: [
                        "approved": .boolean(false),
                        "status": .string(
                            String(describing: screenTimeAuthorizationStatus)
                        ),
                    ]
                )
            )
            return false
        }
    }

    func refreshScreenTimeAuthorizationStatus() {
        screenTimeAuthorizationStatus = ScreenTimeAuthorizationService.status
    }

    func creditProduct(cents: Int) -> CreditProduct? {
        creditProducts.first { $0.creditCents == cents }
    }

    func loadCreditProducts(forceReload: Bool = false) async {
        guard forceReload || creditProducts.isEmpty else { return }
        if case .purchasing = creditPurchaseState { return }

        creditPurchaseState = .loading
        do {
            let loadedProducts = try await purchaseService.products()
            let expectedProducts = loadedProducts.filter { product in
                guard
                    let catalogProduct = CreditProductCatalog(
                        rawValue: product.id
                    )
                else {
                    return false
                }
                return catalogProduct.creditCents == product.creditCents
            }
            guard !expectedProducts.isEmpty else {
                throw PurchaseServiceError.productMetadataMismatch
            }
            creditProducts = expectedProducts.sorted {
                $0.creditCents < $1.creditCents
            }
            creditPurchaseState = loadedCreditCatalogState
        } catch {
            captureStoreKitError(
                stage: "catalog_load",
                error: error,
                properties: [
                    "force_reload": .boolean(forceReload),
                    "cached_product_count": .integer(creditProducts.count),
                ]
            )
            if creditProducts.isEmpty {
                creditPurchaseState = .failed(
                    message: error.localizedDescription
                )
            } else {
                creditPurchaseState = .partial(
                    message: "The App Store couldn’t refresh every price. Try again."
                )
            }
        }
    }

    @discardableResult
    func purchaseCredit(cents: Int) async -> Bool {
        if creditProduct(cents: cents) == nil {
            await loadCreditProducts(forceReload: true)
        }
        guard let product = creditProduct(cents: cents) else {
            let error = PurchaseServiceError.productUnavailable
            captureStoreKitError(
                stage: "purchase_product_lookup",
                error: error,
                properties: ["credit_cents": .integer(cents)]
            )
            creditPurchaseState = .failed(
                message: error.localizedDescription
            )
            return false
        }

        creditPurchaseState = .purchasing(creditCents: cents)
        do {
            switch try await purchaseService.purchase(productID: product.id) {
            case .success(let transaction):
                let mutation = try deliver(transaction)
                await transaction.finish()
                switch mutation {
                case .granted, .duplicate:
                    creditPurchaseState = loadedCreditCatalogState
                    return true
                case .reversed, .ignoredRevocation:
                    creditPurchaseState = .failed(
                        message: PurchaseServiceError.failedVerification
                            .localizedDescription
                    )
                    return false
                }
            case .pending:
                creditPurchaseState = .pending
                return false
            case .userCancelled:
                creditPurchaseState = loadedCreditCatalogState
                return false
            }
        } catch {
            captureStoreKitError(
                stage: "purchase",
                error: error,
                properties: [
                    "credit_cents": .integer(cents),
                    "product_id": .string(product.id),
                ]
            )
            creditPurchaseState = .failed(message: error.localizedDescription)
            return false
        }
    }

    private var loadedCreditCatalogState: CreditPurchaseState {
        let loadedProductIDs = Set(creditProducts.map(\.id))
        if loadedProductIDs == Set(CreditProductCatalog.productIDs) {
            return .idle
        }
        return .partial(
            message: "The App Store returned only some purchase options. Try again."
        )
    }

    func handleFirstRundownRatingCTA(action: String) {
        guard shouldShowFirstRundownRatingCTA else { return }
        firstRundownRatingRequestHandled = true
        persist()
        analytics.capture(
            AnalyticsEvent(
                name: "rating request action",
                properties: ["action": .string(action)]
            )
        )
    }

    @discardableResult
    func startWindow(for app: AppRule, now: Date = .now) -> Bool {
        let rate = effectiveRate(for: app)
        let cost = Money.windowCost(rateCentsPerHour: rate, minutes: defaultWindowMinutes)
        analytics.capture(
            AnalyticsEvent(
                name: "shield action selected",
                properties: [
                    "action": .string("pay"),
                    "source": .string("app_shield_preview"),
                    "window_minutes": .integer(defaultWindowMinutes),
                    "cost_microcents": .integer(Int(cost)),
                ]
            )
        )
        guard protectionEnabled, creditMicrocents >= cost else {
            analytics.capture(
                AnalyticsEvent(
                    name: "access window blocked",
                    properties: [
                        "reason": .string(
                            protectionEnabled ? "insufficient_credit" : "protection_disabled"
                        ),
                    ]
                )
            )
            return false
        }
        creditMicrocents -= cost
        activeWindow = ActiveWindow(
            appID: app.id,
            appName: app.name,
            rateCentsPerHour: rate,
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(defaultWindowMinutes * 60)),
            reservedMicrocents: cost
        )
        persist()
        analytics.capture(
            AnalyticsEvent(
                name: "access window started",
                properties: [
                    "window_minutes": .integer(defaultWindowMinutes),
                    "rate_cents_per_hour": .integer(rate),
                    "reserved_microcents": .integer(Int(cost)),
                    "source": .string("app_shield_preview"),
                ]
            )
        )
        analytics.capture(
            AnalyticsEvent(
                name: "credit spent",
                properties: [
                    "amount_microcents": .integer(Int(cost)),
                    "source": .string("access_window"),
                    "balance_microcents": .integer(Int(creditMicrocents)),
                ]
            )
        )
        return true
    }

    func endActiveWindow(now: Date = .now) {
        if let activeWindow {
            analytics.capture(
                AnalyticsEvent(
                    name: "access window ended",
                    properties: [
                        "ended_early": .boolean(now < activeWindow.endsAt),
                        "elapsed_seconds": .integer(
                            max(0, Int(now.timeIntervalSince(activeWindow.startedAt)))
                        ),
                        "reserved_microcents": .integer(
                            Int(activeWindow.reservedMicrocents)
                        ),
                    ]
                )
            )
        }
        activeWindow = nil
        persist()
    }

    func disableProtection() {
        protectionEnabled = false
        activeWindow = nil
        persist()
        syncSharedScreenTimeSnapshot(resetAllowance: true)
        if persistenceEnabled {
            ScreenTimeMonitoringService.stopAll()
        }
        analytics.capture(
            AnalyticsEvent(
                name: "protection toggled",
                properties: ["enabled": .boolean(false)]
            )
        )
    }

    func enableProtection() {
        protectionEnabled = true
        persist()
        refreshScreenTimeMonitoring(
            using: syncSharedScreenTimeSnapshot(resetAllowance: true)
        )
        analytics.capture(
            AnalyticsEvent(
                name: "protection toggled",
                properties: ["enabled": .boolean(true)]
            )
        )
    }

    func trackScreen(_ screen: String) {
        analytics.capture(
            AnalyticsEvent(
                name: "screen viewed",
                properties: ["screen": .string(screen)]
            )
        )
    }

    func trackRefillOpened(source: String) {
        analytics.capture(
            AnalyticsEvent(
                name: "refill opened",
                properties: ["source": .string(source)]
            )
        )
    }

    func trackRefillPackSelected(cents: Int) {
        analytics.capture(
            AnalyticsEvent(
                name: "refill pack selected",
                properties: ["credit_cents": .integer(cents)]
            )
        )
    }

    func trackShieldBack(source: String) {
        analytics.capture(
            AnalyticsEvent(
                name: "shield action selected",
                properties: [
                    "action": .string("go_back"),
                    "source": .string(source),
                ]
            )
        )
    }

    func applicationBecameActive(now: Date = .now) {
        if persistenceEnabled {
            let snapshot = ScreenTimeSharedRepository.update { snapshot in
                snapshot.normalizeDay(at: now)
                return snapshot
            }
            if let sharedBalance = snapshot.creditMicrocents,
                sharedBalance != creditMicrocents {
                creditMicrocents = sharedBalance
                persist()
            }
            refreshScreenTimeMonitoring(using: snapshot, now: now)
            reportRevision += 1
        }
        analytics.flushSharedEvents()
        refreshAnalyticsMilestone(now: now)
    }

    func refreshAnalyticsMilestone(now: Date = .now) {
        guard
            persistenceEnabled,
            analytics.isAvailable,
            analytics.collectionEnabled
        else {
            analyticsMilestoneRequest = nil
            return
        }
        analytics.flushSharedEvents()
        analyticsMilestoneRequest = AnalyticsSharedRepository.prepareNextMilestone(
            now: now
        )
        reportRevision += 1
    }

    private func startPurchaseMonitoring() {
        guard purchaseUpdatesTask == nil else { return }
        let service = purchaseService
        purchaseUpdatesTask = Task { [weak self, service] in
            let unfinishedTransactions =
                await service.unfinishedTransactions()
            for transaction in unfinishedTransactions {
                guard let self else { return }
                await self.processStoreKitUpdate(transaction)
            }

            for await transaction in service.transactionUpdates() {
                guard let self else { return }
                await self.processStoreKitUpdate(transaction)
            }
        }
    }

    private func processStoreKitUpdate(
        _ transaction: VerifiedCreditTransaction
    ) async {
        do {
            _ = try deliver(transaction)
            await transaction.finish()
        } catch {
            captureStoreKitError(
                stage: "transaction_update_delivery",
                error: error,
                properties: [
                    "product_id": .string(transaction.productID),
                ]
            )
            creditPurchaseState = .failed(
                message: error.localizedDescription
            )
        }
    }

    private func captureStoreKitError(
        stage: String,
        error: Error,
        properties additionalProperties: [
            String: AnalyticsPropertyValue
        ] = [:]
    ) {
        let nsError = error as NSError
        var properties: [String: AnalyticsPropertyValue] = [
            "stage": .string(stage),
            "reason": .string(storeKitErrorReason(error)),
            "error_domain": .string(nsError.domain),
            "error_code": .integer(nsError.code),
        ]
        properties.merge(additionalProperties) { _, newValue in newValue }

        if let purchaseError = error as? PurchaseServiceError,
            case let .noValidProducts(returnedProductIDs) = purchaseError {
            properties["returned_product_count"] = .integer(
                returnedProductIDs.count
            )
            properties["returned_product_ids"] = .string(
                returnedProductIDs.sorted().joined(separator: ",")
            )
        }

        analytics.capture(
            AnalyticsEvent(
                name: "storekit error",
                properties: properties
            )
        )
    }

    private func storeKitErrorReason(_ error: Error) -> String {
        if let purchaseError = error as? PurchaseServiceError {
            switch purchaseError {
            case .productUnavailable:
                return "product_unavailable"
            case .productMetadataMismatch:
                return "product_metadata_mismatch"
            case .noValidProducts:
                return "no_valid_products"
            case .failedVerification:
                return "failed_verification"
            }
        }
        if let deliveryError = error as? CreditPurchaseDeliveryError {
            switch deliveryError {
            case .invalidTransaction:
                return "invalid_transaction"
            case .persistenceFailed:
                return "persistence_failed"
            }
        }
        return "storekit_error"
    }

    private func deliver(
        _ transaction: VerifiedCreditTransaction
    ) throws -> StoreKitCreditMutation {
        guard
            let catalogProduct = CreditProductCatalog(
                rawValue: transaction.productID
            ),
            transaction.purchasedQuantity > 0
        else {
            throw CreditPurchaseDeliveryError.invalidTransaction
        }

        let creditCentsResult = catalogProduct.creditCents
            .multipliedReportingOverflow(
                by: transaction.purchasedQuantity
            )
        guard !creditCentsResult.overflow else {
            throw CreditPurchaseDeliveryError.invalidTransaction
        }
        let amountResult = Int64(creditCentsResult.partialValue)
            .multipliedReportingOverflow(by: Money.microcentsPerCent)
        guard !amountResult.overflow else {
            throw CreditPurchaseDeliveryError.invalidTransaction
        }
        let amountMicrocents = amountResult.partialValue

        let result: (
            mutation: StoreKitCreditMutation,
            balance: Int64
        )
        if persistenceEnabled {
            do {
                result = try ScreenTimeSharedRepository.updatePersisting {
                    snapshot in
                    snapshot.creditMicrocents =
                        snapshot.creditMicrocents ?? creditMicrocents
                    let mutation = snapshot.applyStoreKitCredit(
                        transactionID: transaction.id,
                        productID: transaction.productID,
                        amountMicrocents: amountMicrocents,
                        purchaseDate: transaction.purchaseDate,
                        revocationDate: transaction.revocationDate
                    )
                    return (
                        mutation,
                        snapshot.creditMicrocents ?? creditMicrocents
                    )
                }
            } catch {
                throw CreditPurchaseDeliveryError.persistenceFailed
            }
        } else {
            var snapshot = SharedScreenTimeSnapshot(
                creditMicrocents: creditMicrocents,
                storeKitCreditLedger: fixtureStoreKitCreditLedger
            )
            let mutation = snapshot.applyStoreKitCredit(
                transactionID: transaction.id,
                productID: transaction.productID,
                amountMicrocents: amountMicrocents,
                purchaseDate: transaction.purchaseDate,
                revocationDate: transaction.revocationDate
            )
            fixtureStoreKitCreditLedger =
                snapshot.storeKitCreditLedger ?? []
            result = (mutation, snapshot.creditMicrocents ?? creditMicrocents)
        }

        creditMicrocents = result.balance
        switch result.mutation {
        case .granted:
            hasAddedPaidCredit = true
            persist()
            analytics.capture(
                AnalyticsEvent(
                    name: "payment completed",
                    properties: [
                        "credit_cents": .integer(
                            creditCentsResult.partialValue
                        ),
                        "storekit_verified": .boolean(true),
                        "payment_mode": .string("storekit"),
                    ]
                )
            )
            analytics.capture(
                creditEvent(
                    name: "credit granted",
                    cents: creditCentsResult.partialValue,
                    isFree: false,
                    source: "storekit"
                )
            )
        case .reversed:
            persist()
            analytics.capture(
                AnalyticsEvent(
                    name: "payment refunded",
                    properties: [
                        "credit_cents": .integer(
                            creditCentsResult.partialValue
                        ),
                        "storekit_verified": .boolean(true),
                    ]
                )
            )
            analytics.capture(
                creditEvent(
                    name: "credit reversed",
                    cents: creditCentsResult.partialValue,
                    isFree: false,
                    source: "storekit_refund"
                )
            )
        case .duplicate, .ignoredRevocation:
            break
        }
        return result.mutation
    }

    private func persist() {
        guard persistenceEnabled else { return }
        let state = SavedState(
            onboardingComplete: onboardingComplete,
            globalRateCents: globalRateCents,
            freeMinutesPerDay: freeMinutesPerDay,
            creditMicrocents: creditMicrocents,
            protectedApps: protectedApps,
            protectionEnabled: protectionEnabled,
            activeWindow: activeWindow,
            defaultWindowMinutes: defaultWindowMinutes,
            starterCreditCentsGranted: starterCreditCentsGranted,
            starterCreditAnalyticsRecorded: starterCreditAnalyticsRecorded,
            firstRundownRatingRequestHandled:
                firstRundownRatingRequestHandled,
            hasAddedPaidCredit: hasAddedPaidCredit
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistenceKey)
    }

    @discardableResult
    private func syncSharedScreenTimeSnapshot(
        resetAllowance: Bool = false
    ) -> SharedScreenTimeSnapshot {
        guard persistenceEnabled else { return SharedScreenTimeSnapshot() }
        return ScreenTimeSharedRepository.update { snapshot in
            let previousTokenKeys = Set(
                snapshot.selection.applicationTokens.map(
                    ScreenTimeSharedRepository.tokenKey
                )
            )
            let currentTokenKeys = Set(
                activitySelection.applicationTokens.map(
                    ScreenTimeSharedRepository.tokenKey
                )
            )
            snapshot.normalizeDay()
            if currentTokenKeys.isEmpty {
                snapshot.selectionDate = nil
                snapshot.activeAccessWindows = []
            } else if previousTokenKeys != currentTokenKeys || snapshot.selectionDate == nil {
                snapshot.selectionDate = .now
            }
            if resetAllowance || previousTokenKeys != currentTokenKeys {
                snapshot.allowanceReachedDay = nil
            }
            if previousTokenKeys != currentTokenKeys {
                snapshot.activeAccessWindows = []
            }
            snapshot.selection = activitySelection
            snapshot.globalRateCents = globalRateCents
            snapshot.rateOverrides = applicationRateOverrides
            snapshot.creditMicrocents = snapshot.creditMicrocents ?? creditMicrocents
            snapshot.freeMinutesPerDay = freeMinutesPerDay
            snapshot.defaultWindowMinutes = defaultWindowMinutes
            snapshot.protectionEnabled = protectionEnabled
            return snapshot
        }
    }

    private func refreshScreenTimeMonitoring(
        using snapshot: SharedScreenTimeSnapshot,
        now: Date = .now
    ) {
        guard
            persistenceEnabled,
            screenTimeAuthorizationStatus == .approved
        else {
            return
        }
        do {
            try ScreenTimeMonitoringService.refresh(using: snapshot, now: now)
            screenTimeErrorMessage = nil
        } catch {
            screenTimeErrorMessage = error.localizedDescription
        }
    }

    private func bootstrapSelectionAnalyticsIfNeeded() {
        guard
            analytics.isAvailable,
            analytics.collectionEnabled,
            AnalyticsSharedRepository.loadCohort() == nil,
            !activitySelection.applicationTokens.isEmpty
        else {
            return
        }
        let cohort = AnalyticsSharedRepository.beginSelectionCohort(
            tokenKeys: activitySelection.applicationTokens.map(
                ScreenTimeSharedRepository.tokenKey
            )
        )
        if let cohort {
            analytics.capture(
                AnalyticsEvent(
                    name: "app selection analytics started",
                    properties: [
                        "selection_cohort_id": .string(
                            cohort.id.uuidString.lowercased()
                        ),
                        "app_count": .integer(cohort.appCount),
                        "source": .string("existing_selection_migration"),
                    ]
                )
            )
        }
    }

    private func recordStarterCreditAnalyticsIfNeeded() {
        guard
            analytics.isAvailable,
            analytics.collectionEnabled,
            !starterCreditAnalyticsRecorded
        else {
            return
        }
        analytics.capture(
            creditEvent(
                name: "credit granted",
                cents: Self.starterCreditCents,
                isFree: true,
                source: "starter_credit"
            )
        )
        starterCreditAnalyticsRecorded = true
    }

    private func creditEvent(
        name: String,
        cents: Int,
        isFree: Bool,
        source: String
    ) -> AnalyticsEvent {
        AnalyticsEvent(
            name: name,
            properties: [
                "credit_cents": .integer(cents),
                "is_free": .boolean(isFree),
                "source": .string(source),
                "balance_microcents": .integer(Int(creditMicrocents)),
            ]
        )
    }

    private static func fixtureApps(for fixture: String?) -> [AppRule] {
        guard fixture != nil, fixture != "onboarding" else { return [] }
        return [
            AppRule(
                name: "Instagram",
                symbol: "camera.aperture",
                timeSpentTodaySeconds: 28 * 60,
                chargedTimeTodaySeconds: 18 * 60
            ),
            AppRule(
                name: "TikTok",
                symbol: "music.note",
                rateOverride: 3,
                timeSpentTodaySeconds: 64 * 60,
                chargedTimeTodaySeconds: 54 * 60
            ),
            AppRule(
                name: "Reddit",
                symbol: "bubble.left.and.bubble.right",
                timeSpentTodaySeconds: 12 * 60,
                chargedTimeTodaySeconds: 2 * 60
            ),
            AppRule(
                name: "YouTube",
                symbol: "play.rectangle",
                rateOverride: 2,
                timeSpentTodaySeconds: 46 * 60,
                chargedTimeTodaySeconds: 36 * 60
            )
        ]
    }
}
