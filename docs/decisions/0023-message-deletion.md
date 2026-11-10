# Deleting messages

Status: requested by the owner, 2026-11-10. Extends decision 0021.
The delete payload, sender authorization and replay rules are unchanged.

## Who can delete

A message you sent can be deleted for everyone at any time. The 24-hour window
in decision 0021 applied to the sender and the menu; it no longer applies to
deletion. The sender still has to be the original author. Editing stays limited
to ten revisions within 24 hours.

Someone else's message can be removed on this device only. That deletion is not
sent, and their devices keep the message.

Delete all, from the selection bar, removes the messages shown in that chat on
this device. It does not ask other devices to delete them.

## What remains on screen

A deleted message is not shown. There is no placeholder sentence. The encrypted
history still keeps a remotely deleted record with an empty body so a replay
cannot restore it, and a locally deleted record stays hidden so `has` still
suppresses ciphertext replay. Search, the chat-list preview, the unread count
and in-app arrival notices skip those records. Nothing here adds delivery,
read, typing or presence state.
