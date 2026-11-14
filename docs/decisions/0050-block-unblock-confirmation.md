# 0050: Wait for confirmation when unblocking and receiving our own sends

Date: 2026-11-14. Status: implemented locally; phone verification pending.

## Problem and evidence

The reported symptom is delayed or missing messages after blocking and
unblocking, sometimes with a **Not sent** error. The rules contain no unblock
cooldown. Repeated blocked-send simulations, with real crypto and a refused
publish boundary, preserve both new and established sessions and resume in both
directions immediately after a confirmed unblock.

Two SDK event sequences do reproduce application bugs. Firestore emits a local
block-document deletion before its write is acknowledged. The safety listener
previously exposed that as an immediate unblock, allowing receive sync to resume
while the server could still refuse the peer's messages. Separately, a local
pending message snapshot could turn an ambiguous outgoing send into **sent**
without server confirmation. Fake Firestore always reports no pending writes,
so the existing tests missed both sequences.

These reproduce contributing failure paths; they do not establish the exact
duration or sole cause of the reported incident on a real phone.

The SDK ordering and metadata-only acknowledgement behavior are documented in
[Firestore's listener guide](https://firebase.google.com/docs/firestore/query-data/listen#events_for_metadata_changes).

## Behavior

Keep a locally unblocked peer blocked until the delete future succeeds. Retain
the block on failure, including late pending-write callbacks. Serialize changes
per contact so a later block cannot be overwritten by an earlier unblock
completing last, and one slow unblock cannot delay blocking someone else.
Other devices still learn
block changes through the existing listener.

The live receiver ignores pending write echoes and processes committed additions
and modifications. Subscribe to metadata changes so a server acknowledgement
that only changes metadata is still processed. One-shot receive also leaves
pending documents unfinished and holds its cursor. An uncertain send remains
uncertain until committed evidence arrives; it is never automatically resent.

Keep existing encryption sessions, identity pins, request acceptance, server
rules and generic refusal messages. Do not reset ratchets on block/unblock or
expose another account's private block list.

## Cost and verification

No new server fields, queries, writes, packages or functions. Metadata events
produce extra local callbacks on the existing listener; they request no extra
documents. Existing history checks deduplicate committed modifications.

Regression tests exercise delayed and refused unblock acknowledgements, pending
send echoes, metadata-only commit acknowledgement, and repeated refused sends
before/after session establishment. Before release, use two phones to block,
attempt a send, unblock, and exchange messages immediately in both directions;
repeat with a slow/offline blocker and confirm no premature **sent** state.
