# 0054: Quiet messages, and less work per message

Date: 2026-11-14. Status: accepted by the owner, following the audit of that date.
Adds one optional field to the message documents the app writes (the rule that
allows it is made in the backend). No change to what is encrypted.

## Why

The server cannot read a message, so it sent a "New Message" alert for every
message document. That included things nobody reads as a message:

- in a 1:1 chat: an edit, a delete for everyone, and a reaction taken back;
- in a group: those three, and the colour and notice messages that members'
  phones send each other without anyone typing.

On an iPhone each of these showed as "New Message" (the notification extension
cannot hide an alert), and each one started the extension and cost the server
the lookups of a real message. Issue 82 lists the false alerts as its open part.

## What changes

- **The app marks such a document `quiet: true`** when it writes it. Nothing else
  about the document changes, and nothing inside the encryption changes.
- **The server sends no alert for a quiet document.** An Android phone that posts
  its own notifications still receives it as data, so it can update or remove the
  alert an edit or delete is about, as before. An iPhone receives nothing: the
  change shows the next time the app is open, which is what happened already,
  minus the false alert.
- **A new reaction is not quiet**: it has its own notification.
- A text is never quiet.

## What the server learns

That a document is not a message a person reads. It does not learn which of the
kinds above it is. It already saw the document's size, sender, device and time.
This is the first time the app tells the server anything about what a message
is, so it is recorded here as a deliberate trade: one bit, for no false alerts
and less work on every phone.

## Also in this change: less work per message and per start

None of these changes what a person sees.

- **The block list is read once at start**, by its listener, where it was read by
  a direct read and then again by the listener. Offline, the copy on the phone
  stands in after three seconds.
- **Group key packages are counted** (one read) before they are listed (ten), as
  the one-time prekeys already are.

## Cost

Fewer reads and fewer pushes in every case. No new write.

## Older versions

- A phone on an older version sets no mark: its edits and deletes alert as before.
- A phone on an older version receiving a quiet message is unaffected: the mark is
  on the document, not in the message.

## Tests

- `test/model/chat/quiet_messages_test.dart`: which changes are quiet, and what
  the document carries.
- `test/model/groups/group_service_test.dart`: colours, notices, edits, deletes
  and reactions taken back are quiet in a group; texts and new reactions are not.
- The existing group and safety tests cover the block-list and key-package changes;
  the server's behaviour is tested in the backend.
