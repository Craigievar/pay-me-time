import Darwin
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

enum HourlyRatePolicy {
    static let minimumCentsPerHour = 1
    static let maximumCentsPerHour = 10
    static let defaultCentsPerHour = 5

    static var allowedRange: ClosedRange<Int> {
        minimumCentsPerHour...maximumCentsPerHour
    }

    static func clamped(_ value: Int) -> Int {
        min(max(value, minimumCentsPerHour), maximumCentsPerHour)
    }
}

struct SharedAccessWindow: Codable, Equatable, Identifiable {
    let id: UUID
    let token: ApplicationToken
    let startedAt: Date
    let endsAt: Date
    let reservedMicrocents: Int64
    let rateCentsPerHour: Int
}

enum StoreKitCreditLedgerKind: String, Codable, Equatable {
    case grant
    case refundReversal
}

struct StoreKitCreditLedgerEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: StoreKitCreditLedgerKind
    let amountMicrocents: Int64
    let transactionID: UInt64
    let productID: String
    let purchaseDate: Date
    let effectiveAt: Date
    let createdAt: Date
}

enum StoreKitCreditMutation: Equatable {
    case granted(amountMicrocents: Int64)
    case reversed(amountMicrocents: Int64)
    case duplicate
    case ignoredRevocation
}

struct SharedScreenTimeSnapshot: Codable {
    var selection: FamilyActivitySelection
    var selectionDate: Date?
    var globalRateCents: Int
    var rateOverrides: [String: Int]
    var costMicrocentsByApplication: [String: Int64]
    var creditMicrocents: Int64?
    var freeMinutesPerDay: Int?
    var defaultWindowMinutes: Int?
    var protectionEnabled: Bool?
    var costDay: Date?
    var allowanceReachedDay: Date?
    var activeAccessWindows: [SharedAccessWindow]?
    var storeKitCreditLedger: [StoreKitCreditLedgerEntry]?

    init(
        selection: FamilyActivitySelection = .init(),
        selectionDate: Date? = nil,
        globalRateCents: Int = HourlyRatePolicy.defaultCentsPerHour,
        rateOverrides: [String: Int] = [:],
        costMicrocentsByApplication: [String: Int64] = [:],
        creditMicrocents: Int64? = nil,
        freeMinutesPerDay: Int? = nil,
        defaultWindowMinutes: Int? = nil,
        protectionEnabled: Bool? = nil,
        costDay: Date? = nil,
        allowanceReachedDay: Date? = nil,
        activeAccessWindows: [SharedAccessWindow]? = nil,
        storeKitCreditLedger: [StoreKitCreditLedgerEntry]? = nil
    ) {
        self.selection = selection
        self.selectionDate = selectionDate
        self.globalRateCents = HourlyRatePolicy.clamped(globalRateCents)
        self.rateOverrides = rateOverrides.mapValues(HourlyRatePolicy.clamped)
        self.costMicrocentsByApplication = costMicrocentsByApplication
        self.creditMicrocents = creditMicrocents
        self.freeMinutesPerDay = freeMinutesPerDay
        self.defaultWindowMinutes = defaultWindowMinutes
        self.protectionEnabled = protectionEnabled
        self.costDay = costDay
        self.allowanceReachedDay = allowanceReachedDay
        self.activeAccessWindows = activeAccessWindows
        self.storeKitCreditLedger = storeKitCreditLedger
    }

    func rate(for token: ApplicationToken) -> Int {
        HourlyRatePolicy.clamped(
            rateOverrides[ScreenTimeSharedRepository.tokenKey(token)]
                ?? globalRateCents
        )
    }

    mutating func normalizeRates() {
        globalRateCents = HourlyRatePolicy.clamped(globalRateCents)
        rateOverrides = rateOverrides.mapValues(HourlyRatePolicy.clamped)
    }

