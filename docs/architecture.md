# Architecture

Fireplace is a Flutter client for iOS and Android. Firebase holds account data,
public keys and message ciphertext. The phone encrypts messages and keeps local
history; the backend rules and operator tools live in a separate private repository.

## Find the code

| Start with | Responsibility |
|---|---|
| [main.dart](../lib/main.dart), [Firebase setup](../lib/src/app/firebase_setup.dart) | Initialize Firebase, emulator connections and background push entry points |
| [Routing](../lib/src/app.dart), [providers](../lib/src/app/providers.dart) | Route the app and assemble resources for the signed-in account |
| [Chat list](../lib/src/view/chat_list/), [chat screen](../lib/src/view/chat/chat_screen.dart) | Conversation list, timeline, composer and message actions |
| [ChatService](../lib/src/model/chat/chat_service.dart) | Account/device chat facade; wires sending, receiving and recovery |
| [SendController](../lib/src/model/chat/send_controller.dart), [ContactController](../lib/src/model/chat/contact_controller.dart) | Send/recovery and contact-action state for the chat screen |
| [Notifications](../lib/src/model/notifications/), [push](../lib/src/model/push/) | Local unread/arrival state, notification preferences and push handling |
| [Database](../lib/src/db/) | Encrypted history, secret storage and the account lock |
| [Crypto API](../lib/src/crypto/backend.dart) | Rust by default, with the Dart reference retained for comparison |
| [Styles](../lib/src/styles/), [widgets](../lib/src/widgets/) | Design tokens and shared presentation widgets |

The app imports crypto through `package:fireplace/fireplace_crypto.dart`.
`lib/src/crypto/session.dart` is the Dart reference ratchet; the default implementation
comes from the [pinned Rust core](../packages/fireplace_native/rust/Cargo.toml).
See [setup](development/setup.md) for the native build requirements.

## Layers

- `view/<feature>` owns screens and interaction; Firebase access belongs in `model/<feature>`.
- `model` owns feature logic and may use `db` and `crypto`, without importing UI widgets or styles.
- Shared `widgets` may use styles and helpers, without importing feature models or storage.
- `styles`, `utils`, `db` and `crypto` must not import higher layers. `utils/` is reserved for pure helpers and is currently unused.
- Views may use another feature's public file, but not its nested implementation files. Top-level app wiring assembles the layers.

Use `package:fireplace/...` imports. `scripts/check_layout.py` enforces these
boundaries, rejects retired source directories and warns about files over 500 lines.
`test/` mirrors the source layers; fixtures live in `test/support/`.

## The path of one message

1. `SendController` checks input and calls `ChatService`. `MessageSender` holds
   the account lock and finishes any interrupted receive journal first.
2. `SendMode` checks request/acceptance rules. `DeviceCache` supplies recipient
   devices; `message_payload.dart` encodes the content, and
   `envelope_encryption.dart` encrypts separately for each device.
3. `SessionStore.saveAhead` persists advanced ratchets **before** publication.
   A definite refusal restores prior state. An ambiguous outcome keeps the
   advanced state and an unconfirmed message; it never automatically resends.
4. `MessageReceiver` processes ciphertext under the same lock. After authentication,
   `ReceiveJournal` records the history, session and spent-prekey effects before
   applying them. An interrupted journal is replayed before further send/receive work.
5. Screens, search and previews read local history. Receive cursors do not advance
   past unfinished messages. Pending local Firestore writes cannot confirm a send;
   committed additions and modifications can resolve an unconfirmed entry.

| Helper in `model/chat/` | Owns |
|---|---|
| [ChatDirectory](../lib/src/model/chat/chat_directory.dart) | Firestore chat metadata, requests and username lookup |
| [ChatSummary](../lib/src/model/chat/chat_summary.dart) | Chat metadata for the list and request eligibility; no message text |
| [SessionStore](../lib/src/model/chat/session_store.dart) | Ratchet snapshots in `SecretStore`, scoped to this device and each peer device |
| [SendRecovery](../lib/src/model/chat/send_recovery.dart) | Server confirmation checks, local-history repair and explicit resend callbacks |
| [ReceiveJournal](../lib/src/model/chat/receive_journal.dart) | Replay of partly applied authenticated receives |
| [ChatPreview](../lib/src/model/chat/chat_preview.dart) | Latest local message or pending send shown in the conversation list |

`EncryptedFileMessageStore` stores AES-256-GCM snapshots and, for longer chats,
an encrypted `HistoryLog`. Keys and ratchet state use `SecretStore`. The account
`SharedLock` serializes app/background access and invalidates stale caches.
`AsyncMutex` in `lib/src/model/common/async_mutex.dart` queues work within one isolate;
the prekey service uses it. `SharedLock` owns account-wide coordination.

## Account lifecycle

`appSessionProvider` creates account resources in order. `SessionScope` handles
cancellation and closes resources in reverse order, including when sign-out
interrupts startup.

`ChatSyncCoordinator` reconciles receive subscriptions when chats or blocks
change. It excludes incoming requests, blocked peers and hidden chats, and seeds
the local unread baseline before starting sync. Eligibility is checked again
after that I/O. An unblock takes effect locally after server acknowledgement
([0051](decisions/0051-block-unblock-confirmation.md)).

`ChatService.close()` stops scheduling receives and retries, cancels subscriptions,
drains work, waits for the account lock, and closes caches and event streams
before the session's stores close.

## Planned groups

The app currently implements 1:1 chats. MLS groups are specified but not built:
[owner decisions](decisions/0050-group-chats.md),
[implementation specification](protocol/group-chats-v1.md), and
[design rationale](protocol/group-chat-design.md).

## Verification and changes

Run `scripts/check.sh` before a pull request. For UI changes, use the
[render catalog](../scripts/render/README.md); a move or extraction should produce
identical preview PNGs. See [setup](development/setup.md) for targeted commands.

Put screens in `view/<feature>`, logic in `model/<feature>`, and local storage in
`db/`. Protocol, key-handling, authentication and rules changes need a decision
record and tests. Earlier decision records may retain paths from when they were
written. Contribution rules: [AGENTS.md](../AGENTS.md) and
[coding style](development/coding-style.md).
