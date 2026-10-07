# App Check

App Check attaches app-attestation tokens to Firebase requests. It does not replace
authentication or the Firestore rules. Startup activates it after Firebase
initialization, before Auth or Firestore use. Activation failures are ignored;
startup does not request or wait for a token. Automatic refresh is enabled.

| Mode | Client | Firebase console |
|---|---|---|
| Off | `USE_EMULATOR=true` or `APP_CHECK_OFF=true` skips activation | Leave services Unenforced |
| Monitoring (this change) | Debug providers in debug builds; Play Integrity and App Attest with DeviceCheck fallback in release | Leave services Unenforced |
| Enforced (later owner decision) | Same client | Owner enables enforcement per service |

`flutter run --dart-define=USE_EMULATOR=true` uses the existing emulators.
`flutter run --dart-define=APP_CHECK_OFF=true` skips App Check without selecting
emulators. Neither flag disables server enforcement. Release provider selection
uses Flutter's `kDebugMode`; there is no define that selects a debug provider in
release. The first request after installation may have no valid token.

See [Firebase's Flutter setup](https://firebase.google.com/docs/app-check/flutter/default-providers)
and [decision 0017](../decisions/0017-app-check.md).

## Owner setup

1. In Firebase console, App Check, register Android with Play Integrity and the
   Google Play app-signing SHA-256 ([Android release guide](android-release.md)).
   Link the Play Integrity API to the Firebase project in Google Play Console.
   Unpublished sideloaded beta APKs are expected unverified with the default
   `PLAY_RECOGNIZED` requirement. Firebase supports other distribution settings;
   this change does not select them. See [Play Integrity setup](https://firebase.google.com/docs/app-check/android/play-integrity-provider).
2. After obtaining the Apple Developer account, register iOS with App Attest.
   In Xcode, Runner → Signing & Capabilities, add App Attest. This creates the
   entitlement and developer-portal configuration. This PR edits neither.
3. Leave Firestore, Authentication and Cloud Storage (if used) **Unenforced**.
   Observe verified/unverified traffic for at least one week of real use.
   Later, consider Firestore first and Authentication last; check whether Auth
   enforcement needs a plan upgrade. Do not enable paid plans.
4. Rollback enforcement on that console page by selecting Unenforced; no release
   is needed. Client rollback uses the next build's `APP_CHECK_OFF=true`.

## Debug tokens

Run a debug build against Firebase, without `USE_EMULATOR` or `APP_CHECK_OFF`.
The native SDK logs its debug token; on Apple, enable `-FIRDebugEnabled` in the
local Xcode run scheme if needed. Register it under App Check → app → Manage
debug tokens. Keep the token private: never commit it, capture it in review logs
or include it in a release. Revoke a compromised token in that console page.
See [Firebase's debug-provider guide](https://firebase.google.com/docs/app-check/flutter/debug-provider).

## Verification and limits

Linux checks cover provider selection, skip flags, failure tolerance, existing
tests, unchanged previews and release APK permissions. No real attestation was
run here. iOS compilation and device/console verification remain owner steps;
there are no iOS project or entitlements changes. Do not enforce until legitimate
beta installations have been observed and the owner approves it.
