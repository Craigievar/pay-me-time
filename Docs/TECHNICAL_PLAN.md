# Pay Me Time technical plan

**Status:** implementation in progress
**Date:** July 26, 2026
**Target:** iPhone, iOS 18+, Swift 6, SwiftUI

## 1. Product contract

### Thesis

Pay Me Time turns the moment after a user's chosen free daily allowance into a small, explicit financial decision. The point is not meaningful financial pain; it is a visible mental speed bump.

### MVP rules

- The app is free to download.
- Every user starts with 200¢ of non-cash, non-transferable attention credit.
- The user selects apps privately with `FamilyActivityPicker`.
- The user chooses a whole-number global default rate from 1¢ through 5¢ per hour and may override it per selected app. There is no higher option or hidden override.
- The user chooses 0–240 free minutes per day; default to 60 minutes and support 5-minute increments.
- Selected-app activity consumes free time first.
- During setup, the user chooses a default 5-, 15-, or 30-minute access window.
- After the free allowance, a shield requires an explicit start of that configured access window.
- Starting a window reserves its exact cost from the balance. It never silently extends.
- The app and optional Live Activity show the access window and projected balance ticking down.
- At window end, selected apps are shielded again.
- At zero credit, protected apps remain shielded until the user refills, pauses protection, or revokes authorization.
- Refill denominations are 100¢, 500¢, 1,000¢, and 2,500¢. Credit never expires.
- A pause and complete deletion path stay visible. Individual Screen Time authorization is voluntary and bypassable.

### Honest charging language

The implementation must call the paid period an **access window**, not measured foreground use. Screen Time APIs do not provide a reliable second-by-second foreground session owned by the containing app. The user buys a short interval in which selected apps are unshielded, and the balance decreases for that interval whether or not every second is used.

This contract is measurable:

```text
window cost = rate in cents/hour × window seconds ÷ 3,600
```

Keep the ledger in integer microcents, where 1 cent is 1,000,000 microcents. Do not use `Double` for money.

| Rate | 5 minutes | 15 minutes | 30 minutes | $1 lasts |
| ---: | ---: | ---: | ---: | ---: |
| 1¢/hour | 0.083¢ | 0.25¢ | 0.5¢ | 100 hours |
| 3¢/hour | 0.25¢ | 0.75¢ | 1.5¢ | 33h 20m |
| 5¢/hour | 0.417¢ | 1.25¢ | 2.5¢ | 20 hours |

The UI should show fractional cents for a window and a changing time-to-zero. Showing only a two-decimal dollar balance would barely move and would not create the intended meter effect.

### Explicit non-goals

- No postpaid usage invoice, Stripe billing meter, subscription, or open-ended charge.
- No background claim that the app knows exact foreground seconds.
- No categories or websites in the first validation build.
- No social feed, accountability partner, charity transfer, cash redemption, AI coach, or cross-platform account.
- No promise of tamper resistance.
- No app-owned operational backend in the MVP unless durable reinstall or
  multi-device credit restoration requires one. PostHog event analytics is the
  bounded exception described in `Docs/ANALYTICS.md`.

## 2. Monetization and App Review positioning

Proceed with a free-to-download MVP and optional StoreKit credit refills.

Apple's current [App Review Guideline 4.10](https://developer.apple.com/app-store/review/guidelines/) says apps may not monetize built-in capabilities or Apple technologies, explicitly including Screen Time APIs. Read literally, that creates review risk for a monetized Screen Time product even when the download and core experience are free.

Observed App Store practice is more permissive than that broad reading:

