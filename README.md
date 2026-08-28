# IntuneSDKTest

A small Apple Notes-style SwiftUI app for learning how to integrate the Microsoft Authentication Library (MSAL) and Microsoft Intune App SDK for iOS.

## What is included

- Add, edit, and swipe-delete local notes.
- MSAL interactive sign-in with `User.Read`.
- MSAL broker callback handling for Microsoft Authenticator.
- Intune MAM enrollment after MSAL sign-in.
- Account screen showing the current Intune enrollment state.
- Ordered Intune deregistration, selective wipe, and MSAL sign-out.
- Local JSON persistence using iOS file protection.
- Comments in `AuthenticationService.swift`, `SceneDelegate.swift`, and `NotesStore.swift` explaining the integration points.

The target is iOS 17+ because the current IntuneMAM Swift package requires iOS 17 or newer.

## Configure Entra ID

1. Register an app in **Microsoft Entra admin center > App registrations**.
2. Add the iOS platform with bundle ID `com.example.IntuneSDKTest`.
3. Confirm the redirect URI is `msauth.com.example.IntuneSDKTest://auth`.
4. Add delegated Microsoft Graph permission `User.Read`.
5. Add **APIs my organization uses > Microsoft Mobile Application Management > DeviceManagementManagedApps.ReadWrite**.
6. Grant admin consent if your tenant requires it.
7. Put the application (client) ID and directory (tenant) ID into `Info.plist`, replacing `YOUR_CLIENT_ID` and `YOUR_TENANT_ID`.

Do not put a client secret in an iOS app.

## Open and run

This repository includes `IntuneSDKTest.xcodeproj`. Open it on macOS with Xcode 16 or later, select an Apple development team, and let Swift Package Manager resolve:

- MSAL: `https://github.com/AzureAD/microsoft-authentication-library-for-objc`
- IntuneMAM: `https://github.com/microsoftconnect/ms-intune-app-sdk-ios`

The project links `MSAL` and `IntuneMAMSwift`. It also includes the Intune and MSAL shared keychain groups in `IntuneSDKTest.entitlements`.

Use a physical iPhone or iPad for broker and Intune policy testing. The Intune SDK can be linked successfully without a managed tenant, but policies and enrollment status require an Intune-licensed test user.

## Test Intune policy

1. In Intune admin center, create an iOS/iPadOS app protection policy.
2. Add this app as a custom app using the exact bundle ID.
3. Assign the policy to the test user.
4. Require an app PIN for an obvious first policy test.
5. Sign in to the app, wait for enrollment, and open **Account** to refresh the status.
6. Create, edit, delete, and sign out to exercise the complete sample flow.

## Important files

- `AuthenticationService.swift`: MSAL setup, token acquisition, Intune enrollment, and sign-out ordering.
- `SceneDelegate.swift`: required MSAL redirect callback and SwiftUI scene bridge.
- `Info.plist`: redirect URL, broker schemes, and `IntuneMAMSettings`.
- `IntuneSDKTest.entitlements`: MSAL and Intune shared keychain groups.
- `NotesStore.swift`: note CRUD and file-protected local persistence.
- `RootView.swift`: sign-in, notes list/editor, and enrollment UI.

This is a learning sample, not a production-ready managed-data implementation. Production apps should add Intune enrollment/policy delegates, selective-wipe handling for every corporate data store, Conditional Access remediation, accessibility tests, and the current Intune iOS integration checklist. Set `VerboseLoggingEnabled` to `false` before shipping.
