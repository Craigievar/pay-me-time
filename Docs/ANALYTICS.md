# Analytics contract

**Provider:** PostHog
**Mode:** anonymous event analytics and autocapture
**Session replay:** disabled

## Configuration

`make project` runs `Scripts/configure-posthog.sh`. The script reads
`SCREENBUMP_POSTHOG_KEY` from the environment and writes only the client-side
project token to the gitignored `Config/PostHog.local.xcconfig`. The app runs with
analytics disabled when the token is unavailable.

The SDK never creates identified person profiles. Collection is always on when
PostHog is configured; the app does not expose an analytics preference.
Existing installs that previously opted out are opted back in on launch. When
PostHog is not configured, extensions drop analytics events and the app remains
fully functional.

## Privacy boundary

Never send:

- `ApplicationToken` values or their serialized keys;
- selected app names, bundle identifiers, icons, or categories;
- Screen Time authorization tokens;
- free-form user text;
- a stable identifier that can identify an app across selection cohorts.

Opaque Screen Time token keys and their mapping to random app IDs stay in the App
Group. A new random ID is created when the selected-token set changes. PostHog
therefore receives only an unlinkable label such as `anonymous_app_id`, never the
underlying app identity.

Selected-app labels and Device Activity reports use PostHog's `ph-no-capture`
accessibility identifier. Session replay remains disabled in SDK configuration.
The privacy manifest declares Product Interaction, Other Usage Data, and Purchase
History for analytics; none is linked to identity or used for tracking.

The public privacy policy and App Store privacy-label answers must match this
contract before release.

## Explicit event taxonomy

| Event | Purpose and important properties |
| --- | --- |
| `onboarding completed` | Initial funnel completion and configured defaults |
| `screen time authorization completed` | Approval outcome only |
| `app selection completed` | Cohort ID, selected count, initial/change |
| `app selection cleared` | Previous selected count |
| `protection rate changed` | Scope, old/new rate; no app identity |
| `free allowance changed` | Old/new daily minutes |
| `protection toggled` | Enabled state |
| `shield action selected` | `pay` or `go_back`, source, window/cost when relevant |
| `access window blocked` | Insufficient credit or disabled protection |
| `access window started` | Duration, rate, reserved credit, source |
| `access window ended` | Elapsed duration and whether ended early |
| `free allowance reached` | Extension threshold event |
| `payment completed` | Credit amount and verification mode |
| `credit granted` | Credit amount, source, `is_free`, resulting balance |
| `credit spent` | Debit amount, source, resulting balance |
| `refill opened` | Entry source |
| `refill pack selected` | Selected credit amount |
| `storekit error` | Failure stage, stable reason, error domain/code, and catalog counts when available |
| `rating request action` | User selected `rate` or `dismiss` on the one-time halfway CTA |
| `screen viewed` | Stable app-owned screen name |
| `screen time milestone reached` | Milestone, seven-day duration, baseline and percent |

The refill UI uses StoreKit 2. It emits `payment completed` with
`storekit_verified=true` and `payment_mode=storekit`, followed by the matching
credit event, only after verified, idempotent transaction delivery has been
durably persisted. Duplicate transaction updates do not emit another grant.

## Screen Time milestone method

When the user completes app selection:

1. Create a selection cohort for that exact token set.
2. Measure the preceding seven days immediately as `baseline`.
3. Measure matching trailing-seven-day windows at `week_1`, `week_2`, and
   `week_4`.
4. Continue at `month_2`, `month_3`, and monthly thereafter.

Each checkpoint emits one `overall` event and one event per local random app ID.
Properties include:

- `selection_cohort_id`;
- `milestone` and `milestone_sequence`;
- `measurement_window_days=7`;
- `days_since_selection`;
- `duration_seconds`;
- `baseline_duration_seconds`;
- `percent_of_baseline` when the baseline is nonzero;
- `scope=overall|anonymized_app`;
- `app_count` for overall or `anonymous_app_id` for per-app events.

The Device Activity Report extension performs the aggregation. It queues event
payloads in the App Group, and the containing app sends them on its next active
launch. Missed checkpoints remain pending until the report can run.

## Autocapture

The SDK captures application lifecycle, SwiftUI/UIKit screen, and supported
element-interaction events. Automatic screen events are supplemented by
app-owned `screen viewed` events with stable names. Session replay, surveys,
identified person profiles, and default person properties are disabled.
Automatic crash/error capture is also disabled. StoreKit catalog, purchase, and
transaction-delivery failures are captured manually as privacy-safe
`storekit error` events so TestFlight failures can be diagnosed without sending
account or payment details.
