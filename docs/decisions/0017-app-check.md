# 0017: App Check in monitoring mode

Date: 2026-10-07

## Decision

Activate Firebase App Check before Auth or Firestore use, with automatic refresh.
Debug builds use debug providers; release builds use Android Play Integrity and
Apple App Attest with DeviceCheck fallback. Emulator builds and
`APP_CHECK_OFF=true` skip activation. Failures do not stop startup, and startup
does not wait for a token.

This is **monitoring only**. Enforcement is a separate, manual owner action in
Firebase console. No Firestore rules, authentication flow, server fields or iOS
project/entitlement files change. The Apple account, entitlement and registration
remain owner setup steps. No paid plan is enabled.

Unpublished sideloaded Android beta builds cannot meet the default
`PLAY_RECOGNIZED` requirement and are expected unverified until Google Play
distribution. This is a configuration constraint, not a universal limitation:
[Firebase supports outside-Play configurations](https://firebase.google.com/docs/app-check/android/play-integrity-provider).
Changing those settings is outside this decision. The first request after
installation may carry no valid token; monitoring must tolerate that.

## Consequences

Observe real traffic for at least a week before deciding on enforcement. Keep
services Unenforced now. Debug tokens stay private and never ship in release.
Client activation alone does not reject unverified users. See the
[setup and rollback guide](../development/app-check.md) and
[Firebase's Flutter setup](https://firebase.google.com/docs/app-check/flutter/default-providers).
