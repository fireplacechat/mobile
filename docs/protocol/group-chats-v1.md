# Group chats, version 1: specification

Date: 2026-11-14. Status: **design for review**; sections 2 to 4 were amended by
*Changes after the first emulator test* in decision 0050 (the invitation carries the Add; `hello` profiles;
lines; roles), and where they differ that note and backend 0023 win. Implements
[decision 0050](../decisions/0050-group-chats.md) and the
[proposal](group-chat-design.md) it amends. Fixes the interfaces three pieces of
work will build against at the same time: the Rust core, the backend, and the app.
Nothing here is implemented yet.

Fixed by 0050: suite `MLS_128_MLKEM768X25519_AES256GCM_SHA384_Ed25519`, one MLS leaf
per device, at most 16 accounts, 4 participating devices each (64 leaves), 32 groups
per account, rules-first delivery.

## 1. Rust core interface

The core owns MLS and the Fireplace credential, never storage or the network.

### State as record changes

OpenMLS keeps a group's state as many small records written during each operation.
The core never writes files. It loads a group from the records the app hands it, and
every operation that changes state returns the **changed records**
(`[{key, value | null}]`, encrypted values). The app persists them in its encrypted
journal **before** it publishes anything (decision 0007), exactly as it saves a 1:1
session today. An operation that fails changes nothing, and the handle is dropped
and reloaded.

### Credential

Each device's MLS signature key is endorsed by the account identity:

```
FireplaceMlsCredential v1 (canonical, length-prefixed fields)
  uid, deviceId, sha256(deviceCert), mlsSignatureKey, suite, generation,
  sigEd25519, sigMlDsa65      // both by the account identity, domain "fireplace-mls-credential-v1"
```

The core verifies it on every Add, Welcome and Commit, and reports each leaf as a
verified `(uid, deviceId, accountIdentityKey)`. The app compares that identity with
its contact pins (decision 0014). The app never parses MLS credentials itself.

### Operations

Handle-based and bounded, wiping buffers with `fp_free`, like `FpSession`:

| Operation | Returns |
|---|---|
| `mls_credential_create(identity, device, generation)` | credential and new signature key records |
| `mls_key_packages(credential, n)` | `n` key packages, records |
| `mls_group_create(gid, credential, name, now)` | handle, records |
| `mls_group_load(records)` / `mls_group_destroy` | handle |
| `mls_info(handle)` | epoch, verified roster `[(leaf, uid, deviceId, role)]`, name, suite |
| `mls_encrypt(handle, plaintext, aad)` | ciphertext, records |
| `mls_process(handle, message)` | `application{leaf, plaintext}` or `commit{staged summary}`, records |
| `mls_merge_staged` / `mls_discard_staged` | records |
| `mls_commit_update`, `mls_commit_add(packages)`, `mls_commit_remove(leaves)`, `mls_commit_meta(name, roles)` | commit, Welcomes (for add), records; pending until merged |
| `mls_merge_pending` / `mls_discard_pending` | records |
| `mls_join(welcome, package records)` | handle, records |

A staged commit's summary lists the leaves added, removed and updated and the new
name and roles, so the app can check it against the server roster and its rules
(only administrators remove people and change names and roles; any member's device
may add someone whose invitation was accepted) before merging.

The **name and roles** live in an application-defined group-context extension, changed
only by Commits. They are therefore encrypted, authenticated by MLS, and included in a
newcomer's Welcome. The server never sees the group name.

### Fake for development

`lib/src/crypto/group_crypto.dart` defines this interface in Dart. Until the core
implements it, `FakeGroupCrypto` (test and `GROUPS_FAKE=true` builds only; a release
build refuses to start with it) stands in. Its "ciphertext" is plaintext and
deliberately insecure, but it keeps real epochs, rosters, pending/staged commits and
record changes, so the backend and app can be built and tested now.

## 2. Firestore

`gid` is 128 random bits, base64url. Epoch document ids are zero-padded to 12 digits,
so they sort.

