# 0002: Handshake v2 (signed + one-time prekeys), wire validation

Date: 2026-10-03. Status: accepted. Supersedes the handshake in 0001's glue code.

## Why
Review findings C1 (transcript narrower than "all public keys"), C3 (no forward secrecy), C6 (no wire validation) and S-series items. v1 was development-only; no production sessions exist.

## Protocol
PQXDH-style. Each device publishes (Firestore `users/{uid}/devices/{id}/prekeys/{pid}`):
- one **signed prekey** (X25519 + ML-KEM-768, signed by the account identity: Ed25519 + ML-DSA-65), rotated every 7 days; the previous private half is kept 14 days so in-flight handshakes still work, then deleted;
- a pool of up to 20 **one-time prekeys** (X25519 + ML-KEM-768), each deleted (privately and on the server) once a session was established with it.

Initiator: `SK = HKDF(lp(DH(IK_a,SPK_b), DH(EK_a,IK_b), DH(EK_a,SPK_b), DH(EK_a,OPK_b)?, KEM(SPK_b), KEM(OPK_b)?), transcript)`.
The transcript commits to: protocol label, both account identities, both devices' ids and static keys (incl. initiator's KEM key), the signed/one-time prekey ids **and public keys**, the ephemeral key and all KEM ciphertexts. Session id and AAD domain strings are `fireplace/v2/...`.

## Properties
- Forward secrecy against later compromise of long-term device keys, once the used prekey privates are deleted. Post-quantum for the KEM parts, assuming ML-KEM holds.
- Server cannot forge prekeys (signature check against the pinned identity); it can only withhold or reorder them.
- One-time prekeys are claimed atomically with a Firestore transaction (see decision 0006), so two initiators never share one. Pool exhaustion falls back to the signed prekey only (weaker FS window = rotation interval).
- NOT provided: post-compromise security (needs a DH/KEM ratchet in the message flow; planned as Phase 7b).

## Wire validation
`Envelope.fromJson` and `HandshakeInit.fromJson` validate version, types, counter range, id lengths and exact byte lengths of nonce/mac/ek/KEM ciphertexts, and cap ciphertext at 64 KiB, before any crypto. Unknown versions are shown as "Sent with an incompatible app version." Stored sessions without `pv: 2` are discarded and replaced by a new handshake.

## Cost
A first message to a device reads its signed prekeys and up to 10 one-time prekeys (about 11-12 Firestore reads) and deletes one on the receiver. `maintain` runs on app start and costs one aggregate count query when nothing is due.
