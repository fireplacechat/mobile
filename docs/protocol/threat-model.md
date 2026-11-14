# Fireplace threat model

**Scope:** the one-to-one mobile client, checked against source on 2026-11-14. This is not an independent audit or a check of production configuration. Backend rules and operator tooling live in the private backend repository. See [architecture](../architecture.md), [decisions](../decisions/) and [account deletion](account-deletion.md).

## Assets and goals
- Message content and the keys that protect it; account identity keys; device keys; recovery material; session state; pinned contact identities.
- Local decrypted history (encrypted at rest by the app).
- Credentials and the ability to reach an account's conversations.
- Availability and cost of the shared Firebase project (Blaze plan: usage past the free allowances is billed, with no hard cap on Firestore).

Goals: Firebase and network observers cannot read message bodies; a participant can detect replacement of a contact's identity key; a stolen copy of a session heals after a round trip or two; strangers cannot flood or probe other users freely; people can block and delete.

## What is implemented
- **Accounts:** username + password on Firebase Auth via a synthetic address `<username>@users.fireplace.invalid`. No email/phone. Optional recovery key; device linking by QR + 6-digit code.
- **Identity:** each account has a hybrid Ed25519 + ML-DSA-65 identity. Each device has X25519 + ML-KEM-768 keys certified by that identity. A contact's identity is pinned on first use (TOFU); a change blocks sending until the user accepts it. Safety number / QR verification binds the pin.
- **Handshake (protocol v4):** PQXDH-style with signed and one-time prekeys; transcript commits to both identities and all public keys involved.
- **Ratchet:** hybrid double ratchet (X25519 + ML-KEM-768 on every direction change), per-message AES-256-GCM keys that are deleted after use. Forward secrecy for processed messages; post-compromise security after the compromised side answers with fresh keys.
- **Wire and state validation:** versions, lengths and types of messages and of stored session state are checked before use; failed decrypts never change state; repeated invalid new-chain messages are rate-limited per session. Session ids commit to the full handshake transcript (protocol v4).
- **Local storage:** history in an AES-256-GCM file with the key in Keychain/Keystore; keys/sessions in the platform secure store.
- **Server authorization:** the client relies on participant checks, message/device validation, request limits, blocking and suspension enforced by the backend. Rules and their emulator tests live in `fireplacechat/backend`, not this checkout.
- **Abuse handling:** block, ignore requests and report spam. Reports name the reporter and reported account, with no message text; private operator tools handle moderation. Local unblock waits for server acknowledgement ([0051](../decisions/0051-block-unblock-confirmation.md)).

## What leaks (metadata)
Firebase and anyone with database access see: account ids and usernames, display names, device ids and public keys, which accounts chat, who started a chat, who sent each message and when, approximate message length and the number of recipient devices (envelope sizes), request/accept state, and moderation records. They do not see message text. Direct username lookup is possible for any signed-in user (listing is denied). The block list is private but the rules consult it, so a blocked person's failed send is observable to them as an error. Network providers see IP addresses, times and traffic sizes.

With notifications on, APNs/FCM see push routing, timing and the payload metadata, including the sender's username when enabled. Message text is fetched as ciphertext and decrypted on the phone for previews; it is not sent as push plaintext. Local alerts and lock-screen previews can expose that decrypted text according to Fireplace and OS settings. See [notification previews](../decisions/0030-notification-previews.md).

The device holds decrypted history. Someone with an unlocked phone, screen capture or accessibility access, malware, a compromised OS, device backups exposing keys, or a memory dump can read content. Deleting data is logical, not secure erasure from flash, backups, screenshots or recipients' phones.

## Adversaries and limits
**Considered:** passive network observers; curious or compromised hosting; authenticated strangers (spam, probing, quota abuse); malicious chat participants (malformed traffic, harassment); an attacker who can edit public key records on the server; an attacker who copies a session state once.

**Mitigations and their limits:**
- *Key substitution by the server:* prekeys and device certificates are signed by the account identity; pinning + safety numbers expose swapped identities. A first-contact substitution is only caught if users compare safety numbers.
- *Spam / unsolicited contact / cost abuse:* invite-only sign-up, message requests, blocking, suspension and the send limits in [0028](../decisions/0028-send-window.md) reduce abuse. Read traffic can still drive costs; Firestore has no hard spending cap on Blaze. [App Check activation](../development/app-check.md) alone does not enforce attestation; enforcement is a server setting. Verify deployed rules, limits and console settings in the backend's release process.
- *A contact who sends invalid messages:* after 8 invalid new-chain messages (tampered headers or ciphertexts; replays and reflections are refused cheaply and do not count) in a minute the session ignores further new-chain messages from that contact for up to a minute (they are retried afterwards); this only affects the conversation with that contact. Draining someone's one-time prekeys (anyone with an account can claim them) downgrades new sessions to the signed prekey alone, a 7-day forward-secrecy window; a server substituting a one-time prekey can only make that handshake fail.
- *Compromised device:* not protected. After a one-time copy of session state, messages protected by the copied keys stay readable until the heal point.
- *Metadata:* not hidden.
- *Account takeover:* anyone with the password can sign in; they also need the local keys or the recovery key/linked device to read chats, but can create a new identity and get contacts' warnings. Weak or reused passwords are a risk. Authentication proves an account, not a real-world person.
- *Operator/Admin compromise:* Firebase Admin credentials (and the operator CLI key) can read all metadata, edit rules and public key records, and ban accounts. Keep them out of the repository and the client.
- *Dependencies:* app message crypto defaults to the pinned Rust core through `lib/fireplace_crypto.dart`; its dependency graph is in `packages/fireplace_native/rust/Cargo.lock`. The Dart `pqcrypto`/`cryptography` implementation remains for comparison, and local history encryption uses `cryptography`.

## Not supported
Calls, attachments, real-email recovery, old-history transfer to a new device, and disappearing-message timers. [Groups are specified](group-chats-v1.md) but not implemented. Delete-for-everyone controls exist; they cannot erase a recipient's screenshots, exports or other copies.

## Operational assumptions
Production TLS endpoints and backend authorization rules must match the intended policy. Keep Firebase admin credentials out of the client and repository; client configuration is public identification. Review rules and dependencies before release, maintain the [private reporting contact](../../.github/SECURITY.md) and moderation process, and keep store disclosures aligned with Firebase/SDK behavior.

## Verification

The suites cover distinct boundaries:

- `test/crypto/nist_vectors_test.dart` and `wycheproof_test.dart` check the Dart reference against standard and adversarial vectors.
- `native_vectors_test.dart`, `native_cross_keys_test.dart` and `native_cross_session_test.dart` check native output, interoperability and transferred session state.
- Protocol property tests and chat simulations exercise invalid inputs, restart and persistence/publish failures. See [setup](../development/setup.md) to run them.

These are regression and interoperability checks, not proof of complete protocol security, constant-time execution or secure memory erasure.

A send with an uncertain outcome is not automatically resent; the user can check
server confirmation and explicitly decide whether to send another copy.
