import Foundation

struct AppRule: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var symbol: String
    var rateOverride: Int?
    var timeSpentTodaySeconds: Int
    var chargedTimeTodaySeconds: Int

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        rateOverride: Int? = nil,
        timeSpentTodaySeconds: Int = 0,
        chargedTimeTodaySeconds: Int = 0
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.rateOverride = rateOverride
        self.timeSpentTodaySeconds = timeSpentTodaySeconds
        self.chargedTimeTodaySeconds = chargedTimeTodaySeconds
    }

    func costTodayMicrocents(rateCentsPerHour: Int) -> Int64 {
        Int64(rateCentsPerHour)
            * Int64(chargedTimeTodaySeconds)
            * Money.microcentsPerCent
            / 3_600
    }

    var timeSpentTodayLabel: String {
        let minutes = timeSpentTodaySeconds / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes)m"
    }
}

struct ActiveWindow: Codable, Equatable {
    let appID: UUID
    let appName: String
    let rateCentsPerHour: Int
    let startedAt: Date
    let endsAt: Date
    let reservedMicrocents: Int64
}

enum ShieldMode: String, CaseIterable, Identifiable {
    case freeTime
    case credit
    case empty

    var id: String { rawValue }
}
