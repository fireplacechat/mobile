# 0050: Group chats: profile, delivery and limits

Date: 2026-11-14, amended the same day (*Changes after the first emulator test*,
below). Status: **decisions
accepted by the owner; implementation gated** (see the end). Develops [0036](0036-groups-use-mls.md). The full proposal, written
with GPT, is [protocol/group-chat-design.md](../protocol/group-chat-design.md); this
note records the owner's choices and **amends the proposal's delivery path**. Where
they differ, this note wins.

The interfaces, Firestore schema, rules, function and screens are specified in
[protocol/group-chats-v1.md](../protocol/group-chats-v1.md).

## Owner decisions (2026-11-14)

| Question | Decision |
|---|---|
| MLS suite | `MLS_128_MLKEM768X25519_AES256GCM_SHA384_Ed25519` (draft-ietf-mls-pq-ciphersuites-07, `0x0011`) |
| Delivery | Messages and Commits written directly under Firestore rules; one small function only for membership changes and revocation fences |
| Size | 16 accounts, 4 participating devices each (64 leaves), 32 groups per account |
| Dependency | OpenMLS 0.9.2 with openmls_rust_crypto 0.6.0 approved **for a spike only**; production use needs a second approval |

### Who may do what (owner, 2026-11-14)

| Action | Who |
|---|---|
| Create a group | anyone (5 a day; at most 32 groups per account) |
| Invite someone | **any member**, but only a person they already have an accepted 1:1 chat with; the backend function checks this. The invitee must accept. |
| Add the invited person to MLS | the inviter's device, **when it sends the invitation** (amended; see below). Joining then needs no other phone. |
| Remove someone, change roles | administrators |
| Rename | administrators; other members' phones refuse anyone else's rename |
| Leave | anyone, at any time |
| Last administrator leaves | every remaining member becomes an administrator |
| End a group | no one ends it for others; it ends when its last member leaves, and the server then deletes all its records. Members keep their own copies of past messages. |
| Edit, delete for everyone | **only the message's author**, as in 1:1 chats (edits up to 10 times within 24 hours); the change shows on every member's phone |
| React | anyone |
| Delete for me | anyone, on their own phone only |

### What the suite means

- **Confidentiality is post-quantum:** every key exchange is hybrid X25519 + ML-KEM-768,
  as in 1:1 chats. Recorded group traffic stays safe against a future quantum computer.
- **Message authentication is classical:** members sign with Ed25519 only. An attacker
  with a quantum computer *at the time* could forge messages as an existing member.
  1:1 chats also sign with ML-DSA-65; groups do not.
- **Membership is still bound by the dual-signed account identity:** each device's MLS
  key is endorsed by the account's Ed25519 + ML-DSA-65 identity (proposal, *Identity
  and authentication*), so adding a forged *new* member still needs both signatures.
- Groups record their suite. Moving to an ML-DSA suite later means a new group, or a
  reviewed reinitialisation, with a visible notice; never a silent downgrade or upgrade.

## Delivery: rules first (amends the proposal)

The proposal sent every group write through one Cloud Function. That costs an invocation
and 10–12 reads per message, adds function latency to every send, loses Firestore's
offline write queue, and means reimplementing bans, challenges, the send window and the
deletion fence in Admin code. MLS does not need a total order for application messages,
only **one winning Commit per epoch**, and rules can enforce that with a create-only
document. So:

| Path | Written by | Rule |
|---|---|---|
| `groups/{gid}` | membership function; `epoch` also by a member's Commit batch | members `get`; roster, roles, `epoch`, `profile`, `fence` |
| `groups/{gid}/commits/{epoch}` | a member device, create-only | the id equals the group's current `epoch`; the same batch raises `groups/{gid}.epoch` by one and changes nothing else; no fence |
| `groups/{gid}/events/{opId}` | a member device, create-only | member, not fenced, `epoch` is the current epoch or the one before; the account's send clock is written in the same batch (one allowance shared with 1:1, decision 0028) |
| `groups/{gid}/welcomes/{uid}_{opId}` | membership function | readable by that account only |
| `users/{uid}/groupRefs/{gid}` | membership function | owner `list`; the account's groups |
| `users/{uid}/devices/{d}/mlsPackages/{ref}` | owner create; function consumes | bounded one-use KeyPackages |

- **Idempotency** comes from the document id: `opId` is `{deviceId}-{counter}`, so a
  repeated create is refused and the app reconciles by reading it back, never by
  resending (the same unknown-outcome rule as 1:1, decision 0032).
- **Only Commits that change no members** (self-updates, and renames carried in MLS)
  use the rules path. Adding, removing and leaving go through the function, which
  consumes KeyPackages, writes the Commit at the epoch slot, the Welcomes, the roster
  and both sides' `groupRefs` in one transaction. Every client still checks the staged
  Commit against the roster before merging; neither path is trusted cryptographically.
