# Apple distribution checklist

Pay Me Time uses Family Controls in the containing app and four embedded
extensions. Development signing is working. TestFlight and App Store uploads
require the account and distribution steps below.

## 1. Accept current agreements

Role: Apple Developer Account Holder.

1. Open [App Store Connect](https://appstoreconnect.apple.com/).
2. Open **Business** and review any agreement marked **Action Required**.
3. Complete any missing banking or tax information if Apple requires it.

Success: App Store Connect shows no agreement blocking new app creation or build
uploads.

## 2. Create an Apple Distribution certificate

Role: Account Holder or Admin with certificate access.

1. Open Xcode.
2. Choose **Xcode → Settings… → Accounts**.
3. Select the Apple ID and team `9JWU7V7424`.
4. Click **Manage Certificates…**.
5. Click **+**, then choose **Apple Distribution**.

Do not export or send the private key. Leave the certificate in the login
Keychain.

Success: `security find-identity -v -p codesigning` lists both Apple Development
and Apple Distribution identities.

## 3. Request Family Controls distribution access

Role: Apple Developer Account Holder.

1. Open [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list).
2. Open **Identifiers** and select each App ID listed below.
3. Confirm **Family Controls** and App Group
   `group.com.craig.paymetime` are enabled.
4. Follow Apple's
   [Family Controls entitlement request](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)
   flow for every identifier:

   - `com.craig.PayMeTime`
   - `com.craig.PayMeTime.ShieldConfiguration`
   - `com.craig.PayMeTime.ShieldAction`
   - `com.craig.PayMeTime.DeviceActivityMonitor`
   - `com.craig.PayMeTime.DeviceActivityReport`

5. Track the requests under **Certificates, Identifiers & Profiles →
   Capability Requests**.

Success: Family Controls distribution status is **Assigned** for all five
identifiers. Development approval alone is not enough for TestFlight.

## 4. Create the App Store Connect record

Role: Account Holder, Admin, or App Manager.

1. In [App Store Connect](https://appstoreconnect.apple.com/), open
   **Apps → + → New App**.
2. Choose platform **iOS**.
3. Enter app name **Pay Me Time**.
4. Choose primary language **English (U.S.)**.
5. Select bundle ID `com.craig.PayMeTime`.
6. Enter a unique SKU such as `pay-me-time-ios`.
7. Grant the appropriate user access and create the record.

Success: **Pay Me Time** appears under Apps with bundle ID
`com.craig.PayMeTime`.

## 5. Return for archive and upload

Send back:

- “Apple Distribution is installed.”
- “All five Family Controls requests are Assigned.”
- “The Pay Me Time App Store Connect record exists.”

Codex will then regenerate the project, archive the pushed Git revision, inspect
the signed entitlements in the archive, validate the export, and upload the build
to App Store Connect. Upload does not submit the app for review or release it.
