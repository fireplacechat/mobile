# Delete all also removes messages you sent

Status: requested by the owner, 2026-11-11. Extends decision 0023.
The delete payload, sender authorization and replay rules are unchanged.

## What Delete all does

Delete all, from the selection bar, removes every message shown in that chat
on this device. A message you sent, whose send is confirmed, is also deleted
for everyone through the existing delete control. That control is copied to
the other person's devices and to your other linked devices.

A message the other person sent is removed on this device only. It is not
sent as a delete, and their devices keep it. A message whose send was not
confirmed is removed on this device only, because it may never have reached
them.

The confirmation says this. A remote delete is still best effort: it cannot
erase a screenshot, an export, or a copy held by an older client.
