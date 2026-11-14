# 0052: One colour per person

Date: 2026-11-14. Status: accepted by the owner. Changes the 1:1 message payload
(a new optional field) and replaces the two colour choices in Settings.

## What changes

Until now an account chose two colours on its own phone: one for its own messages
and one for everyone else's. Nobody else saw either. Group chats (0050) introduced
the other idea: each person has **one** colour, and everyone in the group sees that
person's messages in it.

The owner's decision: that is the rule everywhere.

- You choose **one colour**. Your messages use it.
- **Other people's messages use the soft tint of their colour**, in 1:1 chats as in
  groups. Their name and avatar in a group, and the reply bar when you reply to
  them, use its text shade.
- Replying to your own message uses your colour.
- Settings has one choice, *Your color*, under the heading *Make it feel like
  you*. Its preview shows two bubbles in the chosen colour: **You see** (the colour
  itself) and **They see** (its soft version, as your messages appear on other
  people's phones).
- The second choice (the colour of other people's messages) is gone. A saved second
  colour is ignored.

## How the colour reaches the other person

In a group it already travels as an encrypted `profile` message (0050). In a 1:1
chat it now travels **inside each text message**:

```
{ "v": 1, "type": "text", "body": "...", "ts": ..., "color": "plum" }
```

- `color` is optional. It is the colour's name: lower-case letters, at most 24.
  Anything else is dropped on receipt and the message is shown as usual.
- Only text messages (and replies) carry it. Reactions, edits and deletes do not.
- **It costs nothing extra:** no new message, no new Firestore write or read, no
  function. The field is inside the ciphertext, so the server never sees it.
- Apps from before this note ignore the field: they read `type` and `body` only.
- The receiving phone remembers the latest colour for each person, in the device's
  secret store (`peercolors:{uid}`), and forgets it when the account is erased
  from the phone. A message from the account's own other device carries its own
  colour and is not recorded as anyone else's.

### What follows from sending it with messages

- Someone who has not sent you a message since choosing shows in the default
  colour (Stone) until they do. A changed colour shows from their next message.
- A message received only by the background notification handler does not update
  the colour; the next one read with the app open does.
- **Privacy.** Your colour was known to nobody; now everyone you send a text to
  learns it. It is a choice among five names and is sent only to people you are
  already messaging, end-to-end encrypted. No account field, no profile field and
  no server record holds it.

## Not changed

- The five colours and their shades.
- Group chats keep their `profile` message, which also answers a newcomer.
- Your colour is still the app's accent on your own phone.

## Tests

- `test/model/chat/own_color_test.dart`: the field is written only for text; a
  malformed colour is dropped and the text kept; two accounts and a linked device
  over the real double ratchet, with the colour learnt by the other person, not by
  the sender's own second device, absent from everything the server stores, and
  updated by a later message; the per-account store.
- `test/view/chat/peer_color_test.dart`, `reply_panel_test.dart`: bubbles and the
  reply bar use the other person's colour, or the default before it arrives.
- `test/view/settings/`: one choice, the explanation, saving, and that an older
  two-colour save reads as its first colour.

AI assistance: Claude Code.
