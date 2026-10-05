# 0003: Hybrid double ratchet (Phase 7b)

Date: 2026-10-03. Status: accepted. Builds on 0002 (handshake v2). Protocol version bumped to 3.

## What
Signal's Double Ratchet with an ML-KEM-768 step added to every DH step.
- The responder's signed prekey (X25519 + ML-KEM) is its first ratchet key (the session keeps its own copy so the prekey store can retire the original).
- Whenever a party starts a new sending chain it generates a **fresh X25519 key and a fresh ML-KEM key**, does `DH(new, peer's newest X25519)`, encapsulates to the peer's newest KEM key, and mixes both into the root key: `(RK, CK) = HKDF(salt = RK, lp(DH, KEM secret))`.
- Message keys come from a per-chain HMAC hash ratchet and are deleted after use; out-of-order messages are handled with skipped-key storage per chain (`pn` = previous chain length), capped at 1000.
- Headers (`rx`, `rk`, `rc`, `pn`, `n`) are bound into the AEAD associated data.

## Properties (tested)
- Forward secrecy for processed messages (their keys no longer exist in state).
- Post-compromise security: after an attacker copies one side's session state, the session heals once that side has answered a new chain with key pairs generated after the copy (within about two round trips). Verified both for a stolen receiver state and a stolen sender state; verified the tests fail if the ratchet mixes in no secret.
- Secure against classical and quantum attackers as long as either X25519 or ML-KEM-768 holds (both are mixed in).
- A failed or forged decrypt never changes state (everything runs on a clone and commits after authentication).

## Costs / trade-offs
- Every message carries the sender's current ratchet public keys and a KEM ciphertext (about 3.2 KB per envelope in base64) so any message of a chain lets the receiver ratchet; there is no ack protocol. A one-sided burst repeats the same header. Firestore document limits are far above this; mobile bandwidth is acceptable for chat. Possible later optimisation: omit `rk`/`rc` after the peer has demonstrably advanced.
- Session state grows to roughly 8 KB (holds an ML-KEM secret key per side).
- ML-KEM key generation + encapsulation (pure Dart) run on each change of direction.
- Not covered: an attacker who stays resident on the device; metadata.
