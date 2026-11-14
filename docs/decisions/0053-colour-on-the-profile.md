# 0053: A person's colour is on their profile

Date: 2026-11-14. Status: accepted by the owner. Replaces the section "How the
colour reaches the other person" of [0052](0052-one-colour-per-person.md) for 1:1
chats. Adds a profile field (a Firestore rules change, made in the backend) and
removes a field from the 1:1 message payload.

## Why

0052 sent a person's colour inside each text message, so that the server never saw
it. In use that was not enough:

- A colour showed only after the person had sent a text from the new version.
  Someone who accepted a chat and had not written yet, or had not written since
  updating, stayed in the default colour.
- A message received by the background notification handler did not carry the
  colour over.

Sending the colour on its own, encrypted, when a chat is accepted was designed and
set aside: it needs a message kind older apps show as unsupported, a server mark so
it causes no notification, and one write for each chat at every change.

The owner's decision: **a person's colour is public**, like their username.

## What changes

- The profile document `users/{uid}` gains an optional field `color`: the colour's
  name, lower-case letters, at most 24. Only the account itself can write it.
  Anyone who can read the profile (a signed-in account with a profile) can read it.
- **In a 1:1 chat, once it is accepted, the other person's avatar is filled with
  their colour and their name is written in it**: in the chat list, at the top of
  the conversation and in chat details. Before the chat is accepted, and while
  their colour is not known, both look as before.
- Their messages use the soft tint of their colour, as in 0052. That no longer
  waits for a message from them.
- Group chats are not changed: a group's avatar keeps the default colour, and
  members' colours travel as 0050 describes.
- Text messages no longer carry `color`. One received from version 0.4.0 is read
  as before and the field is ignored.
- Settings says, under the choice: "Applies to all chats. Your color is part of
  your profile, so the people you chat with see it."

## How it is written and read

- **Written** when a colour chosen in Settings has been held for 10 seconds: one
  update of the profile, however many colours were tried on the way. The update
  carries the server time of the change (`colorAt`), and the rules refuse another
  change within 5 seconds, so a modified app cannot write faster than that.
  When the app opens and the profile has no colour, or not the one chosen on this
  phone (the app was closed before it was published), the phone's colour is
  written once (also for someone who never chose: the default, Ember). When the profile
  has one and this phone has no choice of its own, the phone takes the profile's,
  so a second phone starts in the same colour.
- **Read** with the person's name. The app already reads each chat partner's
  profile once after it opens, for the username; the colour is in the same
  document, so showing it costs no read of its own. Opening a chat reads that
  person's profile again if it was last read more than 15 minutes ago, so a changed
  colour shows without restarting the app.
- The phone remembers the last colour it read for each person, in the device's
  secret store (`peercolors:{uid}`, as in 0052), so it shows at once the next time.
  A profile without a colour clears what was remembered.

## Cost

- One profile write for each colour change, and one for each account the first
  time it opens this version.
- At most one profile read when a chat is opened, and none within 15 minutes of
  the last read of that profile.
- No function, no listener, no new document.

## Privacy

A person's colour is now stored on the server, in clear, next to their username,
and any signed-in account that knows their id can read it. It is one of five
names. It says nothing about who they talk to. This is a deliberate change from
0052, which kept the colour out of the server's sight.

## Older versions

- Version 0.4.0 does not publish a colour and does not read one. To someone on
  this version, a person still on 0.4.0 shows in the default colour until they
  update and open the app once.
- To someone on 0.4.0, a person on this version shows in the default colour,
  because their messages no longer carry it.

## Tests

- `test/model/chat/own_color_test.dart`: messages carry no colour and an old one
  is still read; publishing, reading with the name, the 15-minute bound, a
  malformed value; what the phone remembers.
- `test/view/chat_list/peer_color_icon_test.dart`: avatar and name in the chat
  list and the conversation, accepted and not.
- `test/view/chat/peer_color_test.dart`: bubbles and the reply bar.
- `test/view/settings/color_publish_test.dart`: choosing publishes; a phone
  without a choice takes the profile's.
- The rules tests in the backend cover the profile field.
