# Fireplace threat model

**Status:** implementation-based, for the current one-to-one app on `main` (2026-10-03). Early software; not a certification or independent audit. Recheck whenever code, SDKs, Firebase configuration or behavior change. Design details: `docs/decisions/0001`-`0004`, `docs/protocol/account-deletion.md`, `tools/operator/README.md`.

## Assets and goals
- Message content and the keys that protect it; account identity keys; device keys; recovery material; session state; pinned contact identities.
- Local decrypted history (encrypted at rest by the app).
- Credentials and the ability to reach an account's conversations.
- Availability and cost of the shared Firebase project (Blaze plan: usage past the free allowances is billed, with no hard cap on Firestore).

Goals: Firebase and network observers cannot read message bodies; a participant can detect replacement of a contact's identity key; a stolen copy of a session heals after a round trip or two; strangers cannot flood or probe other users freely; people can block and delete.

## What is implemented
- **Accounts:** username + password on Firebase Auth via a synthetic address `<username>@users.fireplace.invalid`. No email/phone. Optional recovery key; device linking by QR + 6-digit code.
- **Identity:** each account has a hybrid Ed25519 + ML-DSA-65 identity. Each device has X25519 + ML-KEM-768 keys certified by that identity. A contact's identity is pinned on first use (TOFU); a change blocks sending until the user accepts it. Safety number / QR verification binds the pin.
- **Handshake (protocol v3):** PQXDH-style with signed and one-time prekeys; transcript commits to both identities and all public keys involved.
- **Ratchet:** hybrid double ratchet (X25519 + ML-KEM-768 on every direction change), per-message AES-256-GCM keys that are deleted after use. Forward secrecy for processed messages; post-compromise security after the compromised side answers with fresh keys.
- **Wire and state validation:** versions, lengths and types of messages and of stored session state are checked before use; failed decrypts never change state; repeated invalid new-chain messages are rate-limited per session. Session ids commit to the full handshake transcript (protocol v4).
- **Local storage:** history in an AES-256-GCM file with the key in Keychain/Keystore; keys/sessions in the platform secure store.
- **Server rules (Firestore):** participants only; message and device checks; message requests (3-message cap before acceptance); blocking; banned tokens refused; sender can delete own messages; account data deletable by its owner. Reports are not stored. Tested against the emulator (see `firebase/tests/`).
- **Abuse handling:** block, ignore requests, and an operator CLI (`tools/operator`) that can suspend accounts. Message text is not stored for review.

## What leaks (metadata)
Firebase and anyone with database access see: account ids and usernames, display names, device ids and public keys, which accounts chat, who started a chat, who sent each message and when, approximate message length and the number of recipient devices (envelope sizes), request/accept state, and moderation records. They do not see message text. Direct username lookup is possible for any signed-in user (listing is denied). The block list is private but the rules consult it, so a blocked person's failed send is observable to them as an error. Network providers see IP addresses, times and traffic sizes.

With notifications on, Apple (APNs) and Google (FCM) also see, for each alert: that the device received one, when, and the sender's username as the title (unless "Show sender's name" is off on that device). They never see message text; the server does not have it. Alerts show on the lock screen according to the phone's own notification-preview setting.

The device holds decrypted history. Someone with an unlocked phone, screen capture or accessibility access, malware, a compromised OS, device backups exposing keys, or a memory dump can read content. Deleting data is logical, not secure erasure from flash, backups, screenshots or recipients' phones.

## Adversaries and limits
**Considered:** passive network observers; curious or compromised hosting; authenticated strangers (spam, probing, quota abuse); malicious chat participants (malformed traffic, harassment); an attacker who can edit public key records on the server; an attacker who copies a session state once.

