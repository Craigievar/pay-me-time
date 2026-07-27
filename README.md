# Screenbump

Screenbump is a native iPhone commitment app. It gives people a configurable amount of free daily time in selected distracting apps, then makes additional access consume a deliberately tiny prepaid balance.

This repository contains a working native app, Screen Time extensions, StoreKit
credit refills, visual concepts, and the remaining release-validation plan:

- [Running SwiftUI app](PayMeTime)
- [XcodeGen project source](project.yml)
- [Verified Simulator screenshots](Docs/Screenshots)
- [Core flow mock](Docs/Mocks/pay-me-time-core-flow.png)
- [Meter state mock](Docs/Mocks/pay-me-time-meter-states.png)
- [Mock notes and prompts](Docs/MOCKS.md)
- [Analytics contract](Docs/ANALYTICS.md)
- [Technical plan](Docs/TECHNICAL_PLAN.md)
- [Starting context for a new Codex task](Docs/STARTING_CONTEXT.md)

## Current decision

Proceed with a free-to-download MVP that starts every user with $2.00 in attention
credit and sells optional refills through In-App Purchase.

Apple's current App Review Guideline 4.10 creates review ambiguity around monetizing Screen Time APIs, but current App Store evidence shows multiple approved apps selling subscriptions or lifetime access around Screen Time-powered blocking. Screenbump should keep its core experience and starter credit free, use StoreKit only for optional refills, and never claim to sell access to Apple's API itself.

Use StoreKit for refills, describe the business model candidly in review notes, request the required Family Controls distribution entitlements early, and preserve competitive evidence. App Review remains a managed release risk rather than a reason to stop building.

## Run

```sh
make project
make check
make test
```

`make project` reads `SCREENBUMP_POSTHOG_KEY` from the environment and writes it
to the gitignored `Config/PostHog.local.xcconfig`. If the key is absent, analytics
stays disabled and the app continues to work.

The implemented app includes onboarding, a persistent $2 starting balance, a 1¢ global default, 1–5¢ per-app overrides, configurable free daily time, live access-window math, explicit shield states, StoreKit refill purchases, settings, and clearly labeled deterministic UI fixtures. A dedicated Progress tab charts the last seven days in protected apps and compares that total with the seven-day baseline captured when the current app selection was made.

The production path now requests individual Family Controls authorization and presents Apple's real `FamilyActivityPicker`. Normal installs begin with no selected apps because Apple does not let an app silently preload named applications. Selected apps render with Apple's privacy-preserving labels and icons. A Device Activity Report extension shows real per-app time, sorted from most-used to least-used, and powers the private on-device Progress trend. Its cost column is deliberately sourced from the app's actual access-window ledger snapshot rather than inventing a foreground-use charge.

Five shipping targets compile with Family Controls and the shared App Group: the
containing app, Device Activity Monitor, Shield Configuration, Shield Action,
and Device Activity Report. The previous prototype identifiers signed for
development; the `com.nonagon.Screenbump` identifiers require fresh Apple
registration and provisioning. The daily threshold, atomic
debit/unshield/re-shield path, and verified idempotent StoreKit delivery are
implemented. App Store Connect metadata/availability, StoreKit Sandbox and
TestFlight verification, Family Controls distribution approval, and the
complete on-device behavior matrix remain release gates. Named Simulator
fixtures are explicitly labeled as demo data.

PostHog provides anonymous event analytics, app lifecycle/screen/interaction
autocapture, payment and credit events, shield choices, and privacy-preserving
Screen Time milestones. Session replay is explicitly disabled. Progress remains
available when analytics is not configured; its selection date and Screen Time
totals stay on-device. Selected app names and Screen Time tokens remain
on-device.
