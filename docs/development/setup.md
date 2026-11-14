# Development setup

## Tools

Use the Flutter version pinned in `pubspec.yaml`, Rust from
`packages/fireplace_native/rust/rust-toolchain.toml` (currently 1.98.1), Git,
Python 3 and Bash. On Windows, use Git Bash for the shell scripts and install the
MSVC C++ build tools for Rust host builds. Android builds need Java 17 (as in CI),
the Android SDK and the NDK selected by Flutter; iOS builds need Xcode on macOS.

The Rust host helper currently supports Linux and Windows. macOS contributors
can use the [iOS build/preview guidance](ios-previews.md); `scripts/check.sh`
cannot complete there while its host-build helper lacks macOS support.

## First check

From the repository root, in Bash:

```sh
flutter pub get
scripts/check.sh
```

This checks Dart formatting, analyzes the app, checks layer and packaging rules,
builds both Rust host libraries, and runs regular tests followed by isolated
timing tests. It needs no backend access or production credentials. The first
native build downloads the pinned `fireplace-crypto` crate and dependencies;
it does not use a sibling crypto checkout.

App crypto defaults to the Rust core through `lib/fireplace_crypto.dart`.
The Dart implementation remains a comparison reference. Android and iOS builds
package their native libraries through the in-repo plugin.

## Work on one change

```sh
# Static checks only; still run the full check before a PR.
scripts/check.sh quick

# Prepare native libraries before running a test directly.
bash scripts/build_crypto_host.sh
bash scripts/build_crypto_host.sh test-rng
TZ=UTC flutter test test/model/chat/chat_sync_coordinator_test.dart

# UI previews use fictional fixtures and write to build/renders/.
TZ=UTC flutter test scripts/render/render_screens_test.dart --name 'settings'
```

`build/fireplace_crypto/host/release/` holds the normal core;
`host-test-rng/release/` holds the separate comparison build. The test RNG is
never enabled in app builds. See the [render catalog](../../scripts/render/README.md)
for preview options and [CI](ci.md) for hosted checks. On Windows, if a Python
helper reports a text-decoding error, set `PYTHONUTF8=1` in the shell and retry.

## Run with a local backend

Maintainers with access to `fireplacechat/backend` start Auth and Firestore
emulators **from that repository**, which owns the rules and Firebase config:

```sh
firebase emulators:start --only auth,firestore --project fireplace-chat-app
```

Back in the mobile checkout, start an Android virtual device and run:

```sh
bash scripts/start_android_emulator.sh  # AVD fireplace; FIREPLACE_AVD overrides it
flutter run -d emulator-5554 --dart-define=USE_EMULATOR=true
flutter test integration_test/e2e_test.dart -d emulator-5554 --dart-define=USE_EMULATOR=true
```

Confirm the device ID with `flutter devices`. Connection settings are defined in
`lib/src/app/firebase_setup.dart`:

| Setting | Default | Override |
|---|---|---|
| Host | `10.0.2.2` (Android emulator to host) | `--dart-define=EMULATOR_HOST=<host>` |
| Auth port | `9099` | Fixed in the client |
| Firestore port | `8080` | `--dart-define=EMULATOR_FIRESTORE_PORT=<port>` |

If Firestore uses another port, pass that same port to both `flutter run` and the
integration test, for example `--dart-define=EMULATOR_FIRESTORE_PORT=8180`.
Use only fictional accounts. Without backend access, the unit, widget and
protocol suites still run. Firebase client configuration is public identification;
never add administrator credentials, signing keys or real conversations.

## Build and investigate

For a local Android debug build, use `flutter build apk --debug`. When updating
an emulator, install over the existing app with the same signing key; uninstalling
or clearing data removes its local keys and history.

See [Android builds](android-release.md), [iOS previews](ios-previews.md) and
[store releases](releasing.md) for platform and release steps. Start code changes
with the [architecture map](../architecture.md) and
[contribution rules](../../.github/CONTRIBUTING.md); security boundaries are in the
[threat model](../protocol/threat-model.md).
