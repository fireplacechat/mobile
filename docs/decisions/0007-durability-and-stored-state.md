# 0007: Durable ratchet state and verified stored keys (review `crypto-evaluation-main-7dfe077`)

Date: 2026-10-03. Status: accepted. Responds to M-1 to M-10 of `docs/reviews/crypto-evaluation-main-7dfe077.md`.

## M-1 ratchet persistence failures could reuse a counter or desynchronize - fixed
- **Sending:** the advanced ratchets are now written **before** the message is published (write-ahead). A save failure aborts the send with nothing published. If publishing definitively fails (`permission-denied`, `invalid-argument`, ...) the stored ratchets are put back. If the outcome is ambiguous (network lost), the advanced state is kept: the worst case is a harmless gap in the counter, never a message encrypted twice at the same counter.
- **Receiving:** after a message authenticates, its whole outcome (history entry, advanced session, spent one-time prekey) is written as ONE journal record, then applied idempotently. The journal is replayed before any other message is processed, so a crash or storage failure at any point completes on the next run instead of leaving history written but the ratchet behind.
- Fault-injection tests cover every boundary: save fails before publish; publish denied; publish ambiguous; history written but session save fails; persistent failure then app restart; prekey store failure.

## M-2 one-time prekey erasure could be skipped - fixed
Erasure is part of the journal, so it is retried until it succeeds. `maintain` also forgets private one-time prekeys older than 30 days whose public document is gone (claimed by someone who never completed a session) and still removes published prekeys that have no private half.

## M-3 failed-chain budget counted cheap rejects - fixed
Structural rejections (counter or previous-chain length beyond the skip limit) happen before the budget is checked and never count; only attempts that reach X25519 / ML-KEM work do. Remaining, documented: an accepted contact can still make us ignore their own new-chain messages for up to a minute by sending invalid ones; messages are retried after about 65 seconds. Device cost is unmeasured.

## M-4 one-time prekeys are not individually signed - accepted
A server that substitutes a one-time prekey can only make that handshake fail (the signed prekey is an independent authenticated contribution, and the substituted bytes enter the transcript, so the session id/root differ). Signing every one-time prekey adds a ~3.3 KB ML-DSA signature each (about 66 KB per pool, plus signing time on every refill). Draining the pool (by anyone with an account) downgrades new sessions to the signed prekey alone, i.e. a forward-secrecy window equal to the signed-prekey rotation interval (7 days); this is in the threat model. Revisit if the pool becomes a target.

## M-5 stored keys were only length-checked - fixed
Public/private correspondence is verified on load: X25519 public vs seed, the ML-KEM public key vs the encapsulation key embedded in the decapsulation key (FIPS 203 layout), the identity's Ed25519 key vs its seed plus a fresh hybrid sign/verify probe (covers ML-DSA), the stored device bundle vs the keys and its certificate. Device keys, identity and prekey records are loaded strictly (types, exact lengths, ranges). Inconsistent device/identity records raise "recovery required" (never a silently minted new identity); inconsistent sessions and prekeys are dropped and replaced (new handshake / new prekeys).

## M-6 / M-7 / M-9 - unchanged, documented
Custom construction without an independent composition proof (external review still required); first-contact TOFU unless users verify (changing a pinned identity already clears "verified"); no demonstrated memory erasure or constant-time behaviour for the pure-Dart post-quantum code.

## M-8 label split across versions - addressed
All domain strings now live in `protocolLabels` (`session.dart`), with a test that pins the exact table. Some labels keep older numbers on purpose: renaming one changes every derived key, so it only happens in a release that also changes keys.

## M-10 link confirmation - tightened
Link requests are honoured for 15 minutes after the new device showed its QR code (single use was already enforced). The six-digit code remains a human comparison (SAS), not a long-term authenticator.