| Path | Fields | Written by |
|---|---|---|
| `groups/{gid}` | `members: {uid: {role, devices[]}}`, `epoch`, `suite`, `fence: [{uid, device}]`, `createdAt` | membership function; `epoch` also by a member's update Commit |
| `groups/{gid}/commits/{epoch}` | `by`, `device`, `kind: update\|membership`, `ct`, `at` | member (update) or function (membership); create-only |
| `groups/{gid}/events/{opId}` | `by`, `device`, `epoch`, `ct`, `at`, `expireAt` | member device; create-only |
| `groups/{gid}/welcomes/{uid}_{device}` | `epoch`, `ct` | function; readable by that account |
| `groups/{gid}/ops/{opId}` | a membership request and its result | member creates; function completes |
| `users/{uid}/groupRefs/{gid}` | `joinedEpoch`, `role` | function; owner lists |
| `users/{uid}/devices/{d}/mlsPackages/{ref}` | `kp`, `createdAt` | owner (at most 10 per device); function consumes |
| `users/{uid}/limits/groups` | daily counter (as decision 0017) | owner, with each group creation |

### Rules (summary)

- **Read** `groups/{gid}` and its `commits` and `events`: the caller has a profile,
  is not deleting, and is in `members`. Event queries start at the caller's
  `joinedEpoch`.
- **Create an event**:
  - The caller is a member and the device is in `members[uid].devices`; `fence` is
    empty.
  - `epoch` is the group's epoch or the one before it, so a send that races a
    Commit still lands. Receivers keep one past epoch.
  - `ct` is at most 96 KiB, `at == request.time` and `expireAt` is 30 days on.
  - The send clock is written in the same batch (decision 0028), so groups and
    1:1 chats share one allowance.
  - The id is `{device}-{counter}`, create-only: a repeat is refused, and the app
    reconciles by reading it back. It never resends (decision 0032).
- **Create an update Commit**:
  - The caller is a member, the id equals the current `epoch`, `kind == update`,
    and the document doesn't already exist.
  - The same batch sets `groups/{gid}.epoch` to the next value and changes nothing
    else.
  - The first Commit for an epoch wins. A loser discards its pending Commit,
    applies the winner, and tries again.
- **Membership** changes go only through `ops` and the function. Clients can't write
  `members`, `welcomes` or `groupRefs`.
- Banned, restricted-to-zero and challenged accounts are refused, as for 1:1 sends.

### Membership function

A Firestore trigger on `groups/{gid}/ops/{opId}` (and `users/{uid}/groupOps` for
creation and invitations), not an HTTP endpoint. There is no new client package or
App Check surface, and requests queue offline like any other write. It is
idempotent by `opId` and writes `result: accepted | refused(reason)`. It uses the
Admin SDK, so it repeats every check the rules would make: profile, ban, deletion,
challenge, roles and limits.

| Operation | Who | What the transaction does |
|---|---|---|
| `create` | any account (5 a day) | `groups/{gid}`, creator as administrator, `groupRefs` |
| `invite(uid, devices, epoch, commit, welcome, packages)` | any member's device | needs an accepted 1:1 chat between the two; refused if either has blocked the other; at most 20 pending per recipient. Checks `epoch`, consumes the packages, writes the Commit and the Welcome, records the account in `invited`, and raises `epoch`, all at once |
| `accept` | the invitee | moves the account from `invited` to `members`, writes `groupRefs` with `joinedAt`. No Commit |
| `decline`, `expire(uid)` | the invitee; any member after 7 days | removes the account from `invited` and fences its devices |
| `roles(admins, epoch, commit)` | administrator | the Commit carrying the new list; sets each member's `role` |
| `addDevice(device, …)` | the same account's other device | the same, for a newly linked device |
| `remove(uid, epoch, commit)` | administrator | removes every leaf of that account |
| `leave` | a member | removes it from `members` and `groupRefs` at once (it can no longer read) and adds its leaves to `fence` |
| `finalize(epoch, commit)` | any remaining member | the Commit removing every fenced leaf; clears `fence` |

Two more triggers set fences without the app's help:
- **Account deletion:** the profile turns `deleting`. This covers old apps and
  `fp-ops delete`, and needs no change to the deletion flow (0048).
- **Device removal:** a device document is deleted.

Each fences at most 32 groups and removes the account (or device) from `members`.
While a group has a fence, it accepts no new messages until a remaining member
finalises the removal. MLS can't be advanced by the server.

A trigger on `events` creation sends a generic **New message** to the other members'
devices, rechecking fences, as `pushOnMessage` does.

## 3. App