- **A bad Commit** from a member can occupy an epoch slot. Clients reject it and pause
  (proposal, *Event ordering*). The function may delete a slot that no client can
  merge, after an administrator removes the member who wrote it.
- **Fences.** Revoking a device, or deleting an account, sets `fence` on every group in
  the account's `groupRefs` (at most 32) in one function transaction, before devices or
  indexes are deleted. Account deletion (0048) calls this first, the way it now deletes
  invite rows (0049).
- **Push.** A trigger on `events` creation, like today's `pushOnMessage`, sends a
  generic alert to at most 64 devices, rechecking fences.

### Cost per ordinary message

| | Proposal (function) | This note (rules) |
|---|---|---|
| Writes | 4 | 2 (event, send clock) |
| Reads at send | 10–12 | about 3 rule reads (group, profile, clock) |
| Function invocations | 1 publish + ≤1 push | ≤1 push |
| Recipient reads | one per listening device | the same |

Membership changes cost more under either plan and are rare.

## Changes after the first emulator test (2026-11-14)

The owner tried groups on the Android emulator and asked for six changes. Backend
decision 0023 has the server side.

### Joining must not wait for the inviter's phone

MLS is end to end, so the server cannot add anyone: only a member's device can sign
the Add Commit and write the Welcome. The first version did that after the invitee
tapped Join, on the inviter's phone, while its app was open. In testing Join did
nothing until the inviter opened the app.

Now the **invitation does the Add**. The inviter's phone is online when it invites,
so it fetches a key package for each of the invitee's devices (up to four), and
sends the Commit, the Welcome and the packages it used in the same request.

- **Join** processes the Welcome the phone already has, so the group opens at once.
  The server then moves the account from *invited* into the roster, which is what
  lets the phone read and send.
- **Decline, or seven days without an answer:** the server fences the invited
  devices as it does for a leave, and any member's phone sends the removing Commit
  through `finalize`. The server has no scheduler, so the first member's phone to
  notice an invitation past its seven days asks for the expiry.
- **Declining stays quiet.** The group sees only that the person is no longer
  listed; nothing says whether they declined or the invitation ran out.
- **The trade-off.** From the invitation on, the invited devices are MLS members
  and hold the keys for messages sent afterwards, before the person accepts. The
  rules still refuse them everything but their own Welcome, and the app shows
  nothing from before they joined. The group chose to invite them, and *Group info*
  lists people who are **Invited**, apart from the members, so nobody is surprised.
- **Limits.** The 16 people and 64 devices count people who are invited.
- **Key packages run out:** the invitation is refused with "They need to open
  Fireplace before they can be invited." A device that had none, or is linked
  later, is added by the account's own device after it joins (`addDevice`; the
  server has it, the app does not send it yet).
- **A phone that was offline** when someone was invited and then declined still
  applies both Commits in order. It does not check an Add against the roster,
  because the roster it can read is today's, not the one at that epoch.

**Cost** (Blaze; all bounded by the 100 membership requests an account may make a
day):

| | Writes | Reads | Functions |
|---|---|---|---|
| An invitation | 5 + one delete per key package (≤4) | about 13 + one per device and package (≤8); the inviter's phone reads the invitee's device list and one package each (≤5) | 1 request, 1 push |
| Joining | 4 | 3 + the account's group list; the phone reads its Welcome | 1 request |
| Declining or an expiry | 3 | 4 | 1 request, then a `finalize` (4 writes, 5 reads, 1 request) |
| A newcomer's colours | one message from the newcomer and one from each member (≤16 messages, 2 writes each) | | ≤16 push triggers, throttled per person |
| A member applying a membership Commit | | 1 extra read of the roster | |

### Colours

Your own messages use your primary colour; every other member's use the soft tint
of **that member's** primary colour, and their name and avatar its text shade. The
colour travels only inside the group, as an encrypted `profile` message.

The first version sent a profile only on creating or joining a group or changing
the colour, so a later joiner never received the earlier members' colours and saw
them in Stone. Now a newcomer's profile is marked `hello`, and **every member
answers a `hello` with their own profile**, once. Colours are kept per group, and
avatars use them too.

### The start of the history

Someone who joins a group that already existed sees a quiet line above their first
message: *Messages sent before you joined aren’t shown.* The phone reads and shows
nothing from before the time the server recorded the join.

### The same look as 1:1 chats

