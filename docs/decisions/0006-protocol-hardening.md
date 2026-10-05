# 0006: Protocol hardening after the independent code review (protocol v4)

Date: 2026-10-03. Status: accepted. Responds to `docs/reviews/protocol-code-review-2026-10.md` (F-1 to F-6).

## F-1 session id did not commit to the whole handshake - fixed
The session id is now the first 128 bits of SHA-256 over the *same canonical transcript* the root key is derived from (participants, identities, device keys, signed/one-time prekey ids and public keys, ephemeral key, every KEM ciphertext), url-safe base64, 22 characters. Two handshakes that derive different roots can no longer share an id. The id is also bound into every message's AAD. Protocol version 4; stored v3 sessions are discarded and replaced by a fresh handshake. Tests mutate each handshake field and attribute the same bytes to a different initiator.

## F-2 a rejected one-time-prekey handshake could strand the sender - fixed (three layers)
1. **Atomic claim.** Starting a session now claims a one-time prekey with a Firestore transaction (read + delete). Rules let any signed-up account delete a *one-time* prekey (never a signed one) for exactly this. Verified against the real emulator: with two simultaneous claimers exactly one wins; the other falls back to the signed prekey. The "two initiators share one prekey" collision, and stale published prekeys after consumption, can no longer happen.
2. **Orphan repair.** If an account has more published one-time prekeys than private halves (device state lost or restored), `maintain` deletes the orphans and refills the pool; a failing handshake triggers this immediately.
3. **Stale-session replacement.** If a session we started has never been answered for 24 hours, the next send starts a fresh handshake as well (old sessions stay so late replies still decrypt; unanswered ones older than 30 days are dropped). The receiver always shows a visible "Encryption key no longer available" placeholder. Sessions the peer has answered are never replaced. Sending prefers an answered session (smallest id), otherwise the newest.
Not done: an authenticated NACK. It would need a second protocol message type and a reset-authority design; with 1-3 the remaining failure window is bounded to at most a day.

## F-3 identity-change warning not surfaced - fixed
`ChatService` exposes the pending alerts (peer -> new identity key) as a stream. The chat screen shows a banner with a review dialog (previous and new fingerprint, "Keep on hold" / "Trust new key"); the chat list marks the contact. Nothing is trusted automatically; trusting re-processes the held messages. Sending to a contact whose key changed raises the same alert and sends nothing.

## F-4 persisted state was not validated - fixed
`Session.fromJson` / `_State.fromJson` check every field (types, exact key lengths, counter ranges, skipped-key count and shape, consistency between sending/receiving fields, role vs handshake). `tryFromJson` returns null for anything invalid and the service drops that session and starts a fresh handshake. Mutation and random-corruption tests.

## F-5 expensive work before rejection - mitigated
After 8 failed attempts that needed new-chain work (X25519 + ML-KEM decapsulation) within a minute, a session refuses further new-chain attempts immediately (`SessionRateLimited`); the service retries those messages later instead of discarding them. Ordinary same-chain traffic is unaffected. Forged messages never change state. Worst-case cost on a real iPhone is still unmeasured.

## F-6 no independent composition analysis - open
Unchanged: an external cryptographic review is required before security claims or sensitive use.
