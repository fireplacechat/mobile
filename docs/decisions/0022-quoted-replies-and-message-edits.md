# Quoted replies and message edits

Status: implementation requested by the owner, 2026-11-10. Review before merge.
Extends decision 0021 without changing keys, ratchet construction or server rules.

## Interaction reference

Follow Signal iOS: swipe right or choose Reply, show a cancellable quote above
the input, include the quote in the sent bubble, and tap it to locate the original.
Edit from the held-message menu or double-tap an eligible outgoing message.
Use a separate editing draft, a checkmark to submit, and Cancel to restore the
ordinary draft. Show Edited beside the timestamp and a version-history sheet.
Allow ten edit revisions within 24 hours of original sending. No delivery/read
status, typing or presence indicators are added. Fireplace colors remain.

References: [replies](https://support.signal.org/hc/en-us/articles/6851465208986-Reply-to-a-specific-message)
and [editing](https://support.signal.org/hc/en-us/articles/6255134251546-Edit-Message).

## Encrypted payloads

Plain text stays v1. A reply is
`{v:3,type:'text',body,quote:{targetId,senderUid,body},ts}`. Quote text is a
snapshot of at most 1,024 Unicode characters, never an embedded message tree.
The normal body keeps the 16,384-character limit. Validate bounded identifiers,
quote shape and lengths before accepting it. A quoted snapshot is content from
the replying account, not cryptographic proof that its attributed author wrote
it. Resolve navigation against local history; never retrieve plaintext remotely.
Unknown/undecryptable originals still allow the encrypted snapshot to be read;
tapping explains that the original is unavailable. Known deleted originals
scrub quote bodies, including on replay. Editing the original does not rewrite
previously sent quotes.

An edit is `{v:3,type:'edit',targetId,body,revision,ts}`. Revisions are integers
1 through 10. The authenticated envelope sender must match the original author;
payloads cannot choose an actor. Edits are hidden control records and consume a
normal ratchet key for every receiving device, including linked-device copies.
Only accepted conversations may send these content operations. The sender
checks ownership, readable target, original age, limits and a changed body under
the existing send mutex before encryption. Receivers accept late delivery of
authorized revisions: an offline timestamp cannot prove when a user edited.

Keep a bounded history of the original plus ten revision slots. For concurrent
linked-device edits at the same revision, the greatest `(deviceId,eventId)` wins
that slot. The greatest revision is displayed; arrival order cannot roll it back.
Conflicting versions of the same slot are not separate history entries. Choose
the next revision above every observed local attempt, including an uncertain
send, so an unresolved attempt never reuses a slot. This conservatively consumes
an edit allowance when publication cannot be established. No automatic retry.

Unknown targets retain hidden edits until the original arrives. Undecryptable
targets never become readable from an edit. Local tombstones and remote deletion
dominate edits, erase all versions and scrub hidden edit content. Reactions stay
attached to the original message ID. Edits cannot change the reply reference.

## Durability, privacy and compatibility

Store quotes/history only in existing encrypted local files and receive journals;
old optional fields default to empty. Project controls in linear history passes
and bounded per-message revision work. Preserve reply metadata through unknown
outcomes, explicit status checks, local-save repair and explicit new-copy sends.
Ordinary drafts, reply targets and edit drafts are account-scoped; dismissing an
edit restores ordinary text, and access changes revoke open content surfaces.

Firestore retains exactly the existing encrypted envelope and metadata fields.
Each operation costs ordinary Spark message writes/reads. No new services,
collections, indexes, packages or plaintext server fields. Older clients can
read a reply's text but omit its quote, and cannot apply edits. Both participants
need updated clients for the complete experience. Remote erasure remains best
effort and cannot remove independent copies or older clients.

## Tests

Use real encryption with fake Firestore for both participants and linked devices;
test ordering, duplicate/replayed controls, forged authors, unknown/unreadable
targets, deletion dominance, size/revision/time limits and unknown outcomes.
Exercise encrypted disk reload and receive-journal recovery with metadata.
Keep chat simulations and the separate emulator rules suite green. UiFixture
tests and light/dark renders cover reply/cancel/send/jump, swipe, edit/cancel/save,
history, accessibility actions, enlarged text, keyboard and account transitions.

AI assistance: OpenAI Codex wrote this design and the implementation/tests.
