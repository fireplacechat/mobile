# iOS preview setup and upgrade checks

The notification service and shared-storage foundation shipped in v0.3.7.
The startup regression on upgraded installations is still under investigation.
Signed inspection reproduced missing Rust C ABI exports after archive stripping.
The fix preserves global symbols and checks unsigned archives as well as final
signed IPAs. Physical upgrade validation remains required.
Only the owner configures Apple identifiers, signs and uploads builds.

## Apple Developer configuration

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list):

1. Open **Identifiers**, choose **App Groups**, and register
   `group.com.fireplacechat.app` if it does not exist.
2. Open the existing explicit App ID `com.fireplacechat.app`. Enable
   **App Groups**, select that group, and save the configuration. Preserve
   Push Notifications and all existing capabilities.
3. Register an explicit App ID
   `com.fireplacechat.app.NotificationService`. Enable App Groups and select
   the same group. No separate App Store Connect app record is needed for
   the extension. Both App IDs need refreshed App Store profiles.
4. The repository declares keychain sharing in entitlements. The app retains
   `$(AppIdentifierPrefix)com.fireplacechat.app` first and adds
   `$(AppIdentifierPrefix)com.fireplacechat.app.shared`. The extension will
   request only the shared group. The prefix comes from the signing
   profile; do not substitute a guessed Team ID or create a new keychain
   group identifier in the portal. Preserve the original prefix, especially
   for an app transferred between teams.
5. After the foundation is merged and capabilities are saved, refresh the
   encrypted app signing material with the existing owner-run workflow:

   ```sh
   gh workflow run ios-signing-setup.yml --repo fireplacechat/mobile --ref main
   ```

   The signing lane forces a profile refresh so a still-valid old profile
   cannot silently retain the old capabilities. Inspect its result before
   an upload.

The same signing lane refreshes both app and extension profiles. Confirm
both identifiers appear in its result. Version selection/bump remains a
separate owner decision; do not reuse the already-uploaded build number.

## Unsigned Mac validation

The owner dispatches `ios.yml` on the exact PR branch. It builds all three
Rust targets, unsigned device/simulator apps, Swift tests and the core's
vector/protocol tests on the simulator. Codex reads logs and fixes failures.
Windows host checks cannot validate Apple entitlements or keychain behavior.

## TestFlight upgrade checks for shared storage

Use an upgrade of an existing installation; do not uninstall first. Keep the
recovery key available privately, without pasting it into an issue or log.

- Confirm the account identity, device and safety number are unchanged.
- Open existing chats and confirm old history, search, reactions and local
  preferences still work. Send and receive in a chat that existed before
  the upgrade, including after force-closing and reopening the app.
- Lock and unlock the phone and repeat. After restarting, the extension
  must use the original push body before the first unlock; after the first
  unlock, its shared keychain/files can be read while locked.
- Confirm sign-out/re-login still restores the Firebase session normally;
  Firebase's records retain the app's original default keychain group.
- Test a new installation/account separately after the upgrade test.

Migration copies and verifies each keychain record before deleting its
source, and moves the encrypted history directory with an atomic rename.
Conflicting copies or a failed migration stop access instead of creating new
keys. Do not delete either copy to force an upgrade through; report the
failure without attaching keychain contents or encrypted store dumps.

## Diagnostic TestFlight round

For an upgrade incident, use `mode=inspect` in the existing TestFlight workflow
to build and inspect a signed IPA without uploading it. It uses the protected
owner signing environment and can reuse the current version because it does
not upload a build. Inspection skips the redundant unsigned compilation and
goes directly to the protected signed build after checking the requested version.
Validation checks the main executable's actual dynamic
Rust exports and compares both bundles' runtime keychain configuration with
their signed entitlements, including the app's original default group. Logs
report check results, never keychain values or private signing material.

```sh
gh workflow run ios-testflight.yml --repo fireplacechat/mobile --ref main -f version=vX.Y.Z -f mode=inspect
```

Do not treat a missing-key setup screen as proof of lost keys: failures during
local-key validation can currently reach the same screen. Keep the affected
installation and avoid identity-reset actions during diagnosis. Account login,
public device registrations, an encrypted recovery backup and private local
keys are distinct recovery states; verify each before claiming restoration.

After unsigned checks, Apple configuration, signing setup and the reviewed
version bump have passed, the owner can run:

```sh
gh workflow run ios-testflight.yml --repo fireplacechat/mobile --ref main -f version=vX.Y.Z -f mode=upload -f preview_diagnostics=true
```

Replace `vX.Y.Z` with the exact reviewed version in pubspec.yaml. Existing
environment approval and signing requirements remain. This produces a test
binary with local diagnostics enabled; it must not be selected for App Store
release. The final ordinary build needs another reviewed build number and
`preview_diagnostics=false` (the default). An uploaded binary cannot have
diagnostics stripped later.

On the iPhone X (iOS 16.7), long-press **Settings > Privacy and terms** for
**Preview test results**. After each case, refresh and record outcome,
duration and peak. Aim for about 12 MB peak and under 5 seconds. An incomplete
run is not proof of memory safety; a missing run can also mean iOS did not
start the extension. Process reuse can carry an earlier higher peak forward.
These records stay on the phone and contain no message, key, token or account
identifier. Peak zero is shown as unavailable.

- Receive ordinary messages with the app closed, open, and phone locked.
- Restart, then receive before the first unlock: expect the original
  **New Message**. Unlock once, lock again, and retest previews.
- Turn **Show message preview** off and confirm the original body; turn it
  back on. Test hidden sender names and silent notifications too.
- Test poor/no network, token refresh after more than an hour closed, and
  a burst of messages. Failures must keep the original body, without losing
  any message when the app opens.
- React to an own message in a small chat: expect its quote. Test a long
  chat and one with an append log: expect a generic reaction body without
  loading the full history. Also test reactions to the other person's own
  messages: the generic fallback cannot establish ownership when history
  is capped; assess this known exception during release review.
- Edit, delete and clear a reaction. Without Apple's notification-filtering
  entitlement these retain the incoming push's **New Message**; existing
  delivered alerts are not updated/removed by this first extension. Confirm
  the app still applies every stored mutation normally.
- Sign out during a delayed receive: it must not show new plaintext after
  credential revocation. Sign in again and verify existing keys/history.
- Open the app after every case and confirm each message is received once,
  existing sessions continue and one-time prekeys are consumed by the app.

The production app defaults to Rust after the owner's integration review.
Keep the Dart reference until a working release has been validated and the
owner explicitly approves its removal.
