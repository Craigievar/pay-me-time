# Apple distribution checklist

Screenbump uses Family Controls in the containing app and four embedded
extensions. Simulator builds are working. Device, TestFlight, and App Store
builds require the account, identifier, and distribution steps below.

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
2. Under **Identifiers**, register App Group
   `group.com.nonagon.Screenbump` if it does not already exist.
3. Register each explicit App ID listed below if it does not already exist.
4. Open every App ID and enable **Family Controls** and App Group
   `group.com.nonagon.Screenbump`.
5. Follow Apple's
   [Family Controls entitlement request](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)
   flow for every identifier:

   - `com.nonagon.Screenbump`
   - `com.nonagon.Screenbump.ShieldConfiguration`
   - `com.nonagon.Screenbump.ShieldAction`
   - `com.nonagon.Screenbump.DeviceActivityMonitor`
   - `com.nonagon.Screenbump.DeviceActivityReport`

6. Track the requests under **Certificates, Identifiers & Profiles →
   Capability Requests**.

Success: Family Controls distribution status is **Assigned** for all five
identifiers. Development approval alone is not enough for TestFlight.

## 4. Create the App Store Connect record

Role: Account Holder, Admin, or App Manager.

1. In [App Store Connect](https://appstoreconnect.apple.com/), open
   **Apps → + → New App**.
2. Choose platform **iOS**.
3. Enter app name **Screenbump**.
4. Choose primary language **English (U.S.)**.
5. Select bundle ID `com.nonagon.Screenbump`.
6. Enter a unique SKU such as `screenbump-ios`.
7. Grant the appropriate user access and create the record.

Success: **Screenbump** appears under Apps with bundle ID
`com.nonagon.Screenbump`.

## 5. Return for archive and upload

Send back:

- “Apple Distribution is installed.”
- “All five Family Controls requests are Assigned.”
- “The Screenbump App Store Connect record exists.”

Codex will then regenerate the project, archive the pushed Git revision, inspect
the signed entitlements in the archive, validate the export, and upload the build
to App Store Connect. Upload does not submit the app for review or release it.

Before every upload, run both entitlement gates. They intentionally fail the
release if the checked-in XcodeGen configuration, generated project, archive, or
exported IPA drops Family Controls from any shipping target:

```sh
make verify-entitlements
make verify-archive-entitlements ARCHIVE=/path/to/Screenbump.xcarchive
make verify-ipa-entitlements IPA=/path/to/Screenbump.ipa
```
