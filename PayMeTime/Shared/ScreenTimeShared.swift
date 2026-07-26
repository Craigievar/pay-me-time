import FamilyControls
import Foundation
import ManagedSettings

struct SharedScreenTimeSnapshot: Codable {
    var selection: FamilyActivitySelection
    var selectionDate: Date?
    var globalRateCents: Int
    var rateOverrides: [String: Int]
    var costMicrocentsByApplication: [String: Int64]

    init(
        selection: FamilyActivitySelection = .init(),
        selectionDate: Date? = nil,
        globalRateCents: Int = 1,
        rateOverrides: [String: Int] = [:],
        costMicrocentsByApplication: [String: Int64] = [:]
    ) {
        self.selection = selection
        self.selectionDate = selectionDate
        self.globalRateCents = globalRateCents
        self.rateOverrides = rateOverrides
        self.costMicrocentsByApplication = costMicrocentsByApplication
    }

    func rate(for token: ApplicationToken) -> Int {
        rateOverrides[ScreenTimeSharedRepository.tokenKey(token)] ?? globalRateCents
    }

    func costMicrocents(for token: ApplicationToken) -> Int64 {
        costMicrocentsByApplication[ScreenTimeSharedRepository.tokenKey(token)] ?? 0
    }
}

enum ScreenTimeSharedRepository {
    static let appGroupID = "group.com.craig.paymetime"
    private static let snapshotKey = "screen-time-snapshot-v1"

    static func load() -> SharedScreenTimeSnapshot {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(SharedScreenTimeSnapshot.self, from: data)
        else {
            return SharedScreenTimeSnapshot()
        }
        return snapshot
    }

    static func save(_ snapshot: SharedScreenTimeSnapshot) {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = try? JSONEncoder().encode(snapshot)
        else {
            return
        }
        defaults.set(data, forKey: snapshotKey)
    }

    static func tokenKey(_ token: ApplicationToken) -> String {
        guard let data = try? JSONEncoder().encode(token) else {
            return String(token.hashValue)
        }
        return data.base64EncodedString()
    }
}

struct SelectedApplication: Identifiable, Hashable {
    let token: ApplicationToken

    var id: String {
        ScreenTimeSharedRepository.tokenKey(token)
    }
}
