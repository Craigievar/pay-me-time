import Foundation

enum Money {
    static let microcentsPerCent: Int64 = 1_000_000

    static func windowCost(rateCentsPerHour: Int, minutes: Int) -> Int64 {
        Int64(rateCentsPerHour * minutes) * microcentsPerCent / 60
    }

    static func balance(_ microcents: Int64) -> String {
        let cents = Double(microcents) / Double(microcentsPerCent)
        if cents >= 100 {
            return String(format: "$%.2f", cents / 100)
        }
        return String(format: "%.1f¢", cents)
    }

    static func compactCost(_ microcents: Int64) -> String {
        let cents = Double(microcents) / Double(microcentsPerCent)
        let rounded = (cents * 10).rounded() / 10
        if microcents > 0, rounded == 0 {
            return "<0.1¢"
        }
        return String(format: rounded == rounded.rounded() ? "%.0f¢" : "%.1f¢", rounded)
    }

    static func hoursRemaining(balanceMicrocents: Int64, rateCentsPerHour: Int) -> Double {
        guard rateCentsPerHour > 0 else { return 0 }
        return Double(balanceMicrocents) / Double(microcentsPerCent) / Double(rateCentsPerHour)
    }
}