| App | Current App Store evidence |
| --- | --- |
| [Opal](https://apps.apple.com/us/app/opal-screen-time-control/id1497465230) | Explicitly says it uses Apple's Screen Time API to monitor and block apps; offers In-App Purchases and has an Apple Editors' Choice designation. |
| [Jomo](https://apps.apple.com/us/app/jomo-screen-time-blocker/id1609960918) | Explicitly says it uses Apple's Screen Time API for blocking; sells monthly, annual, family, and lifetime products. |
| [Roots](https://apps.apple.com/us/app/roots-screen-time-control/id6446800962) | Explicitly says it uses Apple's Screen Time API; sells subscriptions and premium passes around limits and blocking. |
| [one sec](https://apps.apple.com/us/app/one-sec-screen-time-focus/id1532875441) | Adjacent evidence: one selected app is free and additional intentional-use interventions require Pro. Its listing describes Shortcuts automation, so it is not exact Screen Time API precedent. |

This does not guarantee approval of a new or materially different business model. It does show that 4.10 should be treated as a positioning and review-consistency risk, not an automatic prohibition on charging for a Screen Time-powered app.

Pay Me Time should describe what the customer buys as the complete app-owned commitment system:

- configurable free daily allowance;
- deliberate access-window workflow;
- prepaid commitment-credit ledger;
- exact rate and cap controls;
- history, receipts, pause, and recovery;
- privacy-preserving orchestration around Apple's public frameworks.

Do not market refills as “paying to access Apple's Screen Time API.” Do not hide the relationship between credit and shielding either. The distinctive value is the app's dollar-denominated commitment mechanic, not the underlying operating-system capability.

Guideline 3.1.1 says digital features and credits sold in an app must use In-App Purchase and purchased credits may not expire. StoreKit is therefore the appropriate refill mechanism.

Review strategy:

1. Build the deterministic app UI and no-network physical-device flow.
2. Request Family Controls distribution capability for the app and every Screen Time extension early.
3. Keep a dated competitor-parity record with current App Store links and screenshots.
4. Use StoreKit, plain purchase language, non-expiring credit, and visible pause/refund support.
5. Prepare candid App Review notes explaining the whole product and why the purchase is not access to an Apple API.
6. Submit an early complete MVP and respond to the actual review result rather than presuming rejection.

## 3. Platform truth versus mock behavior

### Supported direction

- `FamilyControls` authorizes an individual user and provides privacy-preserving app tokens.
- `DeviceActivity` can monitor a daily schedule, notify an extension when a usage threshold is reached, and render privacy-preserving usage through a Device Activity Report extension.
- `ManagedSettings` can apply or remove shields for selected tokens.
- `ManagedSettingsUI` can configure a shield's icon, title, subtitle, primary button, and optional secondary button.
- StoreKit 2 can sell consumable refill products and provide verified transactions.
- An App Group can share policy, ledger snapshots, and extension commands among targets.

### Implemented as of July 26, 2026

- The containing app requests individual Family Controls authorization and presents the real `FamilyActivityPicker`.
- Production installs start with an empty selection; category and web-domain tokens are discarded for the app-only MVP.
- Opaque application tokens, the global default, and per-app rate overrides persist in `group.com.craig.paymetime`.
- Real selected-app labels and icons are rendered by Apple's token-based `Label` initializers.
- The Protection screen supports a 1–5¢ global default and 1–5¢ per-app overrides.
- A Device Activity Report extension aggregates today's real duration by selected app and sorts descending by time spent.
- The same report extension provides a private on-device Progress view with a
  daily seven-day time series and a like-for-like comparison against the seven
  days before the current protected-app selection.
- Reported cost comes only from the shared access-window ledger snapshot. It is not inferred from foreground activity.
- PostHog event analytics, lifecycle/screen/interaction autocapture, an in-app
  opt-out, and aggregate Screen Time milestones are implemented. Session replay
  is disabled, and app identities/tokens are never transmitted.
- The app plus Device Activity Monitor, Shield Configuration, Shield Action, and Device Activity Report targets compile and sign with explicit development profiles containing Family Controls and the App Group.
- Simulator build/install succeeds and the automated suite passes.

Still to implement and prove:

- daily monitoring registration and threshold updates when free time or selection changes;
- production shield configuration from the shared per-app policy rather than placeholder copy data;
- atomic access-window reservation, unshielding, expiry scheduling, and re-shielding;
- writing actual per-app access-window costs into the shared report snapshot;
- StoreKit products and verified, idempotent credit delivery;
- the full physical-device matrix below.

### Must be proven on a physical iPhone

- Free-use threshold fires consistently across midnight, reboot, clock changes, and selection edits.
- A shield action can safely reserve credit, unshield the chosen selection, and arm re-shielding.
- Re-shielding happens within an acceptable tolerance when an access window expires while the containing app is suspended.
- A shield refreshes its balance snapshot after an App Group state change.
- Extension writes are atomic and remain readable under device-lock data protection.
- Authorization revocation, app deletion, and failure to schedule monitoring never create a debit.

### Not supported as drawn

- A system shield is not a custom SwiftUI view and cannot host a second-by-second ticking meter.
- The shield action extension should not be assumed to open the containing app or present StoreKit.
- The containing app cannot overlay a balance on top of another app.
- Simulator mocks do not validate Screen Time, StoreKit Sandbox, App Attest, or the distribution entitlement.

The production shield should show a snapshot and an exact action:

```text
Free time is finished
Continuing uses your credit at 3¢ per hour.
$1.00 available

[ Start 15 min · 0.8¢ ]
[ Not now ]
```

The live tick belongs in the Pay Me Time app and, only after the core works, an optional Live Activity.

## 4. Screen lifecycle

### First launch

1. Promise: “Choose free time. Make the next minute a decision.”
2. Explain in a dedicated card that the user starts with $2.00 in credits.
3. Reveal the research, explicit-cost, and included-credit cards with
   one-second transitions, then reveal the interactive setup controls.
4. Use one app-selection row: “Choose apps that you'll pay for,” changing to
   “Change apps” after selection.
5. Request individual authorization and select apps with `FamilyActivityPicker`.
6. Set the daily free allowance and explain it as the global grace period before payments begin.
7. Keep the initial global rate at 1¢/hour; let the user change global and per-app rates later on Protection.
8. Choose a default access window.
9. Show the exact 5-, 15-, and 30-minute costs and approximate hours in $2.
10. Confirm that payments can be turned off at any time.
11. Activate daily monitoring.

The user may inspect the configuration before granting Screen Time permission. If authorization is denied, show the value and a retry path without trapping the user.

### Repeated daily loop

1. Selected apps open normally while today's free allowance remains.
2. At the usage threshold, `DeviceActivityMonitor` applies shields.
3. The shield shows the latest balance snapshot and rate.
4. “Not now” closes the attempted app.
5. Starting an access window atomically reserves credit before removing shields.
6. The extension records the window, arms expiry, and then unshields.
7. Expiry re-applies shields and closes the ledger reservation as consumed.
8. The containing app reconciles extension records on next launch.

### Empty credit

- The shield says “Credit is empty.”
- “Not now” closes the attempted app.
- Refill instructions tell the user to open Pay Me Time; purchase occurs only in the app. Do not assume the shield extension can deep-link to its containing app.
- “Pause protection” remains available in the app and must be deliberate but not hidden.
- No debit occurs if a refill is pending, canceled, unverified, duplicated, or interrupted.

### Recovery states

- **Permission denied/revoked:** stop monitoring, remove app-owned shields, preserve ledger, explain how to re-enable.
- **Schedule failure:** fail open and show “Protection needs attention”; never debit.
- **App Group corruption:** retain the last verified immutable ledger and fail closed only if the user previously selected that behavior; default to fail open for MVP.
- **Purchase pending:** do not grant credit until StoreKit verification succeeds.
- **Duplicate transaction:** product delivery is idempotent by StoreKit transaction ID.
- **Refund:** append a reversal. Never mutate or delete the original grant.
- **Offline:** existing local credit and windows work; refill waits for StoreKit.
- **Midnight:** reset only free daily activity. Never reset or expire purchased credit.

## 5. Project shape

Use XcodeGen with `project.yml` as the membership source of truth.

```text
PayMeTime/
  App/
  Design/
  Features/
  Models/
  Store/
  Services/
  Shared/
    ScreenTimeShared.swift
    DeviceActivityReportContext.swift
Extensions/
  DeviceActivityMonitor/
  DeviceActivityReport/
  ShieldConfiguration/
  ShieldAction/
Tests/
  PayMeTimeTests/
  PayMeTimeUITests/
Config/
project.yml
```

### Targets

1. `PayMeTime` containing app.
2. `PayMeTimeDeviceActivityMonitor`.
3. `PayMeTimeShieldConfiguration`.
4. `PayMeTimeShieldAction`.
5. `PayMeTimeDeviceActivityReport`.
6. Unit and UI test targets.
7. Add a Live Activity/widget extension only after the device flow passes.

Each shipping target needs the correct App Group and Family Controls entitlements. Distribution entitlement requests are required for the app and each relevant extension.

The five explicit shipping IDs are:

- `com.craig.PayMeTime`
- `com.craig.PayMeTime.DeviceActivityMonitor`
- `com.craig.PayMeTime.DeviceActivityReport`
- `com.craig.PayMeTime.ShieldAction`
- `com.craig.PayMeTime.ShieldConfiguration`

## 6. State and service boundaries

Use one `@MainActor @Observable AppStore` for user-facing state and mutations. Extensions do not instantiate the app store; they communicate through versioned App Group records.

Protocols:

```swift
protocol ScreenTimeControlling {
    func requestAuthorization() async throws
    func saveSelection(_ selection: FamilyActivitySelection) throws
    func startDailyAllowance(_ policy: ProtectionPolicy) throws
    func applyShields() throws
    func removeShields(until: Date) throws
}

protocol PurchaseServicing {
    func products() async throws -> [CreditProduct]
    func purchase(_ product: CreditProduct) async throws -> VerifiedCreditGrant
    func transactionUpdates() -> AsyncStream<VerifiedCreditGrant>
}

protocol LedgerPersisting {
    func snapshot() throws -> CreditLedgerSnapshot
    func append(_ entry: CreditLedgerEntry) throws
}

protocol Clock {
    var now: Date { get }
}
```

Mocks must cover:

- authorized, denied, and revoked Screen Time states;
- free time remaining and threshold reached;
- active 5-, 15-, and 30-minute windows;
- balance at 200¢, fractional-cent display, and zero;
- StoreKit success, pending, cancellation, unverified result, duplicate delivery, and refund;
- scheduling failure, midnight rollover, device restart, and stale App Group snapshot.

All fixtures use real views and store paths. Activate them only with a Debug/UI-test launch argument and make the seam unavailable in Release.

## 7. Data model and ledger

### Protection policy

```text
id
schemaVersion
opaque app tokens
rateCentsPerHour: UInt8 (validated 1...5)
freeMinutesPerDay: UInt16
defaultWindowMinutes: 5 | 15 | 30
protectionEnabled
updatedAt
```

Keep opaque app tokens on-device in the App Group. Do not log or upload app identities.
Analytics may use a random per-selection app identifier to compare the same
selected token over time, but that mapping remains local and cannot identify the
application in PostHog.

### Append-only credit ledger

```text
CreditLedgerEntry
  id: UUID
  kind: initialGrant | storeKitGrant | windowReservation |
        windowRelease | refundReversal | supportAdjustment
  amountMicrocents: Int64
  effectiveAt
  createdAt
  sourceID
  schemaVersion
```

- Grants are positive; reservations and reversals are negative.
- `sourceID` is unique for each StoreKit transaction and each access-window reservation.
- Current balance is a reduction over immutable entries.
- An access window is written before unshielding.
- If unshielding or expiry scheduling fails, append a compensating `windowRelease`.
- Persist via atomic replace, file coordination, and a serial cross-process mutation strategy.
- Use data protection compatible with extensions after first device unlock.

### Money formatting

- Never call the balance cash, a wallet, or stored value.
- State “Commitment credit has no cash value and cannot be transferred or redeemed.”
- Show the balance to a tenth of a cent when useful, but retain full integer precision internally.
- StoreKit product price is localized and fetched from `Product.displayPrice`; never hard-code a checkout price.
- Keep the first release US-only if commitment credit remains USD-denominated.

## 8. StoreKit plan

Use four consumable products:

```text
com.paymetime.credit.100
com.paymetime.credit.500
com.paymetime.credit.1000
com.paymetime.credit.2500
```

For US positioning, configure price points near $0.99, $4.99, $9.99, and $24.99 while clearly stating the amount of in-app commitment credit granted. The App Store price and the displayed credit balance are related product values, not a redeemable dollar deposit.

Delivery:

1. Fetch products from StoreKit.
2. Present localized prices.
3. Purchase in the containing app.
4. Require a verified StoreKit 2 transaction.
5. Append the grant once using `transaction.id` as the idempotency source.
6. Persist successfully.
7. Finish the transaction only after durable delivery.
8. Listen to `Transaction.updates` from app launch.

The initial 200¢ grant is free and separate from StoreKit refill products. Deliver it
once according to a documented per-user policy. The local prototype persists a grant
version and applies the second starter dollar once when migrating old $1.00 state. A
release-quality build still needs a durable reinstall and multi-device policy before
launch because a local preference alone cannot enforce a one-time lifetime grant.

Do not build Stripe for this model. These credits unlock behavior inside the iOS app, and the App Review rules point to In-App Purchase.

## 9. Implementation slices

### Slice 0 — product positioning and entitlements

- Finalize the honest business description.
- Register stable bundle IDs.
- Request Family Controls distribution for all five shipping bundle IDs.
- Create the App Store Connect record, competitor-parity record, and review strategy.

**Current evidence:** all five IDs have working development provisioning with Family Controls and `group.com.craig.paymetime`. Distribution requests must still be submitted and approved for release.

**Exit:** entitlement requests submitted and monetization positioning documented.

### Slice 1 — deterministic SwiftUI prototype

- Scaffold XcodeGen project.
- Implement design tokens and the real onboarding, home, shield-preview, credit-store, and settings views.
- Implement in-memory `MockScreenTimeController`, `MockPurchaseService`, `MockLedgerStore`, and `TestClock`.
- Add launch personas for first run, free time, active window, empty credit, denied permission, purchase pending, and failure.
- Capture light, dark, and accessibility screenshots.

**Current evidence:** complete. The app builds, installs, and runs on Simulator;
18 unit/UI tests pass.

**Exit:** full mocked journey passes in Simulator with no production capabilities.

### Slice 2 — physical Screen Time spike

- Add App Group and development Family Controls entitlements.
- Save a privacy-preserving selection.
- Show a real per-app Device Activity report sorted by time spent.
- Monitor a daily free allowance.
- Apply a custom shield at threshold.
- Start one fixed access window from a shield action.
- Re-shield on expiry.
- Record an atomic local reservation/release ledger.

**Current evidence:** authorization, picker, persistence, per-app configuration, and reporting code are implemented and development-signed. Installation and end-to-end on-phone evidence are still required.

**Exit:** on a physical iPhone, one selected app reports real activity, shields, unshields for exactly one chosen window, and re-shields without a duplicate debit.

### Slice 3 — StoreKit test flow

- Add StoreKit configuration and consumable products.
- Implement verified, idempotent delivery.
- Test purchase, pending Ask to Buy, cancellation, duplicate updates, refund/revocation, interruption, and relaunch.
- Confirm the initial grant behavior separately from refill products.

**Exit:** each verified transaction creates exactly one durable grant and unverified transactions create none.

### Slice 4 — App Store candidate

- Sign every target with approved distribution entitlements.
- Add privacy/support URLs, review notes, and a deterministic review account/state if needed.
- Submit a complete but deliberately narrow TestFlight/App Review candidate.

**Exit:** the candidate is approved or produces specific, actionable review feedback.

### Slice 5 — production hardening

- Decide reinstall and multi-device ledger durability.
- Add private CloudKit or a minimal authenticated ledger service only if required.
- Add Live Activity, notifications, purchase history, and refund support.
- Validate the implemented PostHog dashboards, retention behavior, privacy
  disclosures, and production ingestion before release.
- Run full device, StoreKit Sandbox, TestFlight, accessibility, and release matrices.

## 10. Verification matrix

### Unit

- Money math at 1¢, 3¢, and 5¢ rates for all window lengths.
- No floating-point paths.
- Rate cannot exceed 5¢ or fall below 1¢.
- Balance cannot go negative.
- Duplicate ledger source IDs are rejected.
- Midnight resets free time but not credit.
- Refund and compensating entries preserve history.

### Store

- Each onboarding and authorization transition.
- Empty credit never unshields.
- Reservation failure never unshields.
- Scheduling/unshield failure returns the reserved credit.
- Pause removes app-owned shields without deleting money history.

### UI

- First-run setup.
- Free time to shield.
- Start an access window.
- Active countdown.
- Empty credit and refill.
- Purchase pending/canceled/failed.
- Permission denied/revoked.
- Dynamic Type, VoiceOver, Reduce Motion, light, and dark mode.

### Physical iPhone

- Family Controls authorization and revocation.
- Token selection persistence.
- Threshold delivery.
- Shield copy and actions.
- Re-shield timing under foreground, background, device lock, reboot, and Low Power Mode.
- Extension App Group consistency.
- StoreKit Sandbox purchase and refund.
- Voluntary bypass behavior is accurately described.

Compilation or Simulator UI does not count as proof of Screen Time behavior.

## 11. Product and economic validation

The low cap is intentional, but it changes the business:

- At the maximum 5¢/hour, the starting $2 lasts 40 paid hours and $25 lasts 500 paid hours.
- At 3¢/hour, $25 lasts more than 833 paid hours.
- A daily free allowance may mean many users rarely spend credit at all.
- The initial included $2 may last months.

Validate whether seeing “0.8¢” creates enough friction before assuming refills will be meaningful revenue. The success metric for the prototype is behavior change, not refill conversion:

- shield abandon rate;
- number of deliberately started windows;
- windows ended early;
- paid-window minutes per active day;
- user-reported usefulness after one week.

Keep analytics aggregate and privacy-safe; never transmit selected app identity.
The implemented milestone series captures the preceding seven-day baseline when
selection is completed, then matching seven-day windows at weeks 1, 2, and 4,
followed by monthly checkpoints. Events include duration and percent of baseline
for the aggregate selection and random per-selection app IDs.

## 12. Launch blockers

- Clear App Review notes and a dated competitor-parity record for Guideline 4.10.
- Family Controls distribution entitlements for every relevant target.
- Physical-device proof of shield/window/re-shield behavior.
- A precise decision for unused-window charging and early ending.
- Durable policy for reinstall, device replacement, Family Sharing, and consumable balance.
- Terms describing non-cash commitment credit, refunds, and deletion.
- StoreKit Sandbox and TestFlight evidence.
- App Store privacy-label answers and the public privacy policy must match
  `PrivacyInfo.xcprivacy` and `Docs/ANALYTICS.md`.
- Current legal review if dollar-denominated “credit” language remains.

## 13. Primary Apple references

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Family Controls](https://developer.apple.com/documentation/familycontrols)
- [Requesting the Family Controls entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)
- [ShieldConfiguration](https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration)
- [ShieldAction](https://developer.apple.com/documentation/managedsettings/shieldaction)
- [DeviceActivityEvent](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent)
- [DeviceActivityReportExtension](https://developer.apple.com/documentation/deviceactivity/deviceactivityreportextension)
- [StoreKit](https://developer.apple.com/documentation/storekit)
- [Choosing a StoreKit API](https://developer.apple.com/documentation/storekit/choosing-a-storekit-api-for-in-app-purchases)
