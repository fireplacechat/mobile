# 0062: Replace the identity when a removed device was lost or stolen

Date: 2026-11-15. Status: proposed for review.

## Background

Removing a device is enforced by the server: other phones skip a device the
server marks as removed, and the server refuses its messages. Every linked
device holds a copy of the account's identity key, and removal does not take
that copy back (`docs/protocol/group-chat-design.md` already says so). A
removed device that is in someone else's hands could therefore still sign as
the account. Nothing the account signs can shut it out, because it can sign
the same things.

Replacing the identity does shut it out. The old device's certificate and its
group credential are signed by an identity that contacts no longer trust.

## Decision

Removing a device is two small questions, each with one thing to decide,
on the sheet the app uses for such questions:

1. **"Remove this device?"** Remove or Cancel, as before.
2. Once it is removed: **"Was it lost or stolen?"** with "Reset your security
   code to lock it out. Your other devices and groups need setting up
   again." The answers are "Reset security code" and "No, I have it".

"No, I have it" ends there: the device is removed and nothing else changes.

Replacing does, in this order:

1. Leaves every group, while the old identity can still say so. Other members
   see that the person left and can invite them again.
2. Runs the existing identity reset: a new identity and new device keys on
   this phone; every device record of the account, the recovery key backup
   and the push routing of the old devices are deleted.
3. Starts the session again on the new identity.

For the person: contacts see "security code changed" once and accept it, as
after a reinstall. Other devices of the account have to be linked again. A
new recovery key has to be made. Groups have to be rejoined by invitation.
Message history on this phone stays.

The reset itself is not new. It was offered only on a phone that had lost its
keys ("Start fresh"). This offers it where it is needed for another reason.

## Group records after a reset

A device's group records hold a credential that names that device under one
identity. They are now marked with their owner (a hash of the device id and
the identity key). When the group service starts and the records belong to
another owner, they are erased and the device starts again with a credential
of its own. Records from before this change are taken as this device's and
marked.

This also covers a reset that was interrupted, and a group that could not be
left because the phone was offline: its keys are discarded all the same.

## Not chosen

- **A device list signed by the account.** A removed device holds the
  signing key, so it could sign a newer list with itself in it.
- **Keeping the identity key on one main device only**, with linked devices
  holding keys of their own that the main device vouches for. Removal would
  then be silent for contacts. It changes linking, recovery and group
  credentials together, and is left as a possible later project.

## Limits

- Contacts must accept the new security code before messages flow again,
  and a careful contact will want to verify it.
- Messages the lost device already received stay on it.
- If the person answers "No, I have it" for a device that was in fact
  stolen, nothing here helps; the threat model says what removing does.

## Costs

One delete per old push routing record during a reset, and one leave request
per group. Nothing recurring. No new server fields or rules.

## Validation

- Reset: old devices, backup and push routing are gone; a contact who trusts
  the old identity is warned; after accepting the new one, a record of the old
  device that is put back on the server is not accepted.
- Groups: after leaving and a reset the restarted group service has no
  groups, publishes key packages for the new device, and the account can be
  invited and read messages again; a restart of the same device keeps its
  groups.
- Screen: the second question comes only after the device is removed; "No, I
  have it" changes nothing more; only "Reset security code" replaces the
  identity.
