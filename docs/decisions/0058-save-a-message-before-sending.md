# 0058: A message is saved before it is sent

Date: 2026-11-15. Status: accepted by the owner. Closes issue 191. Adds to
[0009](0009-service-level-simulation.md), where the "message not confirmed"
state comes from; changes nothing on the server or on the wire.

## The problem

A 1:1 message was written to history only after the server had taken it. Until
then it lived in memory, in the list of sends in progress. Closing or killing
the app during the send lost it: no bubble on the next start, and nothing to say
whether it went. Seen on the Android emulator by killing the app six seconds
after a send made straight after start-up.

Groups already saved first.

## The decision

Before anything else is done with it (finding the other person's devices,
encrypting, publishing: seconds, straight after start-up), the message is
written to history with the status **unconfirmed**, under the id it will have
on the server. That status already
means "may or may not have reached the server", which is exactly what is true
if the app stops at that moment. What the app then does with such a message is
decision [0059](0059-finish-a-send-automatically.md).

- Published: the same record becomes an ordinary sent message.
- Refused, or stopped before publishing (nothing was committed): the record
  is removed. The failed send stays
  on screen from the list of sends, as before.
- Outcome unknown: the record stays unconfirmed, as before.
- App stopped during the send: the record is there on the next start, and the
  app finishes sending it (0059).

While the send is in progress the conversation leaves that record out and shows
the bubble from the list of sends, as before, so an ordinary send never shows a
warning.

Only messages a person wrote are saved ahead. Edits, deletes and reactions are
not: saving one applies it to the conversation, and a refused one would have to
be taken back.

## Cost

One more write to the history database per message sent. No server reads or
writes.

## What it does not do

- If history cannot be written before publishing, the send goes on as it did
  before this note.
- A send waits its turn for the account's storage like every other write. In
  the first moments after the app starts, while history is still loading, a
  message can be on screen before it is saved. Measured on the emulator once
  history had loaded: saved 0.2 seconds after Send was pressed, where the send
  took 8.5 seconds.
