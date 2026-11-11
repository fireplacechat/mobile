# Sent message

Pressing send shows the message at once. It slides up from behind the
composer, which sits on the keyboard, in about 0.18 seconds. The
conversation list clips the start of that move.

The same message was also drawn twice. History saved it, and the temporary
row stayed until a chat-list timestamp write finished. Those rows use
different ids, so both stayed on screen for that round trip. The timestamp
write now finishes after the send returns. A saved row covers its temporary
row. A second copy of the same text still shows, and an older message with
the same text stays where it is.

The wire format is unchanged. The chat list is still reordered at most once
a minute. A failed timestamp write leaves the send looking sent.

## Screenshots

Flutter renders of fictional fixture data, UTC, dark theme, keyboard open.
The first is 40 milliseconds into the slide. The second is the message at
rest. Enlarged text is covered by a widget test.

| State | Render |
| --- | --- |
| Sliding up | [Dark](dark-send-sliding.png) |
| At rest | [Dark](dark-send-slid.png) |

Hashes are in [render-sha256.csv](render-sha256.csv).

## What was not checked on a device

The motion was sampled in a widget test and in these renders. It was not
checked on a phone.