The group row reuses the 1:1 row's layout (avatar size, bold name, date, two-line
preview, hairline). Its avatar is a **circle** with the group's initial, like a
person's: the owner changed this from the first version's rounded square after
seeing it on the emulator (2026-11-14). The conversation reuses the
1:1 bubble, held-message menu, reactions, day separators and composer, and editing
happens in the composer, not a dialog. The differences are the sender's name above
the first bubble of a run, their avatar beside the last, and the colours.

### Unread counts, lines and pushes

- **Unread count** on the group row, counted on the phone from the local history
  with the same per-chat record of what has been shown as 1:1 chats. No server
  field and no read receipt. Group messages count on the app icon's badge too.
- **Muting a group** works as for a 1:1 chat: hold the row, or use *Group info*.
  It is kept on the phone with the 1:1 mutes; the server and the other members
  are not told. A muted group keeps its count on the row, in grey, and is left
  out of the app icon's badge. Pushes are unchanged, as for a muted 1:1 chat.
- **Lines in the conversation**, small and centred: *alice added bob_jones*,
  *mira left*, *alice removed mira*, *alice made bob_jones an administrator*,
  *alice renamed the group*. They are built on the phone from the MLS state before
  and after each **authenticated Commit**, never from the server's roster.
  - A removal looks the same in MLS whether the person left or was removed. So a
    member who leaves first says so in an encrypted group message, and an
    administrator who removes someone says that; MLS vouches for the sender. With
    neither (a declined invitation, a deleted account) the line reads *… is no
    longer in the group*.
  - The lines are stored in the encrypted local history, are never counted as
    unread and are never matched by search.
- **Push when someone is invited:** one, to the invited person only (owner's
  choice), following their existing notification settings: *Fireplace / You were
  invited by alice.* when the sender's name is shown, *Fireplace / New Invitation*
  when it is hidden. The owner asked for the group's name as the title; the server
  never has it, so that waits for the phone to read the Welcome in the background
  (backend 0023).

### Administrators

In *Group info* an administrator taps a member for **Make administrator** or
**Remove as administrator**. It is an MLS Commit carrying the new list (group-context
extension `0xF0F1`) and the same list to the server (`roles`). Every phone refuses
a role change, like a rename, from someone who is not an administrator. Someone
invited cannot be made one until they join. If the last administrator leaves,
everyone left is one, as before.

### Tests

`test/model/groups/group_service_test.dart` (23, two and three phones on the real
Rust core): joining with the inviter's phone off, key packages run out, expiry,
decline, removing someone invited, colours for a later joiner, each line, roles,
and a refused role change. `test/view/groups/group_screens_test.dart` (11): the
1:1 menu and composer editing, colours of bubbles, names and avatars, the lines,
the start-of-history line, the unread count, muting, Make administrator, and
*Invited*.
`scripts/render/render_groups_test.dart` renders the screens for review.

### Not in this round

- The invitation card inside the 1:1 chat with the inviter (it shows in Message
  requests): [issue #164](https://github.com/fireplacechat/mobile/issues/164).
- `addDevice` from the app.
- The group's name in the invitation push.

## Spike results

[fireplace-crypto#3](https://github.com/fireplacechat/fireplace-crypto/pull/3)
measured the chosen suite with OpenMLS 0.9.2 (laptop, release build). At 64 devices:
Welcome 312 KiB, add-account Commit 101 KiB, self-update 49 KiB, remove-account Commit
77 KiB, member state 769 KiB; every operation took 13 ms or less. Every document
fits Firestore's 1 MiB limit without chunking. Ordinary messages have the same size as the
classical suite (about 146 bytes of overhead). OpenMLS adds about 3.2 MB of code and 183
crates, including older major versions of `aes-gcm`, `ed25519-dalek`, `x25519-dalek`
and `rand_core` than the core pins.

## Who builds what

- **Rust core** (`fireplace-crypto`): the group API behind the existing C ABI and the
  encrypted, journaled storage provider (proposal, *Local persistence*).
- **Backend:** the rules above, the membership function, the push trigger, `fp-ops`
  support and emulator tests.
- **App:** `model/groups/`, the group conversation type, invitations and screens.

The app and backend can be built against a fake of the core API, agreed first, while
the core work proceeds.

## Before release

1. An OpenMLS release using draft-07's final identifiers (0.9.2 still uses the
   provisional `0x004e` and the draft-06 X-Wing KEM). Groups created with provisional
   ids would all need reinitialising.
2. The owner's production approval of the dependency, after iOS arm64 size and
   memory measurements (especially for the notification extension, which keeps
   showing a generic alert for groups at first).
3. The storage-provider crash tests and fence proofs listed in the proposal.
4. A design review of the rules and the function, with emulator tests and measured
   costs, and an independent review of the integration.

AI assistance: Claude Code, building on the proposal written with GPT (OpenAI Codex).
