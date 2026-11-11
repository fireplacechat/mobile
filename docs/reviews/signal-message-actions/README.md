# Held-message press, deletion, selection and forward

The held-message interaction follows Signal's iOS context menu: a short tap
does nothing, a brief hold shrinks the bubble, and the menu opens only if the
finger is still down when that shrink finishes. The menu for someone else's
message is Reply, Forward, Copy, Select, Info, Pin and Delete. A message you
sent also offers Edit while it is still within the existing edit window.

Deleting someone else's message removes it on this device only. Deleting a
message you sent can remove it for everyone, with no time limit. Either way
the row disappears. There is no "this message was deleted" line. The encrypted
record stays, with an empty body, so a replay cannot bring it back. Search,
the chat list, unread counts and in-app notices skip it. Info shows Sent or
Received and the time. It does not show delivery or read state. Pins are
message ids on this device, in the encrypted chat preferences, and they are
not synced.

Select uses a circular mark in the account accent. Delete All removes the
visible messages in that chat on this device, and deletes messages you sent
for everyone. Messages the other person sent stay on their devices. Forward
opens a sheet of Recent Chats, then People. There is no Stories section.

The wire format, sender authorization and Firestore rules are unchanged.
Decisions 0023 and 0025 record the deletion changes.

Pressing send clears the composer and shows the message in the conversation
at once, with its time. Encryption still runs afterwards. The send button
stays the arrow. A failure still says it was not sent. A reaction sits in a
pill with the same space on both sides of the emoji. The name at the top of
a chat is the same size as the name in the chat list.

## Screenshots

Flutter renders of fictional fixture data, UTC, with the installed Windows
emoji font used only as a test fallback. The forward picture is the sheet
over the chat, about half the page. It has Cancel, Recent Chats, then People.
There is no Stories section and no Back button.

| State | Render |
| --- | --- |
| Received message | [Dark](dark-message-actions-incoming.png) |
| Sent message | [Light](light-message-actions-outgoing.png) |
| Info | [Dark](dark-message-info.png) |
| Delete someone else's message | [Dark](dark-message-delete-for-me.png) |
| Delete a message you sent | [Dark](dark-messages-remote-delete-confirmation.png) |
| After that delete | [Dark](dark-messages-remote-deleted.png) |
| Selection | [Dark](dark-messages-selected.png) |
| Delete the selection | [Dark](dark-messages-delete-confirmation.png) |
| Delete all, enlarged text, keyboard open | [Dark](dark-message-delete-all.png) |
| Forward | [Dark](dark-forward-message.png) |
| Pinned message | [Dark](dark-pinned-message.png) |
| Reaction on a message | [Dark](dark-messages-reaction-counts.png), [Light](light-messages-reaction-counts.png) |
| Message just sent | [Dark](dark-outgoing-sending-next.png) |

Hashes are in [render-sha256.csv](render-sha256.csv).

## What was not checked on a device

The 0.2s press and the 0.2s shrink are the durations in Signal's
`ContextMenuInteraction`, and a widget test samples the scale between them.
The feel of that hold was not checked on a phone.
