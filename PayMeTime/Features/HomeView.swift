import SwiftUI

private enum HomeSheet: Identifiable {
    case refill

    var id: String { "refill" }
}

struct HomeView: View {
    let store: AppStore
    @State private var sheet: HomeSheet?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                BalanceHero(store: store)

                if let activeWindow = store.activeWindow {
                    ActiveWindowCard(window: activeWindow) {
                        store.endActiveWindow()
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("Today", systemImage: "sun.max")
                        .font(.headline)
                    LabeledContent("Free time", value: "\(store.freeMinutesPerDay) min")
                    LabeledContent("Protected apps", value: "\(store.protectedAppCount)")
                }
                .pmtCard()
            }
            .padding(20)
        }
        .background(PMTTheme.canvas)
        .navigationTitle("Pay Me Time")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refill", systemImage: "plus.circle") {
                    sheet = .refill
                }
                .accessibilityIdentifier("home.refill")
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .refill:
                RefillView(store: store, source: "home")
            }
        }
        .task {
            store.trackScreen("home")
        }
    }
}

private struct BalanceHero: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 12) {
            Text(Money.balance(store.creditMicrocents))
                .font(.system(size: 66, weight: .medium, design: .serif))
                .foregroundStyle(PMTTheme.sage)
                .contentTransition(.numericText())
                .accessibilityIdentifier("home.balance")
            Text("attention credit remaining")
                .foregroundStyle(.secondary)
            ProgressView(
                value: min(
                    Double(store.creditMicrocents)
                        / Double(Int64(AppStore.starterCreditCents) * Money.microcentsPerCent),
                    1
                )
            )
                .tint(PMTTheme.sage)
            let hours = Money.hoursRemaining(
                balanceMicrocents: store.creditMicrocents,
                rateCentsPerHour: store.globalRateCents
            )
            Text("About \(hours.formatted(.number.precision(.fractionLength(0)))) hours at your default rate")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .pmtCard()
    }
}

private struct ActiveWindowCard: View {
    let window: ActiveWindow
    let end: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(window.endsAt.timeIntervalSince(context.date)))
            VStack(alignment: .leading, spacing: 12) {
                Label("\(window.appName) is open", systemImage: "timer")
                    .font(.headline)
                Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(.largeTitle, design: .monospaced, weight: .medium))
                Text("\(window.rateCentsPerHour)¢ per hour · \(Money.compactCost(window.reservedMicrocents)) reserved")
                    .foregroundStyle(.secondary)
                Button("End access window", action: end)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .pmtCard()
            .accessibilityIdentifier("ph-no-capture")
        }
    }
}
