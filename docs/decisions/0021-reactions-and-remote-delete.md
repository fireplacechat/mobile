# Encrypted reactions and remote deletion

Status: implementation authorized by the owner on 2026-11-10, following the
initial request for a design-only phase. Human review is still required before
merge. This note does not change the cryptographic construction.

## Scope and presentation

Use Signal iOS's lifted-message context menu, reaction strip, selection controls,
and text composer as interaction references, with Fireplace's existing colors.
Reactions are message content. They introduce no typing, delivery, read, presence,
or last-seen indicators. Attachments are outside this work.

## Payloads and compatibility

Keep text at `{'v':1,'type':'text','body':text,'ts':milliseconds}`. Add version 2
content payloads inside the existing encrypted envelope:

* `{'v':2,'type':'reaction','targetId':id,'emoji':emoji,'operation':'set'|'clear',
  'revision':positiveInteger,'ts':milliseconds}`.
* `{'v':2,'type':'delete','targetId':id,'ts':milliseconds}`.

Validate types, version, identifier length, operation, revision range and emoji
length before applying a control. A reaction is one Unicode grapheme cluster,
with a small byte/codepoint bound; the UI offers a fixed quick palette and an
expanded picker. Invalid or unsupported authenticated content consumes its
ratchet key and is journaled as an unsupported placeholder, never interpreted as
a command. Existing clients display their existing unsupported-message fallback;
they cannot honor a remote deletion. Deployment must explain that both clients
need an updated version. There is no silent downgrade to plaintext commands.

## Transport, authorization and ordering

Use the same sender mutex, recipient discovery, authenticated encryption,
write-ahead ratchet persistence, rate limit and Firestore message batch as text.
Each control has a new message ID and consumes a fresh ratchet key per receiving
device. It is copied to the peer's devices and the sender's other linked devices.
Never reuse the target's ID as the control's own transport ID. Neither definite
failure nor an unknown publish outcome can cause an automatic new send.

Only accepted conversations may send controls. Resolve the actor from the
authenticated sender; no payload may choose an actor. Reactions may target either
participant's readable text. Each account has one reaction per target, shared
across its devices. Changing emoji replaces that account's reaction; choosing its
current emoji clears it. A clear carries a revision too, so an older set cannot
restore it. Choose the greatest `(revision, senderDevice, controlId)` for an
actor/target pair. Locally generated revisions advance beyond all observed
revisions for that actor and target; concurrent offline devices have a stable
tie-break. Wall-clock time does not determine reaction ordering.

Only the original sender account may delete its message remotely, including from
another linked device. A delete permanently dominates reactions and text replay.
Use a 24-hour sending window in the UI and sender, matching the referenced
interaction. Receivers allow late delivery within server retention; an untrusted
sender timestamp is not proof of the age of an offline deletion. Deletion is
best effort: it cannot erase screenshots, exports, older clients or another
person's independent copies. Confirmation explains this plainly.

## Local persistence and replay

Store controls as hidden records in the existing encrypted history and fold them
into immutable `LocalMessage` reaction state for display. Keep clear revisions
even when no emoji is displayed. Persist the received control through the same
receive journal as text, before completing advanced session/prekey persistence.
Journal recovery and duplicate transport delivery must be idempotent.

An unknown target produces no visible bubble or unread count for a successfully
decoded control. Retain the encrypted control so a delayed text can resolve it;
fold history in linear passes plus sorting, with constant-time target lookup,
not nested scans of messages. An undecryptable target cannot show reactions;
remote deletion requires matching sender provenance. Never fetch old plaintext
or rewind a ratchet to satisfy a reference. Devices linked after the original
message cannot reconstruct it from a reaction.

Remote deletion erases the original body from the next committed encrypted
history snapshot and leaves a neutral deleted-message placeholder. Local
deletion erases the body and retains only a hidden encrypted tombstone, so
`has` still suppresses ciphertext replay while `get`/`watch` expose no message.
Local deletion wins over later reaction/delete events and stays device-specific.
Memory-only uncertain sends must also be removed from the local pending UI.
Neither action makes any claim of forensic erasure of flash storage or backups.

Add optional local fields with defaults so existing encrypted histories and
journals load unchanged. Keep the existing at-rest key and encryption format;
there is no new plaintext file, preference, cache, analytics or server index.
Writes remain serialized and publish new cache state only after durable rename.

## Firestore and free-plan impact

There are no new server document fields, collections, services or indexes.
Reaction and delete bodies remain inside existing ciphertext envelopes, under
the existing ciphertext cap. They cost an ordinary message write/batch and
ordinary recipient reads on Spark. Existing membership, device, block, quota,
rate-limit and expiry rules must apply unchanged. A remote delete is an encrypted
request to clients, not a privileged Firestore delete of the original document.
The separately maintained rules suite must verify the unchanged outer schema;
this repository cannot assert emulator coverage for private rules it lacks.

## Validation required

* Payload round trips and malformed versions, identifiers, emoji, operations and
  revisions; unchanged text compatibility and ciphertext size bounds.
* Real service-layer encryption/decryption with fake Firestore at its edge:
  set/change/clear, both participants, linked copies, out-of-order targets,
  duplicate delivery, deletes by the wrong account and late deletes.
* Local memory and encrypted-disk stores: reopen, no plaintext, replay suppression,
  unknown/undecryptable targets, clear/delete dominance and failed durable writes.
* Journal replay, restart and publish failures: no reused key, no automatic retry,
  no content event mistaken for a text-send recovery operation.
* Randomized event schedules alongside `chat_simulation_test.dart`; existing
  protocol simulations and the owner's rules tests must stay green.
* UiFixture tests and deterministic light/dark renders for context menu, reaction
  strip/picker/counts, selection, both deletion confirmations and deleted bubbles;
  keyboard, semantics, large text, small screens, account changes and errors.

AI assistance: OpenAI Codex prepared this design and its implementation/tests.
The submitting human remains responsible for review under `.github/AI_POLICY.md`.
