import FamilyControls
import SwiftUI

struct OnboardingView: View {
    let store: AppStore
    @State private var isPickerPresented = false
    @State private var authorizationError: String?
    @State private var revealStage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Your time is valuable.")
                        .font(.system(.largeTitle, design: .serif, weight: .semibold))

                    if revealStage >= 1 {
                        OnboardingInsightCard(
                            systemImage: "lightbulb.fill",
                            tint: PMTTheme.sage,
                            text: "Research shows that even small explicit costs cause our brains to think instead of running on autopilot."
                        )
                        .transition(revealTransition)
                    }

                    if revealStage >= 2 {
                        OnboardingInsightCard(
                            systemImage: "dollarsign.circle.fill",
                            tint: PMTTheme.amber,
                            text: "After your daily open time, protection begins. If you choose to continue, you can use credits to start a short access window."
                        )
                        .transition(revealTransition)
                    }

                    if revealStage >= 3 {
                        OnboardingInsightCard(
                            systemImage: "checkmark.seal.fill",
                            tint: PMTTheme.sage,
                            text: "We'll give you some credits to start with"
                        )
                        .transition(revealTransition)
                    }

                    if revealStage >= 4 {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 18) {
                                Button {
                                    requestAuthorizationAndOpenPicker()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "square.grid.2x2")
                                            .foregroundStyle(PMTTheme.amber)
                                        Text(
                                            store.protectedAppCount == 0
                                                ? "Choose apps to protect your time from"
                                                : "Change apps"
                                        )
                                        .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("onboarding.chooseApps")

                                Divider()

                                VStack(alignment: .leading, spacing: 6) {
                                    Stepper(value: Binding(
                                        get: { store.freeMinutesPerDay },
                                        set: { store.updateFreeMinutes($0) }
                                    ), in: 0...240, step: 5) {
                                        LabeledContent("Free time each day", value: "\(store.freeMinutesPerDay) min")
                                    }
                                    Text("Global grace period before protection starts")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .pmtCard()

                            Button("Turn on protection") {
                                store.completeOnboarding()
                            }
                            .pmtPrimaryButton()
                            .accessibilityIdentifier("onboarding.continue")

                            Text("You can pause or turn off protection at any time")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                        .transition(revealTransition)
                    }
                }
                .padding(20)
            }
            .background(PMTTheme.canvas)
            .familyActivityPicker(
                headerText: "Choose apps you want Screenbump to protect.",
                footerText: "Your choices stay private and are represented by opaque Apple tokens.",
                isPresented: $isPickerPresented,
                selection: Binding(
                    get: { store.activitySelection },
                    set: { store.updateActivitySelection($0) }
                )
            )
            .alert(
                "Screen Time permission needed",
                isPresented: Binding(
                    get: { authorizationError != nil },
                    set: { if !$0 { authorizationError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(authorizationError ?? "Please try again.")
            }
            .task {
                store.trackScreen("onboarding")
                await revealContent()
            }
            .onChange(of: isPickerPresented) { wasPresented, isPresented in
                if wasPresented, !isPresented {
                    store.finalizeActivitySelection()
                }
            }
        }
    }

    private var revealTransition: AnyTransition {
        .opacity.combined(with: .move(edge: .bottom))
    }

    private func revealContent() async {
        if reduceMotion || ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            revealStage = 4
            return
        }

        for stage in 1...4 {
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1)) {
                revealStage = stage
            }
            if stage < 4 {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func requestAuthorizationAndOpenPicker() {
        Task {
            let authorized: Bool
            if store.screenTimeAuthorizationStatus == .approved {
                authorized = true
            } else {
                authorized = await store.requestScreenTimeAuthorization()
            }

            if authorized {
                isPickerPresented = true
            } else {
                authorizationError = store.screenTimeErrorMessage
                    ?? "Allow Screen Time access to choose protected apps."
            }
        }
    }
}

private struct OnboardingInsightCard: View {
    let systemImage: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(text)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pmtCard()
    }
}

@MainActor
struct RateStepper: View {
    let title: String
    let value: Int
    let onChange: @MainActor @Sendable (Int) -> Void

    var body: some View {
        Stepper(
            value: Binding(get: { value }, set: { onChange($0) }),
            in: HourlyRatePolicy.allowedRange
        ) {
            LabeledContent(title, value: "\(value)¢ / hour")
        }
    }
}
