import DeviceActivity
import FamilyControls
import SwiftUI

struct ProtectionView: View {
    let store: AppStore
    @State private var selectedRule: AppRule?
    @State private var selectedApplication: SelectedApplication?
    @State private var isPickerPresented = false
    @State private var authorizationError: String?

    var body: some View {
        List {
            Section {
                RateStepper(
                    title: "Global default",
                    value: store.globalRateCents,
                    onChange: { store.updateGlobalRate($0) }
                )
                .accessibilityIdentifier("protection.globalRate")
                Stepper(value: Binding(
                    get: { store.freeMinutesPerDay },
                    set: { store.updateFreeMinutes($0) }
                ), in: 0...240, step: 5) {
                    LabeledContent("Free time each day", value: "\(store.freeMinutesPerDay) min")
                }
            } header: {
                Text("Defaults")
            }

            if store.fixtureName == nil {
                Section {
                    if store.selectedApplications.isEmpty {
                        ContentUnavailableView {
                            Label("No apps selected", systemImage: "apps.iphone")
                        } description: {
                            Text("Choose apps privately with Apple’s Screen Time picker.")
                        } actions: {
                            Button("Add apps") {
                                requestAuthorizationAndOpenPicker()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(store.selectedApplications) { application in
                            Button {
                                selectedApplication = application
                            } label: {
                                HStack(spacing: 12) {
                                    Label(application.token)
                                        .labelStyle(.titleAndIcon)
                                        .foregroundStyle(.primary)
                                        .accessibilityIdentifier("ph-no-capture")
                                    Spacer()
                                    Text("\(store.effectiveRate(for: application.token))¢ / hr")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(PMTTheme.amber)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            // The button contains Apple's private app label. Mark the
                            // whole subtree so autocapture cannot observe its token-backed
                            // identifier or rendered name.
                            .accessibilityIdentifier("ph-no-capture")
                        }

                        addAppsButton
                    }
                } header: {
                    Text("Protected apps")
                }

                if !store.selectedApplications.isEmpty {
                    Section {
                        DeviceActivityReport(.payMeTimeApplications, filter: reportFilter)
                            .accessibilityIdentifier("ph-no-capture")
                            .id(store.reportRevision)
                            .frame(
                                minHeight: CGFloat(
                                    store.selectedApplications.count * 52
                                )
                            )
                            .listRowInsets(
                                EdgeInsets(
                                    top: 0,
                                    leading: 16,
                                    bottom: 0,
                                    trailing: 16
                                )
                            )
                    } header: {
                        Text("Today")
                    }
                }
            } else {
                Section {
                    ForEach(store.protectedAppsByTimeSpent) { app in
                        Button {
                            selectedRule = app
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 14) {
                                    AppArtwork(app: app)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.name)
                                            .foregroundStyle(.primary)
                                        Text(app.rateOverride == nil ? "Uses global default" : "Custom rate")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(store.effectiveRate(for: app))¢ / hr")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(PMTTheme.amber)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }

                                HStack(spacing: 20) {
                                    TodayMetric(
                                        title: "Time spent",
                                        value: app.timeSpentTodayLabel,
                                        systemImage: "clock"
                                    )
                                    TodayMetric(
                                        title: "Cost",
                                        value: Money.compactCost(store.costToday(for: app)),
                                        systemImage: "creditcard"
                                    )
                                }
                                .padding(.leading, 42)
                            }
                        }
                        .accessibilityIdentifier("protection.app.\(app.name)")
                    }

                    addAppsButton
                } header: {
                    Text("Protected apps · demo data")
                } footer: {
                    Text("App names and today’s activity are deterministic preview data, not activity read from this device.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PMTTheme.canvas)
        .navigationTitle("Protection")
        .sheet(item: $selectedRule) { app in
            AppRateEditor(store: store, app: app)
        }
        .sheet(item: $selectedApplication) { application in
            ApplicationRateEditor(store: store, application: application)
        }
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
            store.trackScreen("protection")
            store.refreshScreenTimeAuthorizationStatus()
        }
        .onChange(of: isPickerPresented) { wasPresented, isPresented in
            if wasPresented, !isPresented {
                store.finalizeActivitySelection()
            }
        }
    }

    private var addAppsButton: some View {
        Button("Add apps", systemImage: "plus") {
            requestAuthorizationAndOpenPicker()
        }
        .fontWeight(.semibold)
        .accessibilityIdentifier("protection.addApps")
    }

    private var reportFilter: DeviceActivityFilter {
        let interval = DateInterval(
            start: Calendar.current.startOfDay(for: .now),
            end: .now
        )
        return DeviceActivityFilter(
            segment: .hourly(during: interval),
            devices: .all,
            applications: store.activitySelection.applicationTokens
        )
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

private struct AppArtwork: View {
    let app: AppRule

    var body: some View {
        Image(app.name)
            .resizable()
            .scaledToFill()
        .frame(width: 38, height: 38)
        .background(PMTTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct TodayMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ApplicationRateEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: AppStore
    let application: SelectedApplication
    @State private var usesDefault: Bool
    @State private var rate: Int

    init(store: AppStore, application: SelectedApplication) {
        self.store = store
        self.application = application
        let key = ScreenTimeSharedRepository.tokenKey(application.token)
        let override = store.applicationRateOverrides[key]
        _usesDefault = State(initialValue: override == nil)
        _rate = State(initialValue: override ?? store.globalRateCents)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(application.token)
                        .labelStyle(.titleAndIcon)
                        .accessibilityIdentifier("ph-no-capture")
                    Toggle("Use global default", isOn: $usesDefault)
                    if usesDefault {
                        LabeledContent("Effective rate", value: "\(store.globalRateCents)¢ / hour")
                    } else {
                        Stepper(
                            "\(rate)¢ / hour",
                            value: $rate,
                            in: HourlyRatePolicy.allowedRange
                        )
                    }
                } footer: {
                    Text("This app can never charge more than \(HourlyRatePolicy.maximumCentsPerHour)¢ per hour.")
                }
            }
            .navigationTitle("App rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setRateOverride(
                            for: application.token,
                            value: usesDefault ? nil : rate
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AppRateEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: AppStore
    let app: AppRule
    @State private var usesDefault: Bool
    @State private var rate: Int

    init(store: AppStore, app: AppRule) {
        self.store = store
        self.app = app
        _usesDefault = State(initialValue: app.rateOverride == nil)
        _rate = State(initialValue: app.rateOverride ?? store.globalRateCents)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use global default", isOn: $usesDefault)
                    if usesDefault {
                        LabeledContent("Effective rate", value: "\(store.globalRateCents)¢ / hour")
                    } else {
                        Stepper(
                            "\(rate)¢ / hour",
                            value: $rate,
                            in: HourlyRatePolicy.allowedRange
                        )
                    }
                } footer: {
                    Text("This app can never charge more than \(HourlyRatePolicy.maximumCentsPerHour)¢ per hour.")
                }

                Section("What the shield will say") {
                    Text("You decided to charge yourself \(usesDefault ? store.globalRateCents : rate)¢ per hour to use this app.")
                    Text("Your time is worth way more than those pennies.")
                        .italic()
                }
            }
            .navigationTitle(app.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setRateOverride(appID: app.id, value: usesDefault ? nil : rate)
                        dismiss()
                    }
                    .accessibilityIdentifier("rate.save")
                }
            }
        }
    }
}
