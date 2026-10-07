# Architecture

Fireplace is a Flutter app for iOS and Android using Firebase. Its feature layout is being introduced in stages: one-to-one moves first, then separately reviewed extractions. This page describes the current tree and the remaining boundaries.

## Start here

1. `lib/main.dart` starts Firebase and runs the app.
2. `lib/src/app.dart` selects the first screen.
3. `lib/src/view/chat_list/chat_list_screen.dart` lists conversations; `lib/src/view/chat/chat_screen.dart` contains the chat screen, with sending and contact state machines in `lib/src/model/chat/send_controller.dart` and `contact_controller.dart`.
4. `lib/src/model/chat/chat_service.dart` is the public facade; it wires the sender, receiver and shared state holders in `lib/src/model/chat/`.
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
└── app/               provider wiring and session composition
```

`chat_list` is a separate feature from `chat`. Other feature boundaries include account, auth, devices, recovery, safety, search, settings, notifications, push and keys. Not every target folder exists yet.

## Dependencies

`scripts/check_layout.py` checks imports in the migrated layers:

- `view` can use model, database, crypto, styles, widgets and helpers; Firebase access belongs in the model.
- `model` can use database, crypto and helpers, without importing UI widgets or styles.
- Shared `widgets` use styles and helpers, without importing feature models or database code.
- `styles`, `utils`, `db` and `crypto` must not import higher layers.
- A view feature may import another feature's public file, but not its nested implementation files.

All app imports use `package:fireplace/...`. Top-level startup wiring can assemble the layers. The checker warns about files over 500 lines. Top-level app wiring remains outside the feature-layer rules.

## The path of one message

1. `view/chat/chat_screen.dart` delegates sending to `model/chat/send_controller.dart`, which checks message length using `model/chat/message_limits.dart` and calls the chat service.
2. `model/chat/chat_service.dart` forwards to `model/chat/message_sender.dart`, which asks `crypto/session.dart` to encrypt per device and publishes ciphertext.
3. An uncertain send is kept for the user's explicit confirmation or retry; it never silently resends.
4. `model/chat/message_receiver.dart` decrypts, journals through `model/chat/receive_journal.dart`, and saves the message in `db/encrypted_message_store.dart`.
5. Screens read local history. The server receives ciphertext for messaging; optional reports can contain plaintext selected by the reporter.

Firestore stores public keys, ciphertext and account/chat metadata. Secure storage holds device keys and ratchet state. Encrypted local files hold history and preferences. Providers assemble these resources and manage their lifecycle.

## Session lifecycle

`app/providers.dart` keeps the ordered startup sequence and Riverpod dependencies. It delegates cancellation and reverse-order cleanup to `model/common/session_scope.dart`. `SessionScope` owns the cleanup future and reads mounted state at call time; disposal during initialization leaves cleanup to the startup sequence's `finally` block.

`model/chat/chat_sync_coordinator.dart` owns active background-sync subscriptions and the latest chat list. Chat-list and blocked-set events trigger reconciliation. It writes the local unread baseline before starting sync and re-checks eligibility after that I/O. The provider registers its cleanup in the original order, before registering the two event subscriptions. `AppSession` and the other providers retain their public interfaces.

## Remaining extractions

Shared presentation widgets now live in `widgets/`; the message bubble and day separator live in `view/chat/widgets/`.

Recovery-key, device-linking and password-change flows now live in `view/recovery/`, `view/devices/` and `view/account/`;

Composite account, device, safety, settings and chat-list screens now live in their feature folders. Chat activity helpers and message formatting live in `model/chat/`. Chat directory, session storage, send recovery, receive journaling, sender and receiver are behind the existing chat-service facade.

`ChatService` creates one mutex and passes the same instance to the sender and receiver. It also owns the shared `IdentityAlerts`, `WorkTracker` and `DeferredQueue` holders. Its `close()` marks work closed, stops the retry timer, cancels syncs and drains receive work, waits for the mutex, clears deferred and unfinished entries, then closes alerts. The public constructor, methods and test hooks remain compatible. `ChatTuning` holds the tuning values; the facade forwards the existing static API.

The chat screen delegates send/recovery state to `SendController` and contact-action/security-review state to `ContactController`. Controllers receive getters and callbacks from the screen; dialogs and snack bars remain in the view layer, and draft editing stays in the screen. Controller notifications replace the original `setState` wrappers; pending-memory mutations during `build()` stay silent.

`TimelineScroll` owns scrolling and the silent anchor cache; `RouteVisibility` owns route and lifecycle registration. `messageMenuActions` builds the existing message actions through view-layer callbacks. The screen keeps its draft, reveal-all state, message-provider listener and build-time frame callbacks. The screen now composes `ChatComposer`, `ChatSafetyNotices`, `SearchLocationNotice`, the app-bar parts, `ChatTimeline` and the unavailable/privacy guard screens in `view/chat/`. `UiAppBar` construction stays in the State so its height uses the original context. The State also reads the keyboard inset above `Scaffold` and passes it into composer and notice layout. Each extraction preserves behavior and public APIs. Crypto session code stays whole; only its imports change in the first move.

`test/` mirrors the target layers. Some tests already use their target location while their implementation still lives in a legacy composite. Fixture helpers stay in `test/support/`; protocol vectors in `test/vectors/` stay unchanged. Earlier decision records retain paths from when they were written..

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
