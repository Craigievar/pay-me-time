import Foundation
import Testing
@testable import PayMeTime

@MainActor
final class RecordingAnalyticsTracker: AnalyticsTracking {
    var isAvailable = true
    var collectionEnabled = true
    private(set) var events: [AnalyticsEvent] = []

    func capture(_ event: AnalyticsEvent) {
        guard collectionEnabled else { return }
        events.append(event)
    }

    func flushSharedEvents() {}
}

@MainActor
struct AnalyticsTests {
    @Test
    func paidAccessRecordsActionSpendAndWindowEvents() {
        let tracker = RecordingAnalyticsTracker()
        let store = AppStore(
            arguments: ["PayMeTime", "--fixture=standard"],
            analytics: tracker
        )

        #expect(store.startWindow(for: store.protectedApps[0]))

        #expect(tracker.events.map(\.name) == [
            "shield action selected",
            "access window started",
            "credit spent",
        ])
        #expect(tracker.events[0].properties["action"] == .string("pay"))
        #expect(tracker.events.allSatisfy { event in
            !event.properties.keys.contains("application_token")
                && !event.properties.keys.contains("app_name")
        })
    }

    @Test
    func goingBackFromShieldRecordsTheChoice() {
        let tracker = RecordingAnalyticsTracker()
        let store = AppStore(
            arguments: ["PayMeTime", "--fixture=standard"],
            analytics: tracker
        )

        store.trackShieldBack(source: "app_shield_preview")

        #expect(tracker.events.count == 1)
        #expect(tracker.events[0].name == "shield action selected")
        #expect(tracker.events[0].properties["action"] == .string("go_back"))
    }

    @Test
    func verifiedRefillSeparatesPaymentFromPaidCredit() async {
        let tracker = RecordingAnalyticsTracker()
        let store = AppStore(
            arguments: ["PayMeTime", "--fixture=standard"],
            analytics: tracker,
            purchaseService: FixturePurchaseService()
        )

        await store.loadCreditProducts()
        let purchased = await store.purchaseCredit(cents: 100)

        #expect(purchased)
        #expect(tracker.events.map(\.name) == [
            "payment completed",
            "credit granted",
        ])
        #expect(tracker.events[0].properties["storekit_verified"] == .boolean(true))
        #expect(tracker.events[1].properties["is_free"] == .boolean(false))
        #expect(tracker.events[1].properties["credit_cents"] == .integer(100))
    }

    @Test
    func failedStoreKitCatalogLoadRecordsDiagnosticContext() async throws {
        let tracker = RecordingAnalyticsTracker()
        let store = AppStore(
            arguments: ["PayMeTime", "--fixture=standard"],
            analytics: tracker,
            purchaseService: FixturePurchaseService(
                productsError: .noValidProducts(returnedProductIDs: [])
            )
        )

        await store.loadCreditProducts(forceReload: true)

        let event = try #require(
            tracker.events.first { $0.name == "storekit error" }
        )
        #expect(event.properties["stage"] == .string("catalog_load"))
        #expect(event.properties["reason"] == .string("no_valid_products"))
        #expect(event.properties["returned_product_count"] == .integer(0))
        #expect(event.properties["force_reload"] == .boolean(true))
    }

    @Test
    func milestoneScheduleUsesBaselineThenRequestedCadence() throws {
        let selectedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let cohort = AnalyticsSelectionCohort(
            id: UUID(),
            selectedAt: selectedAt,
            tokenKeys: ["local-token-key"],
            anonymousAppIDsByTokenKey: ["local-token-key": "anonymous-app-id"],
            baselineDurationSeconds: nil,
            baselineDurationSecondsByAnonymousAppID: [:],
            completedMilestones: [],
            pendingRequest: nil
        )

        let baseline = try #require(
            AnalyticsSharedRepository.nextMilestone(
                for: cohort,
                now: selectedAt,
                calendar: calendar
            )
        )
        #expect(baseline.name == "baseline")
        #expect(baseline.sequence == 0)

        var completed = cohort
        completed.completedMilestones = ["baseline", "week_1", "week_2", "week_4"]
        let monthTwoDate = try #require(
            calendar.date(byAdding: .month, value: 2, to: selectedAt)
        )
        let monthTwo = try #require(
            AnalyticsSharedRepository.nextMilestone(
                for: completed,
                now: monthTwoDate,
                calendar: calendar
            )
        )
        #expect(monthTwo.name == "month_2")
        #expect(monthTwo.sequence == 4)
    }
}
