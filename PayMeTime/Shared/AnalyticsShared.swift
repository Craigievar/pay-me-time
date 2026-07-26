import Foundation

enum AnalyticsPropertyValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)

    private enum CodingKeys: String, CodingKey {
        case type
        case string
        case integer
        case double
        case boolean
    }

    private enum ValueType: String, Codable {
        case string
        case integer
        case double
        case boolean
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ValueType.self, forKey: .type) {
        case .string:
            self = .string(try container.decode(String.self, forKey: .string))
        case .integer:
            self = .integer(try container.decode(Int.self, forKey: .integer))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .double))
        case .boolean:
            self = .boolean(try container.decode(Bool.self, forKey: .boolean))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .string)
        case let .integer(value):
            try container.encode(ValueType.integer, forKey: .type)
            try container.encode(value, forKey: .integer)
        case let .double(value):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(value, forKey: .double)
        case let .boolean(value):
            try container.encode(ValueType.boolean, forKey: .type)
            try container.encode(value, forKey: .boolean)
        }
    }

    var foundationValue: Any {
        switch self {
        case let .string(value): value
        case let .integer(value): value
        case let .double(value): value
        case let .boolean(value): value
        }
    }
}

struct AnalyticsEvent: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let properties: [String: AnalyticsPropertyValue]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        properties: [String: AnalyticsPropertyValue] = [:],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.properties = properties
        self.createdAt = createdAt
    }
}

struct AnalyticsMilestoneRequest: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let sequence: Int
    let periodStart: Date
    let periodEnd: Date
}

struct AnalyticsSelectionCohort: Codable, Equatable, Sendable {
    let id: UUID
    let selectedAt: Date
    let tokenKeys: [String]
    let anonymousAppIDsByTokenKey: [String: String]
    var baselineDurationSeconds: Int?
    var baselineDurationSecondsByAnonymousAppID: [String: Int]
    var completedMilestones: [String]
    var pendingRequest: AnalyticsMilestoneRequest?

    var appCount: Int {
        anonymousAppIDsByTokenKey.count
    }
}

enum AnalyticsSharedRepository {
    static let appGroupID = "group.com.craig.paymetime"
    private static let cohortKey = "analytics-selection-cohort-v1"
    private static let eventQueueKey = "analytics-extension-events-v1"
    private static let collectionEnabledKey = "analytics-collection-enabled-v1"
    private static let maximumQueuedEvents = 200

    static var isCollectionEnabled: Bool {
        defaults?.bool(forKey: collectionEnabledKey) ?? false
    }