    func costMicrocents(
        for token: ApplicationToken,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int64 {
        guard costDay.map({ calendar.isDate($0, inSameDayAs: now) }) == true else {
            return 0
        }
        return costMicrocentsByApplication[
            ScreenTimeSharedRepository.tokenKey(token)
        ] ?? 0
    }

    func allowanceReached(
        at now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        allowanceReachedDay.map { calendar.isDate($0, inSameDayAs: now) } == true
    }

    mutating func normalizeDay(
        at now: Date = .now,
        calendar: Calendar = .current
    ) {
        if costDay.map({ calendar.isDate($0, inSameDayAs: now) }) != true {
            costDay = calendar.startOfDay(for: now)
            costMicrocentsByApplication = [:]
            allowanceReachedDay = nil
            activeAccessWindows = []
        } else {
            activeAccessWindows = (activeAccessWindows ?? []).filter {
                $0.endsAt > now
            }
        }
    }

    mutating func reserve(
        costMicrocents: Int64,
        forTokenKey tokenKey: String,
        at now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        normalizeDay(at: now, calendar: calendar)
        guard
            protectionEnabled ?? true,
            costMicrocents > 0,
            (creditMicrocents ?? 0) >= costMicrocents
        else {
            return false
        }
        creditMicrocents = (creditMicrocents ?? 0) - costMicrocents
        costMicrocentsByApplication[tokenKey, default: 0] += costMicrocents
        return true
    }

    mutating func applyStoreKitCredit(
        transactionID: UInt64,
        productID: String,
        amountMicrocents: Int64,
        purchaseDate: Date,
        revocationDate: Date?,
        now: Date = .now
    ) -> StoreKitCreditMutation {
        guard amountMicrocents > 0 else { return .duplicate }

        let entries = storeKitCreditLedger ?? []
        let hasGrant = entries.contains {
            $0.transactionID == transactionID && $0.kind == .grant
        }
        let hasReversal = entries.contains {
            $0.transactionID == transactionID
                && $0.kind == .refundReversal
        }

        if let revocationDate {
            guard hasGrant else { return .ignoredRevocation }
            guard !hasReversal else { return .duplicate }

            let priorBalance = max(0, creditMicrocents ?? 0)
            let updatedBalance = max(0, priorBalance - amountMicrocents)
            creditMicrocents = updatedBalance
            storeKitCreditLedger = entries + [
                StoreKitCreditLedgerEntry(
                    id: UUID(),
                    kind: .refundReversal,
                    amountMicrocents: -amountMicrocents,
                    transactionID: transactionID,
                    productID: productID,
                    purchaseDate: purchaseDate,
                    effectiveAt: revocationDate,
                    createdAt: now
                )
            ]
            return .reversed(
                amountMicrocents: priorBalance - updatedBalance
            )
        }

        guard !hasGrant else { return .duplicate }
        creditMicrocents = max(0, creditMicrocents ?? 0) + amountMicrocents
        storeKitCreditLedger = entries + [
            StoreKitCreditLedgerEntry(
                id: UUID(),
                kind: .grant,
                amountMicrocents: amountMicrocents,
                transactionID: transactionID,
                productID: productID,
                purchaseDate: purchaseDate,
                effectiveAt: purchaseDate,
                createdAt: now
            )
        ]
        return .granted(amountMicrocents: amountMicrocents)
    }
}

enum ScreenTimeSharedRepository {
    enum PersistenceError: Error {
        case appGroupWriteFailed
    }

    static let appGroupID = "group.com.nonagon.Screenbump"
    private static let snapshotKey = "screen-time-snapshot-v1"
    private static let snapshotFilename = "screen-time-snapshot-v2.json"
    private static let lockFilename = "screen-time-snapshot-v2.lock"

    static func load() -> SharedScreenTimeSnapshot {
        withLock {
            loadUnlocked()
        }
    }

    static func save(_ snapshot: SharedScreenTimeSnapshot) {
        withLock {
            _ = saveUnlocked(snapshot)
        }
    }

