# 0027: Faster sending, receiving, reactions and start-up

Status: requested by the owner, 2026-11-12. Review before merge. No change to
wire formats, message payloads, the ratchet, Firestore rules or the backend.
Local storage and how key material is read change; both are described here.

Signal's iOS app and server were read first for comparison: its apps send to
the devices they already know and let the server answer 409/410 with missing
or stale devices; reactions are recorded locally before they are sent and
reverted if the send fails for everyone; history and session state live in one
SQLCipher database whose key alone is in the Keychain.

## What was slow

Measured from the code, before this change:

| Step | Before |
|---|---|
| Before encrypting a send | reads the chat document and both accounts' device lists (3 round trips, 3+ Firestore reads) |
| Keychain calls per received message | about 11 (journal and its index, session, sync position) |
| Saving a message, reaction or edit | re-encrypts and rewrites the chat's whole history file (99 ms per save at 2,000 messages on a desktop) |
| Own reaction on screen | after the whole send, with the menu busy meanwhile |
| Start-up | waits for prekey upkeep; reads the own profile twice |

## 1. Reactions show at once

`PendingReactions` records the chosen reaction for its message and the chat
screen draws it over the saved history (`shownMessagesProvider`). When the send
ends the entry goes and the history shows the result: a failed reaction is
simply not there, with no notice. An unknown outcome is not sent again; the
person can react again. A reaction that reached the server but could not be
saved here is saved locally without being sent again (`saveControlLocally`).
Edits and deletes keep their notices.

## 2. No reads before a send

**Device lists** come from a live listener per account (`DeviceCache`, at most
32, least recently used first), started when a chat opens. Only server
snapshots are used; one from the offline cache could miss a new device. If a
new listener has not answered within 4 seconds the send reads directly, as
before. A changed identity is re-checked on every send, so trusting the new
key lets the next send through. Device documents are immutable apart from
revocation, so a listener costs one read per device when it starts and almost
nothing after: fewer reads than one per send.

The risk is the one Signal handles with 409: a device linked a moment ago can
miss one message, which then shows "Sent before this device was added" there.

**The chat document** comes from the chat-list listener when it says the chat
is accepted; the rules never let a chat go back from accepted. A request is
still read fresh, because its counter decides whether a message may be sent.

## 3. Append-only history for long chats

Each chat keeps its snapshot file, unchanged in format. Chats of 200 records or
more also keep `<snapshot>.log`: the SHA-256 of the snapshot it extends, then
length-prefixed AES-256-GCM boxes, each holding the records that changed in one
save, already projected. Loading reads the snapshot and then the entries in
order; nothing is replayed.

- Each box's associated data is the chat id, the snapshot hash and the entry's
  position, so entries cannot be reordered, moved to another chat or replayed
  onto another snapshot.
- Content that is erased must not stay on disk. A deletion (for everyone or on
  this device), a quote losing its text, a body replaced without being kept as
  an edit, or a control record rewritten all force a new snapshot, which
  deletes the log. Reactions and edits only add, so they are appended.
- The log is folded into a new snapshot after a quarter of the snapshot's
  records (at least 64 entries), so loading stays quick.
- A last entry cut short by a crash is dropped and cut off before the next
  append. A log whose hash does not match its snapshot was left by a rewrite
  that stopped before deleting it; its records are in the snapshot already, so
  it is ignored. Any other damage is reported, as for the snapshot.
- Decision 0013 still holds: readers see a change only after it is flushed.

## 4. Fewer Keychain calls

The chat service reads its own keys (sessions, the receive journal, sync
positions) through `CachedSecretStore`. Every write still goes to the
Keychain; a value is remembered only after the write succeeded; a failed or
overlapping write forgets it, so the next read asks the Keychain. Session
state therefore stays in memory while the app runs. The identity and device
keys already did, and the cache ends with the session. Nothing else writes
these keys.

At most one receive journal can be open: every receive and send first
finishes the open one and fails if it cannot. It now has one fixed slot
(`journal:<device>`) instead of a key per message plus an index. Journals left
by older versions are still finished first.

A received message now takes at most four Keychain calls (journal written and
closed, session saved, sync position saved); a send writes each target's
session once.

Signal's approach (sessions in the encrypted database, one transaction per
message, no journal) would go further but needs a database package; that is
the owner's decision.

## 6. Start-up

Prekey upkeep runs in the background once the device has published keys; a
brand-new device still waits for its first keys, since nobody could start a
conversation with it before that. The username comes from the profile already
read.

Upkeep used to save the private prekeys it had loaded at its start. A one-time
prekey spent by a handshake while it ran came back (possible before through
the receive-side repair too). Every change to the private prekeys is now one
load, change and save under a lock, never held across a network call; two
runs at once share one; a closed session stops it before further writes.

## Tests

`device_cache_test`, `known_chat_test`, `keychain_traffic_test`,
`history_log_test`, `prekey_background_test` and the new cases in
`message_reactions_test`. The upkeep race test fails on the previous code.
Two tests edited or read stored state behind the chat service, which the
cache no longer sees: one now shortens the stale period instead of ageing the
stored session, the other reads the journal slot instead of the old index. A
test fake of `KeyService` gained `watchDevices`. The randomized chat
simulation passes.

Implementation assisted by Claude Code.