    static func setCollectionEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: collectionEnabledKey)
        if !enabled {
            defaults?.removeObject(forKey: eventQueueKey)
            defaults?.removeObject(forKey: cohortKey)
        }
    }

    @discardableResult
    static func beginSelectionCohort(
        tokenKeys: [String],
        selectedAt: Date = .now
    ) -> AnalyticsSelectionCohort? {
        let normalizedKeys = Array(Set(tokenKeys)).sorted()
        guard !normalizedKeys.isEmpty else {
            defaults?.removeObject(forKey: cohortKey)
            return nil
        }

        if let existing = loadCohort(), existing.tokenKeys == normalizedKeys {
            return existing
        }

        let anonymousIDs = Dictionary(
            uniqueKeysWithValues: normalizedKeys.map { ($0, UUID().uuidString.lowercased()) }
        )
        let cohort = AnalyticsSelectionCohort(
            id: UUID(),
            selectedAt: selectedAt,
            tokenKeys: normalizedKeys,
            anonymousAppIDsByTokenKey: anonymousIDs,
            baselineDurationSeconds: nil,
            baselineDurationSecondsByAnonymousAppID: [:],
            completedMilestones: [],
            pendingRequest: nil
        )
        saveCohort(cohort)
        return cohort
    }

    static func loadCohort() -> AnalyticsSelectionCohort? {
        guard
            let data = defaults?.data(forKey: cohortKey),
            let cohort = try? JSONDecoder().decode(AnalyticsSelectionCohort.self, from: data)
        else {
            return nil
        }
        return cohort
    }

    @discardableResult
    static func prepareNextMilestone(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AnalyticsMilestoneRequest? {
        guard isCollectionEnabled else { return nil }
        guard var cohort = loadCohort() else { return nil }
        if let pendingRequest = cohort.pendingRequest {
            return pendingRequest
        }

        guard let milestone = nextMilestone(for: cohort, now: now, calendar: calendar) else {
            return nil
        }

        let periodStart = calendar.date(
            byAdding: .day,
            value: -7,
            to: milestone.date
        ) ?? milestone.date.addingTimeInterval(-7 * 24 * 60 * 60)
        let request = AnalyticsMilestoneRequest(
            id: UUID(),
            name: milestone.name,
            sequence: milestone.sequence,
            periodStart: periodStart,
            periodEnd: milestone.date
        )
        cohort.pendingRequest = request
        saveCohort(cohort)
        return request
    }

    static func completeMilestone(
        requestID: UUID,
        durationSecondsByTokenKey: [String: Int]
    ) {
        guard
            isCollectionEnabled,
            var cohort = loadCohort(),
            let request = cohort.pendingRequest,
            request.id == requestID
        else {
            return
        }

        var durationByAnonymousAppID: [String: Int] = [:]
        for tokenKey in cohort.tokenKeys {
            guard let anonymousID = cohort.anonymousAppIDsByTokenKey[tokenKey] else { continue }
            durationByAnonymousAppID[anonymousID] = max(0, durationSecondsByTokenKey[tokenKey] ?? 0)
        }

        let totalDuration = durationByAnonymousAppID.values.reduce(0, +)
        if request.name == "baseline" {
            cohort.baselineDurationSeconds = totalDuration
            cohort.baselineDurationSecondsByAnonymousAppID = durationByAnonymousAppID
        }

        let daysSinceSelection = max(
            0,
            Calendar.current.dateComponents(
                [.day],
                from: cohort.selectedAt,
                to: request.periodEnd
            ).day ?? 0
        )
        var overallProperties = milestoneProperties(
            cohort: cohort,
            request: request,
            durationSeconds: totalDuration,
            baselineDurationSeconds: cohort.baselineDurationSeconds,
            daysSinceSelection: daysSinceSelection,
            scope: "overall"
        )
        overallProperties["app_count"] = .integer(cohort.appCount)
        enqueue(
            AnalyticsEvent(
                name: "screen time milestone reached",
                properties: overallProperties
            )
        )

        for anonymousID in cohort.anonymousAppIDsByTokenKey.values.sorted() {
            var properties = milestoneProperties(
                cohort: cohort,
                request: request,
                durationSeconds: durationByAnonymousAppID[anonymousID] ?? 0,
                baselineDurationSeconds:
                    cohort.baselineDurationSecondsByAnonymousAppID[anonymousID],
                daysSinceSelection: daysSinceSelection,
                scope: "anonymized_app"
            )
            properties["anonymous_app_id"] = .string(anonymousID)
            enqueue(
                AnalyticsEvent(
                    name: "screen time milestone reached",
                    properties: properties
                )
            )
        }

        cohort.completedMilestones.append(request.name)
        cohort.pendingRequest = nil
        saveCohort(cohort)
    }

    static func anonymousAppID(forTokenKey tokenKey: String) -> String? {
        loadCohort()?.anonymousAppIDsByTokenKey[tokenKey]
    }

    static func enqueue(_ event: AnalyticsEvent) {
        guard isCollectionEnabled else { return }
        var events = loadQueuedEvents()
        events.append(event)
        if events.count > maximumQueuedEvents {
            events.removeFirst(events.count - maximumQueuedEvents)
        }
        saveQueuedEvents(events)
    }

    static func drainQueuedEvents() -> [AnalyticsEvent] {
        guard isCollectionEnabled else { return [] }
        let events = loadQueuedEvents()
        guard !events.isEmpty else { return [] }
        defaults?.removeObject(forKey: eventQueueKey)
        return events
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static func saveCohort(_ cohort: AnalyticsSelectionCohort) {
        guard isCollectionEnabled else { return }
        guard let data = try? JSONEncoder().encode(cohort) else { return }
        defaults?.set(data, forKey: cohortKey)
    }

    private static func loadQueuedEvents() -> [AnalyticsEvent] {
        guard
            let data = defaults?.data(forKey: eventQueueKey),
            let events = try? JSONDecoder().decode([AnalyticsEvent].self, from: data)
        else {
            return []
        }
        return events
    }

    private static func saveQueuedEvents(_ events: [AnalyticsEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults?.set(data, forKey: eventQueueKey)
    }

    private static func milestoneProperties(
        cohort: AnalyticsSelectionCohort,
        request: AnalyticsMilestoneRequest,
        durationSeconds: Int,
        baselineDurationSeconds: Int?,
        daysSinceSelection: Int,
        scope: String
    ) -> [String: AnalyticsPropertyValue] {
        var properties: [String: AnalyticsPropertyValue] = [
            "selection_cohort_id": .string(cohort.id.uuidString.lowercased()),
            "milestone": .string(request.name),
            "milestone_sequence": .integer(request.sequence),
            "measurement_window_days": .integer(7),
            "days_since_selection": .integer(daysSinceSelection),
            "duration_seconds": .integer(durationSeconds),
            "scope": .string(scope),
        ]
        if let baselineDurationSeconds {
            properties["baseline_duration_seconds"] = .integer(baselineDurationSeconds)
            if baselineDurationSeconds > 0 {
                properties["percent_of_baseline"] = .double(
                    Double(durationSeconds) / Double(baselineDurationSeconds) * 100
                )
            }
        }
        return properties
    }

    static func nextMilestone(
        for cohort: AnalyticsSelectionCohort,
        now: Date,
        calendar: Calendar
    ) -> (name: String, sequence: Int, date: Date)? {
        let completed = Set(cohort.completedMilestones)
        if !completed.contains("baseline") {
            return ("baseline", 0, min(cohort.selectedAt, now))
        }

        let weeklyMilestones = [
            ("week_1", 1, 7),
            ("week_2", 2, 14),
            ("week_4", 3, 28),
        ]
        for (name, sequence, days) in weeklyMilestones where !completed.contains(name) {
            guard let date = calendar.date(byAdding: .day, value: days, to: cohort.selectedAt) else {
                continue
            }
            return date <= now ? (name, sequence, date) : nil
        }

        for month in 2...120 {
            let name = "month_\(month)"
            if completed.contains(name) {
                continue
            }
            guard let date = calendar.date(byAdding: .month, value: month, to: cohort.selectedAt) else {
                continue
            }
            return date <= now ? (name, month + 2, date) : nil
        }
        return nil
    }
}
