# Architecture

Fireplace is a Flutter app for iOS and Android using Firebase. Its feature layout is being introduced in stages: one-to-one moves first, then separately reviewed extractions. This page describes the current tree and the remaining boundaries.

## Start here

1. `lib/main.dart` starts Firebase and runs the app.
2. `lib/src/app.dart` selects the first screen.
3. `lib/src/ui/chat_list_screen.dart` and `lib/src/ui/chat_screen.dart` contain the current chat screens.
4. `lib/src/services/chat_service.dart` handles sending, receive journaling, history and sync.
5. `lib/src/crypto/session.dart` implements the cryptographic session and stays whole.

## Folders

```text
lib/src/
├── view/<feature>/    screens and feature widgets
├── model/<feature>/   feature logic, state and Firebase access
├── widgets/           shared widgets
├── styles/            colours, spacing, typography and brand drawing
├── db/                local encrypted history and secret storage
├── utils/             reserved for small pure helpers
├── crypto/            protocol primitives and cryptographic sessions
├── app.dart           first-screen routing
├── app/               providers awaiting extraction
├── services/          chat service awaiting extraction
└── ui/                composite screens and helpers awaiting extraction
```

`chat_list` is a separate feature from `chat`. Other feature boundaries include account, auth, devices, recovery, safety, search, settings, notifications, push and keys. Not every target folder exists yet.

## Dependencies

`scripts/check_layout.py` checks imports in the migrated layers:

- `view` can use model, database, crypto, styles, widgets and helpers; Firebase access belongs in the model.
- `model` can use database, crypto and helpers, without importing UI widgets or styles.
- Shared `widgets` use styles and helpers, without importing feature models or database code.
- `styles`, `utils`, `db` and `crypto` must not import higher layers.
- A view feature may import another feature's public file, but not its nested implementation files.

All app imports use `package:fireplace/...`. Top-level startup wiring can assemble the layers. The checker warns about files over 500 lines; this is informational while composites are being extracted. Legacy `app/`, `services/` and `ui/` files remain outside the layer rules during this first stage; imports involving those files are not evidence that the final boundaries are complete.

## The path of one message

1. `ui/chat_screen.dart` checks message length using `model/chat/message_limits.dart` and calls the chat service.
2. `services/chat_service.dart` asks `crypto/session.dart` to encrypt per device and publishes ciphertext.
3. An uncertain send is kept for the user's explicit confirmation or retry; it never silently resends.
4. The receiving chat service decrypts, journals and saves the message in `db/encrypted_message_store.dart`.
5. Screens read local history. The server receives ciphertext for messaging; optional reports can contain plaintext selected by the reporter.

Firestore stores public keys, ciphertext and account/chat metadata. Secure storage holds device keys and ratchet state. Encrypted local files hold history and preferences. Providers assemble these resources and manage their lifecycle.

## Remaining extractions

Shared presentation widgets now live in `widgets/`; the message bubble and day separator live in `view/chat/widgets/`. `ui/presentation.dart` retains their compatibility exports.

Recovery-key, device-linking and password-change flows now live in `view/recovery/`, `view/devices/` and `view/account/`; `ui/recovery_screens.dart` retains their compatibility exports.

Separate PRs will extract composite screens; split unread, visibility and search helpers; then extract chat directory, sender, receive journal, receiver and session storage behind the existing chat-service facade. Chat-screen controllers and providers follow after those boundaries are reviewed. Each extraction preserves behavior and public APIs. Crypto session code stays whole; only its imports change in the first move.

`test/` mirrors the target layers. Some tests already use their target location while their implementation still lives in a legacy composite. Fixture helpers stay in `test/support/`; protocol vectors in `test/vectors/` stay unchanged. Earlier decision records retain paths from when they were written; `scripts/lib-map.csv` and `scripts/test-map.csv` record the one-to-one path changes.

## Verification

```sh
python3 scripts/check_layout.py .
flutter analyze
dart format --output=none --set-exit-if-changed lib test scripts
TZ=UTC flutter test --concurrency=1
TZ=UTC flutter test scripts/render/render_screens_test.dart
```

For a move or extraction, preview PNG hashes must match the parent revision. Tests change only in imports and file locations.

For new work, put screens in `view/<feature>/`, logic in `model/<feature>/`, and local storage in `db/`. Reuse shared widgets. Cryptographic, wire-format or authentication changes require a decision record and tests.

See [CONTRIBUTING.md](../.github/CONTRIBUTING.md) and the [coding style](development/coding-style.md).