**Mitigations and their limits:**
- *Key substitution by the server:* prekeys and device certificates are signed by the account identity; pinning + safety numbers expose swapped identities. A first-contact substitution is only caught if users compare safety numbers.
- *Spam / unsolicited contact / cost abuse:* invite-only sign-up (accounts without an invite are inert), message requests, blocking, suspension, and enforced limits of 20 messages per 10-second window and 2,000 a day per account (decision 0028). An invitee can still send 2,000 messages a day until banned (an app still on the older send-clock form has no daily cap until that form is removed), reads are not rate limited, and there is no App Check or device attestation yet, so a determined invitee can still drive up usage. On the Blaze plan that is a bill rather than an outage; budget alerts give warning and the push function's instance cap bounds its own cost, but nothing caps Firestore spending (see `docs/push/COSTS.md` in the backend repository).
- *A contact who sends invalid messages:* after 8 invalid new-chain messages (tampered headers or ciphertexts; replays and reflections are refused cheaply and do not count) in a minute the session ignores further new-chain messages from that contact for up to a minute (they are retried afterwards); this only affects the conversation with that contact. Draining someone's one-time prekeys (anyone with an account can claim them) downgrades new sessions to the signed prekey alone, a 7-day forward-secrecy window; a server substituting a one-time prekey can only make that handshake fail.
- *Compromised device:* not protected. After a one-time copy of session state, messages protected by the copied keys stay readable until the heal point.
- *Metadata:* not hidden.
- *Account takeover:* anyone with the password can sign in; they also need the local keys or the recovery key/linked device to read chats, but can create a new identity and get contacts' warnings. Weak or reused passwords are a risk. Authentication proves an account, not a real-world person.
- *Operator/Admin compromise:* Firebase Admin credentials (and the operator CLI key) can read all metadata, edit rules and public key records, and ban accounts. Keep them out of the repository and the client.
- *Dependencies:* ML-KEM/ML-DSA come from the pure-Dart `pqcrypto` package (not FIPS-validated; not hardened against side channels). The classical AES-GCM, X25519, Ed25519 and HKDF primitives from `cryptography` also use Dart implementations on Android/iOS with the current provider configuration; browser builds can use Web Crypto with Dart fallbacks. No constant-time or side-channel-hardening guarantee is claimed for these implementations. The protocol glue is project code that has had review by tools and tests but **no external cryptographic audit**.

## Not supported
Group chats, calls, attachments, real-email recovery, multi-device history sync (a new device starts with an empty history), message deletion for everyone, disappearing messages.

## Operational assumptions
Production TLS endpoints and the deployed rules from this repository; Firebase admin credentials kept out of the client and repo; Firebase client configuration treated as public identifiers; rule and dependency changes reviewed and tested before release; a published security contact ([`SECURITY.md`](../../.github/SECURITY.md)) and operator process for reports; store privacy disclosures that include Firebase/SDK practices.

Historical internal review reports are maintained privately; this document does not claim an external audit.


## Evidence for the primitives (no external audit)
No completed independent cryptographic audit is claimed. Included test evidence:
- **Standards conformance.** `test/crypto/nist_vectors_test.dart` runs the pure-Dart ML-KEM-768 and ML-DSA-65 against NIST's official ACVP vectors (key generation, encapsulation, decapsulation including implicit rejection, key validity checks, signing, and verification of valid and invalid signatures). `test/crypto/wycheproof_test.dart` runs X25519, Ed25519, AES-256-GCM and HKDF-SHA256 against Google's Wycheproof vectors, which include malformed and tampered inputs. All pass.
- **What this does and does not show.** It shows the *building blocks* compute what the standards specify and reject known-bad inputs. It does **not** show that the handshake, ratchet or key-management design is secure, that secrets are erased from memory, or that the pure-Dart code is constant-time. Those rest on design review by ChatGPT/Claude, fault-injection and property tests, and public scrutiny of the open-source code.
- **Honest wording for users:** not independently audited; not intended for life-or-death secrets.

### Failure behaviour
Seeded simulations exercise crashes, restart, offline delivery and persistence/publish failures.
They are regression evidence, not a universal delivery guarantee. A send with an uncertain outcome
is not automatically resent; the user can inspect history and choose what to do next.