- **Payloads.** Group application messages carry the existing v1–v3 JSON (text,
  quote, reaction, edit, delete), unchanged. The sender comes from the MLS leaf, never
  the payload. A new v4 `group_invite` payload (`gid`, name, inviter) travels over the
  existing 1:1 channel.
- **Model** (`lib/src/model/groups/`):
  - `GroupService` per account: listens to `groupRefs`, then per open group to
    `commits` (in epoch order) and `events` (by `at`).
  - Each event is processed after the Commits it depends on, under the shared
    account lock and receive journal.
  - `GroupSendController` reuses the outbox, unknown-outcome and send-window
    behaviour of 1:1 sends.
- **Chat list.** A sealed `ChatListEntry` (`DirectChat | GroupChat`). A group's
  last-activity time and preview come from local history only; the server bumps
  nothing per message.
- **History.** A group's messages live in the existing encrypted store under
  `group:{gid}`. `peerOf` is never called on it.
- **No receipts, ticks, typing or presence**, as everywhere.

## 4. Screens (owner's choices, 2026-11-14)

- **Starting a group.** *New chat* opens a small choice: *Message someone* or *New
  group*. *New group* asks for a name (up to 40 characters) and lets you tick people
  from your accepted chats, at most 15 besides you, then *Create group*. The people
  are invited, not added: each joins when they accept.
- **In the chat list.** A group's avatar is its name's first letter in a circle,
  like a person's (the first version used a rounded square; the owner changed it in
  the emulator test). The preview
  names the sender: *Mira: See you at 7?* A group you've been invited to doesn't
  appear until you join.
- **Invitations** show in both places:
  - as a card in the 1:1 chat with the person who invited you (*Rowan invited you to
    Book club · 4 people*, with **Join** and **Decline**);
  - as a line in *Message requests* until you decide.

  Declining tells nobody. Blocked people can't invite you.
- **In the conversation.** Each run of messages from one person has their name above
  the first bubble and a small avatar beside the last. The header shows the group
  name and the number of people. Tapping it opens *Group info*:
  - the members and who are administrators;
  - for everyone: *Add people* (from your 1:1 contacts) and *Leave*;
  - for administrators also: *Rename* and *Remove*.
- **Message actions.** Hold a message: react (anyone); *Edit* and *Delete for
  everyone* (your own messages only; every member's phone applies them only from the
  author); *Delete for me* (any message, this phone only).
- **Colours.**
  - **Your** messages use your primary chat colour, as in 1:1 chats.
  - **Each other member's** messages use the secondary (soft) version of *their own*
    primary colour, with their name and avatar in that colour's text shade. If Mira
    chose Plum, everyone sees her bubbles in the plum tint.
  - A member's colour is shared only inside the group, as an encrypted `profile`
    message (`type: profile, color`) sent on joining and whenever they change it. The
    server never stores it, and 1:1 chats are unchanged. A newcomer's is marked
    `hello: true`, and each member answers it with their own.
  - `type: notice` messages (`kind: left`, or `kind: removing, uid` from an
    administrator) say why a removal is about to happen, for the line it shows.
  - A member whose colour hasn't arrived yet shows in Stone.
- **System lines**, small and centred: *Rowan added Mira*, *Elliot left*, *Rowan
  renamed the group*. They come from the authenticated Commits, never from the
  server's roster.
- **Notifications** say *New message* for groups until previews are measured on the
  iPhone (0050).

## 5. Cost

| | Writes | Reads at send | Functions |
|---|---|---|---|
| Message | 2 (event, send clock) | about 3 rule reads | ≤1 push |
| Self-update | 2 (Commit, group epoch) | about 3 | none |
| Add an account | about 8 + its packages | about 10 | 1 trigger |

Receiving costs one read per listening device per event, plus reconnects. 1,000
messages a day in a ten-account group with two devices each is about 2,000 writes,
3,000 rule reads and 20,000 delivery reads.

## 6. Order of work

1. **Contract.** This document; `group_crypto.dart` and `FakeGroupCrypto`. The Rust
   core starts the real implementation (GPT).
2. **Backend.** Rules, the function and triggers, emulator tests, `fp-ops group`.
3. **App model.** `GroupService` against the fake, extending the chat simulation
   to groups.
4. **App screens** behind `GROUPS_FAKE`, for the owner to try on an emulator.
5. **Real core.** Swap the fake for the core. Release gates in 0050.

AI assistance: Claude Code.