    @discardableResult
    static func update<Result>(
        _ mutation: (inout SharedScreenTimeSnapshot) -> Result
    ) -> Result {
        withLock {
            var snapshot = loadUnlocked()
            let result = mutation(&snapshot)
            _ = saveUnlocked(snapshot)
            return result
        }
    }

    static func updatePersisting<Result>(
        _ mutation: (inout SharedScreenTimeSnapshot) -> Result
    ) throws -> Result {
        var didPersist = false
        let result = withLock {
            var snapshot = loadUnlocked()
            let result = mutation(&snapshot)
            didPersist = saveUnlocked(snapshot)
            return result
        }
        guard didPersist else {
            throw PersistenceError.appGroupWriteFailed
        }
        return result
    }

    static func tokenKey(_ token: ApplicationToken) -> String {
        guard let data = try? JSONEncoder().encode(token) else {
            return String(token.hashValue)
        }
        return data.base64EncodedString()
    }

    private static func loadUnlocked() -> SharedScreenTimeSnapshot {
        if
            let url = snapshotURL,
            let data = try? Data(contentsOf: url),
            var snapshot = try? JSONDecoder().decode(
                SharedScreenTimeSnapshot.self,
                from: data
            )
        {
            snapshot.normalizeRates()
            return snapshot
        }

        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: snapshotKey),
            var snapshot = try? JSONDecoder().decode(
                SharedScreenTimeSnapshot.self,
                from: data
            )
        else {
            return SharedScreenTimeSnapshot()
        }
        snapshot.normalizeRates()
        return snapshot
    }

    private static func saveUnlocked(_ snapshot: SharedScreenTimeSnapshot) -> Bool {
        var snapshot = snapshot
        snapshot.normalizeRates()
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return false
        }
        var savedToFile = false
        if let url = snapshotURL {
            do {
                try data.write(to: url, options: .atomic)
                savedToFile = true
            } catch {
                savedToFile = false
            }
        }
        UserDefaults(suiteName: appGroupID)?.set(data, forKey: snapshotKey)
        return savedToFile
    }

    private static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFilename)
    }

    private static func withLock<Result>(_ operation: () -> Result) -> Result {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID
            )
        else {
            return operation()
        }

        let lockURL = containerURL.appendingPathComponent(lockFilename)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            return operation()
        }
        flock(descriptor, LOCK_EX)
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        return operation()
    }
}

enum ScreenTimePolicy {
    static var dailyActivity: DeviceActivityName {
        DeviceActivityName("pay-me-time.daily")
    }

    static var allowanceEvent: DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("pay-me-time.allowance")
    }

    static let accessActivityPrefix = "pay-me-time.access."

    static var storeName: ManagedSettingsStore.Name {
        ManagedSettingsStore.Name("pay-me-time")
    }

    static func accessActivityName(for id: UUID) -> DeviceActivityName {
        DeviceActivityName(accessActivityPrefix + id.uuidString.lowercased())
    }

    static func accessWindowID(from activity: DeviceActivityName) -> UUID? {
        guard activity.rawValue.hasPrefix(accessActivityPrefix) else { return nil }
        return UUID(
            uuidString: String(activity.rawValue.dropFirst(accessActivityPrefix.count))
        )
    }

    static func shieldedApplications(
        in snapshot: SharedScreenTimeSnapshot,
        now: Date = .now
    ) -> Set<ApplicationToken> {
        let activeTokens = Set(
            (snapshot.activeAccessWindows ?? [])
                .filter { $0.endsAt > now }
                .map(\.token)
        )
        return snapshot.selection.applicationTokens.subtracting(activeTokens)
    }
}

struct SelectedApplication: Identifiable, Hashable {
    let token: ApplicationToken

    var id: String {
        ScreenTimeSharedRepository.tokenKey(token)
    }
}
