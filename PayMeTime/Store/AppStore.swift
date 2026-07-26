import FamilyControls
import Foundation
import ManagedSettings
import Observation

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
    }

    private static let persistenceKey = "pay-me-time-state-v2"
    static let starterCreditCents = 200
    private let persistenceEnabled: Bool
    private let analytics: any AnalyticsTracking
    private var starterCreditCentsGranted: Int
    private var starterCreditAnalyticsRecorded: Bool
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
    private(set) var anonymousAnalyticsEnabled: Bool
    let analyticsAvailable: Bool

    let availableWindowMinutes = [5, 15, 30]
    private(set) var defaultWindowMinutes: Int

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        analytics: any AnalyticsTracking = NoopAnalyticsTracker()
    ) {
        self.analytics = analytics
        let fixture = arguments.first(where: { $0.hasPrefix("--fixture=") })?
            .replacingOccurrences(of: "--fixture=", with: "")
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
        onboardingComplete = fixture == "onboarding"
            ? false
            : savedState?.onboardingComplete ?? (fixture != nil)
        globalRateCents = savedState?.globalRateCents ?? 1
        freeMinutesPerDay = savedState?.freeMinutesPerDay ?? 60
        let existingCreditMicrocents = savedState?.creditMicrocents
            ?? ((fixture == "empty" || fixture == "empty-shield")
                ? 0
                : Int64(Self.starterCreditCents) * Money.microcentsPerCent)
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
        protectedApps = savedState?.protectedApps ?? Self.fixtureApps(for: fixture)
        activeWindow = savedState?.activeWindow
        defaultWindowMinutes = savedState?.defaultWindowMinutes ?? 15
        activitySelection = fixture == nil ? sharedSnapshot.selection : FamilyActivitySelection()
        applicationRateOverrides = fixture == nil ? sharedSnapshot.rateOverrides : [:]
        screenTimeAuthorizationStatus = fixture == nil
            ? ScreenTimeAuthorizationService.status
            : .approved
        screenTimeErrorMessage = nil
        analyticsAvailable = analytics.isAvailable
        anonymousAnalyticsEnabled = analytics.collectionEnabled
        analyticsMilestoneRequest = nil

        if fixture == nil {
            let snapshot = syncSharedScreenTimeSnapshot()
            refreshScreenTimeMonitoring(using: snapshot)
            bootstrapSelectionAnalyticsIfNeeded()
            refreshAnalyticsMilestone()
            recordStarterCreditAnalyticsIfNeeded()
            if starterCreditUpgrade > 0 || starterCreditAnalyticsRecorded {
                persist()
            }
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
        globalRateCents = min(max(value, 1), 5)
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
        app.rateOverride ?? globalRateCents
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
        protectedApps[index].rateOverride = value.map { min(max($0, 1), 5) }
        persist()
        analytics.capture(
            AnalyticsEvent(
                name: "protection rate changed",
                properties: [
                    "scope": .string("fixture_app"),
                    "uses_global_default": .boolean(value == nil),
                    "cents_per_hour": .integer(value ?? globalRateCents),
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

    func effectiveRate(for token: ApplicationToken) -> Int {
        applicationRateOverrides[ScreenTimeSharedRepository.tokenKey(token)] ?? globalRateCents
    }

    func setRateOverride(for token: ApplicationToken, value: Int?) {
        let key = ScreenTimeSharedRepository.tokenKey(token)
        applicationRateOverrides[key] = value.map { min(max($0, 1), 5) }
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
                    "uses_global_default": .boolean(value == nil),
                    "cents_per_hour": .integer(value ?? globalRateCents),
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

    func addCredit(cents: Int) {
        let amount = Int64(cents) * Money.microcentsPerCent
        if persistenceEnabled {
            creditMicrocents = ScreenTimeSharedRepository.update { snapshot in
                let updatedBalance = (snapshot.creditMicrocents ?? creditMicrocents) + amount
                snapshot.creditMicrocents = updatedBalance
                return updatedBalance
            }
        } else {
            creditMicrocents += amount
        }
        persist()
        analytics.capture(
            AnalyticsEvent(
                name: "payment completed",
                properties: [
                    "credit_cents": .integer(cents),
                    "storekit_verified": .boolean(false),
                    "payment_mode": .string("prototype_refill"),
                ]
            )
        )
        analytics.capture(
            creditEvent(
                name: "credit granted",
                cents: cents,
                isFree: false,
                source: "prototype_refill"
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

    func setAnonymousAnalyticsEnabled(_ enabled: Bool) {
        guard analytics.isAvailable else { return }
        if enabled {
            analytics.setCollectionEnabled(true)
            anonymousAnalyticsEnabled = true
            analytics.capture(
                AnalyticsEvent(
                    name: "analytics preference changed",
                    properties: ["enabled": .boolean(true)]
                )
            )
            bootstrapSelectionAnalyticsIfNeeded()
            refreshAnalyticsMilestone()
        } else {
            analytics.capture(
                AnalyticsEvent(
                    name: "analytics preference changed",
                    properties: ["enabled": .boolean(false)]
                )
            )
            analytics.setCollectionEnabled(false)
            anonymousAnalyticsEnabled = false
            analyticsMilestoneRequest = nil
        }
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
            starterCreditAnalyticsRecorded: starterCreditAnalyticsRecorded
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
