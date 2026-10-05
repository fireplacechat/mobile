# 0009: Service-level random simulation, and the lost-message bugs it found

Date: 2026-10-04. Status: accepted. Follows 0008 (session-layer property tests). The session layer was now well covered; what was not covered was everything around it: Firestore sync and catch-up, the send write-ahead, the receive journal, deferral/retry, several devices per account, and crashes.

## What was added
`test/services/chat_simulation_test.dart` builds two accounts (each can gain a second, linked device mid-run) over the real `ChatService`, `PreKeyService` and `KeyService` with a fake Firestore, then executes a seeded random schedule of:
- sends from any device, including both accounts sending at the same instant (first-message glare);
- publish failures: refused for certain, lost before reaching the server, and *committed but reported as lost*;
- storage failures while saving the write-ahead ratchets, the receive journal, the sync cursor, or the message history;
- devices going offline and coming back (catch-up from the persisted cursor);
- app restarts, including **killing the app part-way through a send**; the old instance's storage handles stop working, as after a real crash;
- losing the sync cursor entirely; refreshing prekeys; linking a new device; session replacement forced at every send (the 24-hour rule set to zero).

After the schedule every fault is cleared and the system must converge:
1. every message that reached the server is readable, exactly once, on every device that existed when it was sent (the other account's devices and the sender's own other devices);
2. no device shows a message that was never published, or one whose send definitely failed;
3. the only unreadable entries are "sent before this device was added", and only on devices linked later;
4. the conversation is not stuck: every device can then send and everyone receives.

Whether a message "exists" is decided by asking the server, not by what the app reported, because a failure can arrive after the message was already published.

CI runs 6 runs of 36 steps (about 30 s). For a longer search, or to replay a failure:
`flutter test test/services/chat_simulation_test.dart --dart-define=SIM_RUNS=60 --dart-define=SIM_STEPS=70`
`... --dart-define=SIM_SEED=<seed>`
Background sync is asynchronous, so a seed reproduces the sequence of actions and usually, not always, the same outcome.

## Bugs found and fixed
All three are in `chat_service.dart`; each has (or is covered by) a regression test in `test/services/durability_test.dart`.

1. **A counter could be reused after a storage failure (message permanently unreadable).** A received message's journal holds a snapshot of the session. If it could not be fully applied, it stayed pending. A later *send* advanced the session, and replaying the journal afterwards rolled the session back, so the next send reused a counter and the receiver stored "could not decrypt (replayed or unknown counter)". `sendText` now replays pending journals first, inside the same lock, exactly as receiving already did. If storage is still failing the send fails safely.
2. **A failed message could be skipped forever after a restart.** The sync cursor only refused to advance past a failure within the same batch of messages. If message 1 failed and message 2 arrived in a later batch and succeeded, the cursor passed message 1; the in-memory retry list is lost on restart, so message 1 was never fetched again. The cursor is now held back by the oldest message that is not finished.
3. **The same, with batches overlapping.** Sync callbacks can overlap, so a newer message could finish while an older one was still being processed (not yet marked failed), moving the cursor past it. Every message in a batch is now registered as unfinished, synchronously, before any is processed, and removed only when it succeeds.

Also: a failed cursor write used to throw out of the stream listener as an unhandled error; the cursor is only an optimisation (stored messages are skipped on re-read), so the failure is now ignored.

## Known and accepted
- If the *local* history write fails after a message was already published, the sender sees an error although the message was delivered, and its own device lacks its copy. A resend would create a duplicate. This is the same situation as a network drop at the wrong moment; it needs a UI story (show "not confirmed"), not a protocol change.
- Fake Firestore does not isolate transactions, so concurrent claims of the same one-time prekey are covered by the emulator tests (`firebase/tests`), not here.

## Not covered by this simulation
Identity-change warnings, blocking and message requests, account deletion, recovery and device linking (each has dedicated tests), and anything about real network or Firestore behaviour (rules are tested against the emulator).
