# iOS releases through TestFlight

The owner completes this checklist after Apple verifies the account. These manual
workflows do not submit an App Store release. Never run signing or upload from a
pull request. The check job needs no secrets and creates no environment.

## Owner checklist

1. In the Apple Developer portal, **Certificates, Identifiers & Profiles →
   Identifiers → + → App IDs → Continue**, register an explicit App ID with bundle
   identifier `com.fireplacechat.app`. Use the team that owns the app; record its
   Team ID from **Membership details**. See [register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id/).
2. In App Store Connect, **Apps → + → New App**, choose iOS and enter the app
   name, primary language, that bundle ID and an owner-chosen SKU. See
   [add an app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).
3. In **Users and Access → Integrations → App Store Connect API → Team Keys**,
   have the Account Holder or an Admin create a team API key with **App Manager**
   or **Admin** access. Record the Key ID and Issuer ID, and download the `.p8`
   once; Apple does not allow downloading it again. Team keys cover the team's
   apps, so keep this key private. No Apple ID password or two-factor code is
   used by CI. See [App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api).
4. Create the **private** repository `fireplacechat/ios-certs`. Create a
   fine-grained GitHub personal access token restricted to that repository,
   **Contents: read and write**. Set `MATCH_GIT_URL` to its HTTPS Git URL and
   `MATCH_GIT_BASIC_AUTHORIZATION` to base64 of `username:token`, without a trailing
   newline. Do not paste credentials into a command that will be saved in shell
   history. Choose a strong `MATCH_PASSWORD` and keep it in a password manager;
   losing it loses access to the encrypted signing material. See
   [match](https://docs.fastlane.tools/actions/match/) and
   [fine-grained tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).
5. **Before any signing or upload run**, open the mobile repository's
   **Settings → Environments → New environment** and create `ios-release`.
   Add the owner under **Required reviewers**, and restrict **Deployment branches
   and tags** to the `main` branch. Then add these seven **environment secrets**,
   not repository secrets:

   | Secret | Value |
   |---|---|
   | `ASC_KEY_ID` | Apple API Key ID |
   | `ASC_ISSUER_ID` | Apple team Issuer ID |
   | `ASC_KEY_P8` | Entire downloaded private key text |
   | `APPLE_TEAM_ID` | Apple Developer Team ID |
   | `MATCH_PASSWORD` | Signing repository encryption password |
   | `MATCH_GIT_URL` | Private signing repository HTTPS URL |
   | `MATCH_GIT_BASIC_AUTHORIZATION` | Base64 of the repository username and scoped token |

   GitHub automatically creates an **unprotected** environment if a workflow
   names one that does not exist. Pre-create and verify these protections; do not
   use a workflow run to create the environment. See
   [deployment environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).
6. In **Actions → iOS signing setup → Run workflow**, choose **main** and approve
   the protected environment deployment. Run it once to create the encrypted
   distribution certificate and App Store provisioning profile. It can refresh
   signing material later only when the owner deliberately runs it again.
7. In **Actions → iOS TestFlight → Run workflow**, choose **main**, version
   `vX.Y.Z` matching `pubspec.yaml`, and **check** first. It builds without signing
   and prints the built app's short version and build number (initially `0.1.0`
   and `000100`). It uses no signing secrets. Once green, run **upload** and approve
   the protected environment. Upload first repeats the unsigned check, then uses
   existing match material read-only, builds an IPA and sends it to TestFlight.
   The upload lane cannot create signing certificates. Workflow dispatch becomes
   available only once these workflow files are merged onto the default branch.
8. In App Store Connect, **Apps → Fireplace → TestFlight → Internal Testing → +**,
   create an internal group, select the build and add the owner as an internal
   tester (an App Store Connect user). Install Apple's **TestFlight** app on the
   iPhone and accept the invitation. Processing can take time after upload; CI
   intentionally does not wait for it. See [internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/).
9. The **owner decides** the encryption/export-compliance answer. The current
   `ITSAppUsesNonExemptEncryption = false` declaration records the owner's
   questionnaire result: standard encryption implemented in addition to Apple's
   operating-system encryption, no distribution in France, and no documents
   required by App Store Connect. It does not mean the app has no encryption.
   No `ITSEncryptionExportComplianceCode` is supplied. See
   [Apple's definition of the declaration](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).
   The owner must keep distribution settings consistent with these answers;
   this plist does not restrict availability in France. Reassess the declaration
   before changing encryption or enabling distribution in France. If a build
   shows **Missing Compliance**, use **TestFlight → the build → Manage** to
   answer Apple's questions. See [beta export compliance](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds/).
10. First-build limits: push is off. App Attest is not enabled yet; App Check may
    show iOS as unverified until its entitlement is added in a later step. Keep
    App Check in monitoring mode; do not enable enforcement for this build.

The same [version rules](releasing.md#version-numbers) apply to both stores.
`CFBundleVersion` comes from the part after `+` in `pubspec.yaml`; Apple compares
its numeric components as integers, so zero padding is fine. Increase it for every
upload. For a rebuild, bump the patch version rather than reusing a tag/build.
See [Apple's bundle version definition](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html).

## Implementation and safety

Both workflows are manual-only and accept dispatched `main` only. All actions
are pinned. The upload job requires a successful unsigned check and the protected
`ios-release` environment; signing secrets exist only in signing/upload steps.
The API key file has mode 600 in runner temporary storage and is removed by an
always-run cleanup step. Credentials are masked before use. No IPA, key or
certificate is attached to GitHub releases or uploaded as an Actions artifact.

Fastlane match encrypts the signing repository. The beta lane uses a temporary
CI keychain, sets manual signing only in the ephemeral checkout, and runs
`flutter build ipa --release --export-options-plist=...`, following
[Flutter's iOS deployment route](https://docs.flutter.dev/deployment/ios).
The export method is `app-store-connect`, the current Xcode name for App Store
export. The temporary export plist obtains its profile name from match.

## When it fails

| Failure | Owner check |
|---|---|
| Wrong team or unavailable signing identity | Verify `APPLE_TEAM_ID` matches the registered identifier and API key team. |
| Profile does not match bundle identifier | Verify `com.fireplacechat.app` and the team; refresh using signing setup only after reviewing the mismatch. Upload remains read-only. |
| Build number already used | Bump the patch version and its build number in `pubspec.yaml`, merge and rebuild. |
| Missing Compliance | Answer the owner-reviewed encryption questions for the build in TestFlight. |
| Missing environment secret or approval | Verify the pre-created protected `ios-release` environment and its seven secrets. |

## Allowed actions
The repository allows only GitHub-owned actions and the pinned `subosito/flutter-action` (Settings, Actions, General). The iOS workflows therefore use the Ruby and Bundler already on the macOS runner and install fastlane from `ios/Gemfile.lock`; do not add a third-party action to them without adding it to that allow-list on purpose.
