# Implementation record

**Implemented:** July 26, 2026

## User-visible app

- Native Swift 6 and SwiftUI app targeting iOS 18+.
- Free-download product model with a $2.00 starting attention-credit grant.
- Warm editorial home with the attention-credit balance as the dominant element.
- First-run setup says “You start with $2.00 in credits.”
- First-run setup leads with “Your time is valuable,” stages the research,
  explicit-cost, and included-credit cards with one-second fades, then reveals
  the app picker, global grace period, and activation controls.
- The app-picker row is the single setup action and changes from “Choose apps
  that you'll pay for” to “Change apps” after selection.
- Global charge default starts at 1¢/hour and is capped at 5¢.
- Each protected app may inherit the global rate or define its own 1–5¢ override.
- Configurable free daily time.
- Integer-microcent access-window calculations and a live countdown.
- A one-time Home rating CTA appears when the untouched starter balance reaches
  $1.00, halfway through its first rundown. It is permanently suppressed after
  a refill or after either CTA action.
- Daily aggregate Device Activity monitoring that includes activity accumulated
  earlier in the current day when protection is registered or updated.
- A named Managed Settings shield applied to every selected app when the shared
  free allowance is reached.
- Cross-process locked App Group credit reservations, per-app daily cost totals,
  immediate single-app unshielding, and one-off expiry monitoring that restores
  the shield after the purchased window.
- Dynamic system-shield copy showing the selected app's effective rate, exact
  window cost, duration, and current attention-credit balance.
- $1, $5, $10, and $25 refill sheet.
- Standalone advance credit-purchase action in Settings.
- Persistent local state outside deterministic test fixtures.
- One-time migration adds the second starter dollar to existing prototype state.
- Screen Bump flexing-bar Home Screen icon configured through
  `AppIcon.appiconset`; the selected 1,254-pixel master is retained as
  `Docs/Brand/ScreenBump-AppIcon-Master.png`.
- Explicit free-time, credit, and empty-credit shield presentations.
- Visible pause and “disable this block and stop protecting your time” recovery.
- Light and dark adaptive semantic surfaces.
- PostHog event analytics with lifecycle, screen, and interaction autocapture.
- Session replay explicitly disabled, an in-app anonymous-analytics opt-out, and
  `ph-no-capture` boundaries on selected-app labels/reports.
- Aggregate and randomly pseudonymized per-selection Screen Time milestones for
  baseline, weeks 1/2/4, and monthly follow-ups.
- A fourth bottom tab, Progress, with a seven-day protected-app time-series,
  baseline-average guide, and last-seven-days versus pre-selection baseline
  comparison. The comparison waits for a complete post-selection week.
- Payment, free/paid credit, refill-funnel, shield pay/go-back, protection,
  onboarding, and authorization events.

## Targets

- `PayMeTime`
- `PayMeTimeShieldConfiguration`
- `PayMeTimeShieldAction`
- `PayMeTimeDeviceActivityMonitor`
- `PayMeTimeDeviceActivityReport`
- `PayMeTimeTests`
- `PayMeTimeUITests`

The extension targets now implement the daily threshold, system shield, atomic
reservation, timed unshield, and automatic re-shield path. These mutations still
require the physical verification matrix below because Simulator builds cannot
exercise Screen Time enforcement.

## Verification

- Isolated Debug build of the app and all extensions: passed on iOS 26.2.
- Signed Debug device build: passed for Craig's iPhone 15.
- Physical installation and launch previously passed on July 26, 2026 under the
  prototype identifier. The current shipping identifier is
  `com.nonagon.Screenbump` and requires fresh provisioning.
- Current unit suite: 19 passed, 0 failed.
- Existing UI suite: 8 focused journeys passed.
- Focused Progress verification: 2 unit tests and 1 bottom-tab UI journey
  passed after the final integration change.
- Visually inspected onboarding, home, the halfway rating CTA, protection,
  settings, the Home Screen app icon, the four-tab shell, and Progress.

## Remaining physical and commerce work

- Complete the physical iPhone threshold, debit, unshield, and timed re-shield
  verification matrix, including midnight, reboot, and selection changes.
- StoreKit 2 product loading, verified consumable delivery, refund handling, and Sandbox tests.
- Family Controls distribution entitlement requests for every relevant target.
