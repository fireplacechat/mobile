# 0008: Randomised protocol tests, and cheap refusal of replays and reflections

Date: 2026-10-03. Status: accepted. Follows decision 0007 (no external review is available, so adversarial testing has to carry more of the weight).

## Tests added
`test/crypto/protocol_property_test.dart` drives two parties through seeded random schedules of sends, reordering, drops, duplicate deliveries, replays, reflection (a message handed back to its own sender), wrong chat id, tampering with every header and ciphertext field, and app restarts (session saved and reloaded). After every step it checks:
1. a delivered message decrypts to exactly what was sent;
2. a message is accepted at most once;
3. nothing decrypts under the wrong session, chat, direction or peer;
4. any tampering is refused and refusing it leaves the session usable;
5. every message that was not dropped is eventually readable, whatever the order;
6. nonces and (ratchet key, counter) pairs are never reused.
Also covered: the responder can start from any of the first-flight messages in any order and agrees on the session id; a handshake cannot be accepted by a different device or for a different peer.

CI runs 10 runs of 90 steps. For a deeper run, or to reproduce a failure:
`flutter test test/crypto/protocol_property_test.dart --dart-define=PROTOCOL_RUNS=250 --dart-define=PROTOCOL_STEPS=150`
`... --dart-define=PROTOCOL_SEED=<seed>`
250 runs of 150 steps pass.

## Do the tests catch real breakage? (mutation check)
Each of these deliberate breakages of `session.dart` was detected, then reverted: committing state before authenticating; not consuming a skipped key; not binding the chat id into the encryption; not advancing the message counter; disabling the cheap replay check (caught by a dedicated regression test as well).

## What the tests found
Replaying an old message, reflecting a message to its sender, or using the wrong chat id each reached the expensive new-chain path (X25519 + ML-KEM decapsulation) before failing, and each failure counted against the 8-per-minute budget. A server replaying eight old messages could therefore make a session refuse honest new-chain messages for about a minute, and could cost us repeated post-quantum work.

## Fix
The session now remembers up to 64 ratchet public keys that can never legitimately start a new chain from the peer: the peer's retired keys and our own current and past keys (`retired`, stored with the session state, strictly validated on load, optional for older state). An honest peer's new chain always carries a fresh key, so a "new chain" under one of these is a replay or a reflection and is refused before any expensive work and without touching the budget. Wire format and protocol version are unchanged. Remaining: invalid messages that look like genuine new chains (tampered headers) still cost work and still count; that is the bounded residual from decision 0007.
