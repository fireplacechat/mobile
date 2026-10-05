# Development

Install the Flutter version pinned in `pubspec.yaml`, Java 21 and the Android SDK (or Xcode
on macOS for iOS). Android requires API 26 or newer. Then run:

```sh
flutter pub get
flutter analyze
dart format --output=none --set-exit-if-changed lib test scripts
TZ=UTC flutter test --concurrency=1
flutter build apk --debug
```

The unit/widget suite uses fictional fixtures and requires no production credentials. Render
screens with `TZ=UTC flutter test scripts/render/render_screens_test.dart --concurrency=1`.
The client Firebase configuration is public identification, not an administrator credential.
Never add service-account files, signing keys or real account data.

## Local backend and integration testing

Backend rules and operator tools are maintained in a separate private repository. Maintainers
with access can clone `fireplacechat/backend` beside this checkout and start Auth/Firestore
emulators there with `firebase emulators:start --only auth,firestore --project fireplace-chat-app`.
Do not run that command from the client repository, which has no backend rules/configuration.

Start an Android virtual device using `bash scripts/start_android_emulator.sh`; the default AVD
is `fireplace` (`FIREPLACE_AVD` overrides it). Then use:

```sh
flutter run -d emulator-5554 --dart-define=USE_EMULATOR=true
flutter test integration_test/e2e_test.dart -d emulator-5554 --dart-define=USE_EMULATOR=true
```

The Android emulator reaches host services at `10.0.2.2`; `EMULATOR_HOST` overrides it.
Use only emulator fixtures, never production accounts. Contributors without backend access
can run the unit, widget and protocol tests independently.

## Architecture and security

`lib/src/crypto/` contains protocol primitives and the hybrid ratchet; `model/` contains feature
logic and Firebase access, `db/` stores local data, and `view/` contains screens. See the
[architecture map](../architecture.md) for the staged layout and remaining composites. Chat bodies are encrypted
before upload. The service still sees account/device identifiers, participants, timestamps and
ciphertext sizes. Optional reports can contain plaintext selected by the reporter.

No completed independent audit is claimed. Read the [threat model](../protocol/threat-model.md),
[account deletion notes](../protocol/account-deletion.md) and [decisions](../decisions/).
See [contribution guidance](../../CONTRIBUTING.md) and [security reporting](../../SECURITY.md).
