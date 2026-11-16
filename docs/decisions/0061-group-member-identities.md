# 0061: Group members are checked against the identity keys this phone trusts

Date: 2026-11-15. Status: proposed for review.

## Decision

The group design (`docs/protocol/group-chats-v1.md`, "Credential") says the
core reports every member as a verified `(uid, deviceId, accountIdentityKey)`
and the app compares that identity key with its pins (decision 0014). This
note says exactly when the app compares, with what, and what happens when the
keys differ.

A phone compares the identity key of:

- **the devices it is about to add**, before the Commit and the Welcome are
  saved or sent;
- **every member of a group it joins**, before the join is saved;
- **every device a received Commit adds**, before the Commit is saved.

The key it compares with:

- for this account's own devices: this device's own identity key;
- for an account it has a pin for: the pin, the same one 1:1 chats use;
- for an account it has never seen: none yet. The key is remembered (pinned)
  the first time it is seen, as in a 1:1 chat. It is remembered only when the
  whole change passed, so a change that is refused teaches the phone nothing.

One pin per account serves both 1:1 chats and groups. Someone first met in a
group and later added as a contact is checked against the key the group
showed, and the other way round.

## Inviting

The inviter reads the invited person's devices as a 1:1 chat does
(`KeyService.fetchDevices`): certified by the identity key the phone trusts
for them, and not revoked. Only those devices are added. The core is given
the account and the identity key every key package must carry
(`commit_add` with `uid` and `identity`), and reports who each package
belongs to before anything leaves the phone. The app then requires, for each
package: the invited account, the device it was listed under, the trusted
identity key, and the hash of that device's verified certificate
(`certHash`). Anything else and the invitation is not sent.

The server allows an invitation only between accounts that already share an
accepted 1:1 chat, so the inviter has, or gets at that moment, the same pin a
chat with that person uses.

## When a key contradicts a pin

The change is not applied and the person is asked, as in a 1:1 chat:

- **A received Commit.** The group stops at its current epoch on this phone.
  The group's screen shows "<name>'s security code changed. This group is on
  hold." with Review. Nothing newer in that group is read or shown until the
  person accepts the new key; then the Commit is applied and the group
  catches up. Declining leaves it on hold.
- **Joining.** The join is not kept. The same review is shown; after
  accepting, the person joins again.
- **Inviting.** The invitation is not sent; the chat with that person shows
  the usual security code warning.

Accepting a new key in a 1:1 chat releases the groups that were waiting for
it, and accepting it in a group releases the chat.

Other phones are not affected: each decides for itself. A phone that holds a
group sends nothing useful to it meanwhile, since it is an epoch behind.

## Also checked on joining

- The core is told which group the Welcome must be for (`join` with `gid`)
  and refuses any other before keeping anything.
- The member who made the Welcome, as MLS authenticated it (`inviter`), must
  be the person the invitation names.

## Costs

Inviting reads the invited person's device records once more than before (at
most a handful of documents). Nothing is added to the server, and no fields
change. Pins are local records as before.

## Limits

- First sight of a stranger in a group is trusted on the word of the member
  who added them. A member is already in the group and reads everything in
  it, so this gives them nothing new there; it can give a wrong first key for
  that stranger, which a later 1:1 chat or verification would show.
- After an identity reset, a device's group credential still carries the old
  identity. Other phones will hold changes that add such a device. Re-issuing
  the credential after a reset is not part of this change.

## Core

Needs `fireplace-crypto` with `added` in the result of `commit_add`,
`certHash` on members, and `inviter` and `gid` on `join`.

## Validation

`test/model/groups/group_member_identity_test.dart`, with the real core:

- an invitation pins the invited person, and members pin each other on first
  sight;
- a key package made under another identity in the invited person's name is
  refused, and no Commit, Welcome or request is sent;
- a Commit adding someone under a key the phone does not trust for them
  stops the group; trying again without accepting changes nothing; nothing
  newer is read; after accepting, the group catches up;
- joining waits in the same way and keeps nothing of the group until then;
- an invitation for someone whose key changed is not sent.
