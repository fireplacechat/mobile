# iOS preview setup and upgrade checks

The shared-storage foundation is under review. The notification extension
and preview setting follow separately; this is not a release announcement.
Only the owner configures Apple identifiers, signs and uploads builds.

## Apple Developer configuration

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list):

1. Open **Identifiers**, choose **App Groups**, and register
   `group.com.fireplacechat.app` if it does not exist.
2. Open the existing explicit App ID `com.fireplacechat.app`. Enable
   **App Groups**, select that group, and save the configuration. Preserve
   Push Notifications and all existing capabilities.
3. For the upcoming extension, register an explicit App ID
   `com.fireplacechat.app.NotificationService`. Enable App Groups and select
   the same group. No separate App Store Connect app record is needed for
   the extension. Its target and signing profile are added in the extension
   PR; creating the identifier does not ship it.
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

The extension PR will add its profile to the same signing lane and provide
the final TestFlight inputs. No version bump or upload is requested here.

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

The extension PR adds the notification and iPhone X memory/timing checklist.
