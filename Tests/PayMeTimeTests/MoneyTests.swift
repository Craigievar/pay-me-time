import XCTest
@testable import PayMeTime

final class MoneyTests: XCTestCase {
    @MainActor
    func testStarterCreditIsTwoDollars() {
        let store = AppStore(arguments: ["PayMeTime", "--fixture=onboarding"])

        XCTAssertEqual(
            store.creditMicrocents,
            Int64(200) * Money.microcentsPerCent
        )
    }

    func testWindowCostsUseIntegerMicrocents() {
        XCTAssertEqual(Money.windowCost(rateCentsPerHour: 1, minutes: 15), 250_000)
        XCTAssertEqual(Money.windowCost(rateCentsPerHour: 3, minutes: 15), 750_000)
        XCTAssertEqual(Money.windowCost(rateCentsPerHour: 5, minutes: 30), 2_500_000)
        XCTAssertEqual(Money.compactCost(33_333), "<0.1¢")
    }

    @MainActor
    func testRatingCTAStartsAtHalfOfOriginalStarterCredit() {
        let oneCent = Money.microcentsPerCent

        XCTAssertFalse(
            AppStore.isFirstRundownRatingEligible(
                balanceMicrocents: 101 * oneCent,
                hasAddedPaidCredit: false,
                requestHandled: false
            )
        )
        XCTAssertTrue(
            AppStore.isFirstRundownRatingEligible(
                balanceMicrocents: 100 * oneCent,
                hasAddedPaidCredit: false,
                requestHandled: false
            )
        )
        XCTAssertFalse(
            AppStore.isFirstRundownRatingEligible(
                balanceMicrocents: 0,
                hasAddedPaidCredit: false,
                requestHandled: false
            )
        )
    }

    @MainActor
    func testRatingCTAOnlyAppearsDuringFirstCreditRundown() {
        let threshold = Int64(AppStore.firstRundownRatingThresholdCents)
            * Money.microcentsPerCent

        XCTAssertFalse(
            AppStore.isFirstRundownRatingEligible(
                balanceMicrocents: threshold,
                hasAddedPaidCredit: true,
                requestHandled: false
            )
        )
        XCTAssertFalse(
            AppStore.isFirstRundownRatingEligible(
                balanceMicrocents: threshold,
                hasAddedPaidCredit: false,
                requestHandled: true
            )
        )
    }

    @MainActor
    func testRatingCTAIsOneTime() {
        let store = AppStore(arguments: ["PayMeTime", "--fixture=rating"])

        XCTAssertTrue(store.shouldShowFirstRundownRatingCTA)
        store.handleFirstRundownRatingCTA(action: "dismiss")
        XCTAssertFalse(store.shouldShowFirstRundownRatingCTA)
    }

    @MainActor
    func testPerAppRateInheritsGlobalDefault() {
        let store = AppStore(arguments: ["PayMeTime", "--fixture=home"])
        let inherited = store.protectedApps.first(where: { $0.rateOverride == nil })!
        XCTAssertEqual(store.effectiveRate(for: inherited), 1)

        store.updateGlobalRate(4)
        XCTAssertEqual(store.effectiveRate(for: inherited), 4)

        store.setRateOverride(appID: inherited.id, value: 2)
        let updated = store.protectedApps.first(where: { $0.id == inherited.id })!
        XCTAssertEqual(store.effectiveRate(for: updated), 2)
    }

    @MainActor
    func testRateIsAlwaysCappedAtFiveCents() {
        let store = AppStore(arguments: ["PayMeTime", "--fixture=home"])
        store.updateGlobalRate(99)
        XCTAssertEqual(store.globalRateCents, 5)
    }

    @MainActor
    func testEmptyCreditCannotStartWindow() {
        let store = AppStore(arguments: ["PayMeTime", "--fixture=empty"])
        XCTAssertFalse(store.startWindow(for: store.protectedApps[0]))
        XCTAssertNil(store.activeWindow)
    }

    func testPerAppTodayCostUsesChargedTimeAndRate() {
        let app = AppRule(
            name: "Example",
            symbol: "app",
            rateOverride: 3,
            timeSpentTodaySeconds: 3_600,
            chargedTimeTodaySeconds: 1_800
        )

        XCTAssertEqual(app.timeSpentTodayLabel, "1h 0m")
        XCTAssertEqual(app.costTodayMicrocents(rateCentsPerHour: 3), 1_500_000)
    }

    func testSharedLedgerReservesExactWindowCostAndUpdatesDailyTotal() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = SharedScreenTimeSnapshot(
            creditMicrocents: 200 * Money.microcentsPerCent,
            protectionEnabled: true,
            costDay: calendar.startOfDay(for: now)
        )
        let cost = Money.windowCost(rateCentsPerHour: 1, minutes: 15)

        XCTAssertTrue(
            snapshot.reserve(
                costMicrocents: cost,
                forTokenKey: "space-game",
                at: now,
                calendar: calendar
            )
        )
        XCTAssertEqual(
            snapshot.creditMicrocents,
            200 * Money.microcentsPerCent - 250_000
        )
        XCTAssertEqual(
            snapshot.costMicrocentsByApplication["space-game"],
            250_000
        )
    }

    func testSharedLedgerRejectsReservationWithoutCredit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = SharedScreenTimeSnapshot(
            creditMicrocents: 100_000,
            protectionEnabled: true,
            costDay: now
        )

        XCTAssertFalse(
            snapshot.reserve(
                costMicrocents: 250_000,
                forTokenKey: "space-game",
                at: now
            )
        )
        XCTAssertEqual(snapshot.creditMicrocents, 100_000)
        XCTAssertTrue(snapshot.costMicrocentsByApplication.isEmpty)
    }

    @MainActor
    func testProtectedAppsAreSortedByTimeSpentDescending() {
        let store = AppStore(arguments: ["PayMeTime", "--fixture=home"])

        XCTAssertEqual(
            store.protectedAppsByTimeSpent.map(\.name),
            ["TikTok", "YouTube", "Instagram", "Reddit"]
        )
    }

    func testProgressComparesLastSevenDaysWithBaseline() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = (0..<7).map { index in
            ProgressDailyUsage(
                day: calendar.date(
                    byAdding: .day,
                    value: index - 6,
                    to: now
                )!,
                seconds: 60 * 60
            )
        }
        let summary = ProgressSummary(
            dailyUsage: usage,
            baselineSeconds: 10 * 60 * 60,
            selectionDate: calendar.date(
                byAdding: .day,
                value: -14,
                to: now
            )!,
            generatedAt: now
        )

        XCTAssertEqual(summary.lastSevenDaysSeconds, 7 * 60 * 60)
        XCTAssertEqual(summary.changeSeconds, -3 * 60 * 60)
        XCTAssertEqual(summary.percentChange!, -30, accuracy: 0.001)
        XCTAssertTrue(summary.comparisonIsReady(calendar: calendar))
    }

    func testProgressWaitsForACompletePostSelectionWeek() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = ProgressSummary(
            dailyUsage: [],
            baselineSeconds: 60 * 60,
            selectionDate: calendar.date(
                byAdding: .day,
                value: -3,
                to: now
            )!,
            generatedAt: now
        )

        XCTAssertFalse(summary.comparisonIsReady(calendar: calendar))
        XCTAssertEqual(summary.daysUntilComparison(calendar: calendar), 4)
    }
}
