# 0059: A message that was not sent is finished by the app

Date: 2026-11-15. Status: accepted by the owner. Builds on
[0058](0058-save-a-message-before-sending.md). Changes what the app does with
a send whose outcome it does not know; changes nothing on the wire or on the
server.

## The problem

When a send ended without an answer (the network dropped, the app was closed),
the conversation showed a warning card: "Message not confirmed", with "Check
status" and "Send again…", and a second question before sending another copy.
The app could not tell whether the message had arrived, so it asked the person.

That is the wrong person to ask. They cannot know either, and the card is
large, worrying, and offers a choice with a consequence ("could create a
duplicate") that nobody should have to weigh to send a message.

## Why the app can decide

The card existed because sending again made a **new** message with a new id.
If the first had arrived, the other person got it twice.

A message's id is chosen on the phone before it is sent, and since 0058 it is
saved with the message. The server's rules take a message id once: a write to
an id that exists is an update, and updates to messages are refused for
everyone. So sending the saved message again **under its own id** has two
possible results:

- the first try never arrived: this one is the message;
- the first try did arrive: this one is refused, and nothing changes.

Either way the other person has it once. No rule changes; this is how the
rules already are.

## The decision

A saved message of this account that is still marked unconfirmed is finished by
the app:

1. Ask the server for that id (one read).
2. It is there: mark it sent.
3. The server answers that it is not there: send it again under the same id.
   If that is refused, ask once more, because an earlier try may have arrived
   in between; if it is there now, mark it sent.
4. The server cannot be reached: wait and try again, after 5, 20 and 60
   seconds.

This starts when the app sees such a message: straight after a send that got no
answer, and at every start for anything left from before.

**What the person sees.** The message stays in the conversation and looks like
any message on its way. There is no card. If the server refuses the message, or
the tries run out, the bubble says "Not sent. Tap for options.", the same as a
message that failed to send in the ordinary way, with the same "Send again" and
"Delete". "Send again" does steps 1 to 3 again. The chat list says "You (not
sent)" for it, and nothing special while it is still trying.

**A day's limit.** A message left unsent for more than a day is not sent by the
app: it shows as "Not sent" and waits for the person. Someone who wrote
something last week should not find it delivered today.

## Cost

One read per unfinished message per try, and one message write if it was not
there. Unfinished messages are rare, and the tries are bounded at four.

## What stays

- Edits, deletes and reactions whose send got no answer keep their own
  handling.
- Group messages keep theirs ("Not confirmed" under the message).
- If the phone cannot write to its own storage, the message is kept in memory
  with the old card, because there is no saved message to finish. That needs a
  storage fault to happen at all.
- A message is never sent again under a **new** id by the app.
