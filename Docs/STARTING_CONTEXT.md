# Starting context for a new Codex task

Copy the block below into a new Codex task when implementation begins.

```text
Use $craig-app-development for this project.

We are building a separate native iPhone app named “Pay Me Time.” Start by reading
README.md, Docs/MOCKS.md, and Docs/TECHNICAL_PLAN.md completely. Treat project.yml
as the future Xcode project source of truth.

PRODUCT PROMISE

Pay Me Time is a calm adult commitment app. A user chooses distracting apps, a
small rate capped at 5¢ per hour, and a free daily allowance. Selected apps work
normally during the allowance. After it is used, an Apple Screen Time shield
requires a deliberate, prepaid access window. Commitment credit counts down; it
never becomes an open-ended bill.

MONEY MODEL

- The app is free to download.
- Start every user with 200¢ of non-cash, non-transferable attention credit.
- User rate: exactly 1–5¢ per hour, never higher.
- Daily free time: configurable, default 60 minutes.
- During setup, choose a default 5-, 15-, or 30-minute access window and show
  the exact cost of every choice.
- After free time, the shield offers the configured window. Reserve its exact
  cost before unshielding and never silently extend it.
- At zero balance, protected apps remain shielded until the user refills, pauses,
  or revokes permission.
- Refill choices: 100¢, 500¢, 1,000¢, and 2,500¢ through StoreKit consumable IAP.
- Purchased credit never expires and has no cash redemption value.
- Do not use Stripe, postpaid billing, or a subscription for this version.

PLATFORM HONESTY

The Apple-managed shield is not an arbitrary SwiftUI screen. It may show a balance
snapshot and exact button copy, but it cannot show a continuously ticking custom
meter. Put the live countdown in the containing app and consider a Live Activity
only after the core flow works.

Do not claim exact foreground measurement. A paid access window is a fixed wall-
clock interval during which selected apps are unshielded. It is not a continuous
charge based on unknowable app foreground time.

MONETIZATION AND APP REVIEW

Apple's current App Review Guideline 4.10 explicitly says apps may not monetize
Screen Time APIs, so retain this as a review risk. Do not interpret it as an
automatic prohibition on a monetized Screen Time-powered app.

Current approved App Store products including Opal, Jomo, and Roots explicitly
use Screen Time-powered blocking while selling subscriptions or lifetime access.
one sec is adjacent evidence for monetized intentional-use friction. This observed
review practice supports building a monetized MVP.

Keep the core experience and initial $2.00 grant free. Position optional refills as
part of the complete app-owned commitment product, never as payment for access to
Apple's API, and never hide that Screen Time frameworks enforce the selected-app
shield.

Use StoreKit for the non-expiring refills under Guideline 3.1.1. Request Family
Controls distribution entitlements early, keep a dated competitor-parity record,
prepare candid review notes, and submit a deliberately narrow complete MVP.

DESIGN

Follow the checked-in mock boards. The product should feel like a calm financial
instrument: warm ivory or deep warm-neutral canvas, charcoal text, amber action
accent, sage free-time accent, editorial hierarchy, native controls, hairlines
before shadows, and plain exact copy.

Avoid shame, aggressive red, coins, points, gems, streaks, confetti, fake
currencies, neon gradients, generic AI visuals, and any language suggesting that
individual Screen Time authorization is tamper-proof.

TECHNICAL DEFAULTS

- Swift 6, SwiftUI, Observation, iPhone-first, iOS 18+.
- XcodeGen project.yml.
- @MainActor app store with injected service protocols and deterministic mocks.
- App Group shared state.
- FamilyControls, ManagedSettings, ManagedSettingsUI, and DeviceActivity.
- Containing app plus Device Activity Monitor, Shield Configuration, and Shield
  Action extensions, plus a Device Activity Report extension.
- StoreKit 2 consumables after the Screen Time spike passes.
- Append-only integer-microcent ledger; never use floating point for money.
- Keep privacy-preserving app tokens on-device and never log selected app identity.
- No app-owned backend until review viability and reinstall/multi-device
  requirements justify it. The existing PostHog event-only analytics integration
  is the bounded exception.

CURRENT REPOSITORY STATE

- The real individual Family Controls authorization request and
  `FamilyActivityPicker` are implemented.
- Production starts with no selected apps; Apple does not permit silent
  preloading. Opaque selected-app tokens persist in `group.com.nonagon.Screenbump`.
- Apple's token-based labels provide the real app names and icons.
- The Protection screen has a 1¢ global default, 1–5¢ per-app overrides, and a
  Device Activity report sorted by real time spent.
- Per-app cost must come from actual reserved access-window ledger entries, not
  estimated foreground activity.
- All five shipping targets have working development profiles with Family
  Controls and the App Group. Distribution entitlement approval is still a
  release gate.
- Daily threshold enforcement, atomic reserve/unshield/re-shield, real StoreKit
  delivery, and full physical-device proof remain unfinished.
- PostHog is integrated for anonymous event analytics and autocapture. Session
  replay is explicitly disabled. Preserve `Docs/ANALYTICS.md`, the user opt-out,
  and the rule that selected app names/tokens never leave the device.

VALIDATION TARGET

Success is not compilation. On a physical iPhone:

1. cumulative selected-app use reaches the configured free allowance;
2. the selected app becomes shielded;
3. the shield shows the correct rate, balance snapshot, and exact window cost;
4. one explicit action reserves credit and opens one bounded access window;
5. expiry re-shields the app;
6. the ledger contains exactly one debit;
7. zero balance never unshields;
8. revocation, scheduling failure, duplicate events, and interruption never
   create an unexplained debit.
```
