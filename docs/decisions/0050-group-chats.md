# 0050: Group chats: profile, delivery and limits

Date: 2026-11-14. Status: **decisions accepted by the owner; implementation gated**
(see the end). Develops [0036](0036-groups-use-mls.md). The full proposal, written
with GPT, is [protocol/group-chat-design.md](../protocol/group-chat-design.md); this
note records the owner's choices and **amends the proposal's delivery path**. Where
they differ, this note wins.

## Owner decisions (2026-11-14)

| Question | Decision |
|---|---|
| MLS suite | `MLS_128_MLKEM768X25519_AES256GCM_SHA384_Ed25519` (draft-ietf-mls-pq-ciphersuites-07, `0x0011`) |
| Delivery | Messages and Commits written directly under Firestore rules; one small function only for membership changes and revocation fences |
| Size | 16 accounts, 4 participating devices each (64 leaves), 32 groups per account |
| Dependency | OpenMLS 0.9.2 with openmls_rust_crypto 0.6.0 approved **for a spike only**; production use needs a second approval |

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
