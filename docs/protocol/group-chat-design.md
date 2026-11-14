# Fireplace group chat design

Date: 2026-11-14. Status: **proposal**, implementing the direction in
[decision 0036](../decisions/0036-groups-use-mls.md). This is a design review,
not an implemented or audited group protocol.

> **Amended by [decision 0050](../decisions/0050-group-chats.md).** The owner chose the
> `MLS_128_MLKEM768X25519_AES256GCM_SHA384_Ed25519` suite, 16 accounts / 64 devices,
> and rules-first delivery: messages and Commits are written under Firestore rules,
> and a function handles only membership changes and fences. Where this proposal
> describes one publish endpoint for every event, 0050 applies.

## Recommendation

Use a maintained OpenMLS release inside `fireplace-crypto`, with one MLS
leaf for every participating device. Store each encrypted message once and
let authorized devices read it from an ordered Firestore log. Keep the
existing hybrid 1:1 protocol, account identities, local contact pins,
encrypted history and shared account lock.

Start with small private groups, explicit invitations and a thin delivery
service in the existing backend. Reuse Signal's separation of device
encryption, group state and delivery. Reproducing Signal's zero-knowledge
private-group infrastructure would be a separate project. Fireplace's
service will know group membership and roles; group names and content stay
encrypted.

The main release obstacle is the cryptographic profile. OpenMLS now offers
more post-quantum choices than 0036 records, but neither its name nor its
audit establishes compatibility with Fireplace's present guarantees. There
must be a reviewed suite/provider/version combination before groups ship.

## Existing design notes and code

The local canonical checkouts matched GitHub `main` during this review:

| Repository | Revision | Finding |
|---|---|---|
| `mobile` | `f5a3aca7b615f64eaab75bfba1ef19fe3a804d4c` | Flutter app; 1:1 assumptions throughout directory, send, receive and push |
| `backend` (private) | `361ce16ef8dd7d79ee8e9dea2e6bfe821636ef5d` | Canonical rules/functions, abuse controls, deletion and operator integration |
| `server` | `05ca305652e38865f49bdefa21b7463a881bd48e` | Public export of backend source `2a06f64af450937b021a2a4d78b8bef67d4acc7f`; not an independent delivery system |
| `fireplace-crypto` | `2cfd022d129e59ba50c104761fc9eca907087f7d` | Rust 0.1.1, current hybrid 1:1 protocol and C ABI; no MLS engine |

The useful notes are:

- [Architecture](../architecture.md): message and storage paths.
- [0036](../decisions/0036-groups-use-mls.md): accepted MLS direction,
  Firestore transport, post-quantum requirement and unresolved integration.
- [0002](../decisions/0002-handshake-v2-prekeys.md),
  [0003](../decisions/0003-hybrid-double-ratchet.md) and
  [0014](../decisions/0014-account-contact-trust.md): current identity,
  device certification, hybrid handshake/ratchet and local trust.
- [0034](../decisions/0034-encrypted-database.md): keep encrypted files;
  SQLCipher remains an alternative requiring separate approval.
- [0035](../decisions/0035-crypto-core-and-ios-extension.md),
  [0037](../decisions/0037-crypto-core-abi-and-test-stream.md) and
  [0040](../decisions/0040-app-crypto-backend-seam.md): shared native core.
- [0042](../decisions/0042-ios-shared-preview-storage.md) and
  [0043](../decisions/0043-ios-notification-service.md): shared locking and
  the iOS extension's bounded, non-persisting preview path.
- [Feature matrix](../roadmap/feature-matrix.md),
  [chat UI plans](../roadmap/chat-ui-features.md) and
  [threat model](threat-model.md): groups are outside today's implemented
  feature set. This proposal does not change release scheduling.

`ChatDirectory.chatIdFor` and `peerOf` encode two UIDs in a chat ID.
`encryptForDevices` makes a separate envelope for every peer device and
every other local-account device. Current rules require exactly two
participants and at most 40 envelope entries. `push-core.js` derives one
recipient from that two-person ID. These paths cannot become group-aware
just by increasing a participant limit.

The public `server` export omits private operational material and replaces
the spam policy. Implement backend changes in the canonical private repo,
then export their public parts through its existing review workflow. This
proposal does not copy private policy thresholds into public documentation.

## What Signal provides and what Fireplace should copy

The inspected libsignal revision is
`8be00c282001caa3585d18de0f044c6d500348ab`.
Its [group cipher](https://github.com/signalapp/libsignal/blob/8be00c282001caa3585d18de0f044c6d500348ab/rust/protocol/src/group_cipher.rs)
uses a sender's chain and signing key to produce a signed group ciphertext.
The chain advances after encryption; receiving checks signatures and bounds
skipped generations. Its distribution API supplies the material recipients
need. This is a sender-key design, not MLS.

Signal's [private-group system](https://signal.org/blog/signal-private-group-system/)
addresses a different problem: server-side group administration without a
plaintext membership list. Libsignal's `zkgroup` and credential components
support that system. The app and service still have to handle distribution,
membership lifecycle, delivery and persistence. Libsignal is not a complete
group-chat backend, and its [README](https://github.com/signalapp/libsignal/blob/8be00c282001caa3585d18de0f044c6d500348ab/README.md)
does not support third-party use.

| Approach | Reuses existing work | New responsibilities | Assessment |
|---|---|---|---|
| Pairwise encryption to every device | Current ratchets | Group agreement, authorization, changes and recovery | Easy message prototype; poor long-term group design |
| Fireplace sender-key scheme | Current pairwise channels for distribution | Distribution tracking, rekeys, removals, recovery and security analysis | Avoid maintaining a second custom protocol |
| Adopt libsignal | Signal primitives | Protocol/identity migration, bindings, service and lifecycle integration | Does not fit this task's existing-encryption constraint |
| OpenMLS in the Rust core | Identity/trust, storage, FFI and transport | Credential validation, ordering, policy and delivery | Recommended, subject to the profile review below |

Copy the architectural lessons: encrypt content once, identify devices
explicitly, authenticate state changes, bound reordering and keep cryptographic
state crash-safe. MLS replaces sender-key distribution with standardized
group key management. It does not remove the recipient delivery cost.

## Cryptographic profile and dependency review

### Version baseline

Evaluate **[`openmls = 0.9.2`](https://crates.io/crates/openmls/0.9.2)** and
**`openmls_rust_crypto = 0.6.0`**, with exact
versions and a reviewed dependency lock before an integration build. The
published OpenMLS 0.9.2 crate identifies source commit
`8a8f83b4b61fc45f28facec25e914992b3465de6`. The upstream working tree reviewed
was `6100df3fb1d8c3eeab53e349fcbd621f98c44fe2`; it is not a production pin.

GitHub's latest-release endpoint still reports 0.9.0, whereas the crates.io
registry publishes 0.9.2. Do not select a version from that label alone.
The following published advisories make 0.9.0 unsuitable:

- [GHSA-gc79-23g3-8g52](https://github.com/openmls/openmls/security/advisories/GHSA-gc79-23g3-8g52):
  nested-extension decoding can abort a process; the 0.9 fix starts at 0.9.1.
- [GHSA-94v4-rg25-x625](https://github.com/openmls/openmls/security/advisories/GHSA-94v4-rg25-x625):
  external commits can retain a removed leaf; fixed in 0.9.2.
- [GHSA-p276-g3f3-wwgh](https://github.com/openmls/openmls/security/advisories/GHSA-p276-g3f3-wwgh):
  rejected private messages can change a sender ratchet; fixed in 0.9.2.

OpenMLS's [audit announcement](https://blog.openmls.tech/posts/2026-05-27-independent-audit/)
describes eight findings and one Low finding still outstanding at announcement
time. The [report](https://blog.openmls.tech/SRL-OpenMLS_security_assurance_assessment.pdf)
identifies that finding as S1-3, inconsistent in-memory and stored state after
storage failures. Crypto and storage providers were outside the assessment's
scope. The audit is useful evidence, not an audit of Fireplace, its provider
selection or newer post-quantum additions. Recheck advisories and S1-3 against
the exact selected source; the transaction design below must handle failures
even if upstream changes its behavior.

OpenMLS and its provider crates are MIT licensed. Start the spike with the
released RustCrypto provider because Fireplace already uses RustCrypto
primitives. Reuse does not mean identical dependency versions: the published
provider uses older `aes-gcm` and `ed25519-dalek` major versions than Fireplace.
Measure duplicate dependencies, binary size, iPhone memory and execution time.
Compare libcrux when the released provider's supported profile or measurements
justify it. Do not copy support claims from upstream `main` to a released crate.

### Post-quantum choices

[The IETF draft](https://datatracker.ietf.org/doc/html/draft-ietf-mls-pq-ciphersuites-07)
is version **07, dated 2026-11-01**, submitted for publication and still an
Internet-Draft. The March/version-04 description in 0036 is stale. The draft
now includes suites with post-quantum signatures as well as hybrid KEMs.

| Candidate | Key exchange | MLS signatures | Difference from Fireplace today |
|---|---|---|---|
| `MLS_128_MLKEM768X25519_CHACHA20POLY1305_SHA384_MLDSA44` | ML-KEM-768 + X25519 | ML-DSA-44 | Best hybrid/PQ-authentication candidate to evaluate; no Ed25519 component and a different ML-DSA level |
| `MLS_192_MLKEM768_AES256GCM_SHA384_MLDSA65` | ML-KEM-768 | ML-DSA-65 | Keeps the ML-DSA level; loses the classical KEM hedge and dual signatures |
| Hybrid KEM with Ed25519 | ML-KEM-768 + X25519 | Ed25519 | Passive post-quantum confidentiality, classical authentication only |
| Base RFC 9420 suite | X25519 | Ed25519 | Useful interoperability fixture; fails the production PQ requirement |

Use the first row as the **evaluation preference**, not a production decision.
It offers hybrid confidentiality and PQ signatures using upstream algorithms,
but does not reproduce today's exact dual-signature construction. An
account-signed credential cannot upgrade every subsequent MLS signature to
Ed25519 plus ML-DSA-65. If exact parity is required, keep production groups
blocked pending an appropriate maintained upstream profile. Do not create an
ad hoc combiner or label a classical fallback post-quantum.

There is also a concrete interoperability gap. Released traits 0.6.0 assign
the first candidate provisional suite ID `0x0052` and X-Wing KEM ID `0x004D`.
Draft 07 uses suite ID `0x0020` and KEM ID `0x647a`. Upstream `main` has already
changed KEM definitions and derivation behavior relative to released providers.
Matching algorithm names is insufficient: compare code points, KDFs, key
encodings, domain labels and deterministic key derivation against the exact
draft and cross-implementation vectors. Wait for a suitable upstream release
or review an explicit upstream-supported compatibility profile; do not patch
numeric identifiers alone.

Each group has a fixed profile identifier covering wire version, suite,
provider compatibility and application policy. A join must advertise and
support that exact profile. Unsupported devices show an update requirement;
they are never silently omitted from an already accepted membership.
Profile changes require a reviewed MLS reinitialization/migration procedure
or a new group, with a visible security notice.

## First version of the product

Proposed initial limits are **16 accounts, four participating devices per
account, 64 leaves, and 32 joined groups per account**. These are conservative
application limits to validate in a spike, not MLS limits. Accounts with more
devices explicitly choose participating devices; a device outside the group
cannot receive its content. An invited device must support the group profile.

Support text, replies, edits, reactions, local search/unread state,
administrators, rename, invite, accept/decline, remove and leave. The creator
starts as administrator; administrators add/remove accounts and change roles
or the name. Members may add their own certified devices and request their
own departure. Preserve at least one administrator while other accounts
remain; transfer administration or close the group when the last account leaves.

Use explicit acceptance before adding an account. Initially invite only
through an accepted 1:1 contact; the invitation is an encrypted control payload
with an opaque, expiring handle. No public links, directory or unsolicited
group history. An acceptance authorizes one group and profile, not arbitrary
future invitations.

Keep the existing 16,384-Unicode-character message limit. Edits/deletes refer
to an authenticated event ID; only the original author's account may mutate
its message. Quotes are untrusted quoted content, never evidence of another
member's authorship. New accounts and newly added devices begin at their
Welcome epoch with empty old history. There is no export of old epoch secrets
or automatic history sync.

No receipts, delivery ticks, typing or presence. Server acceptance is an
internal protocol result and must not appear as a recipient-delivery receipt.
Blocking someone still prevents direct contact and invitations; sharing a
group does not stop that member decrypting group messages. Explain this when
blocking a fellow member and offer to leave or ask an administrator to remove
them. Reports remain IDs only. Muting is local, with recipient push preferences
used only to avoid unnecessary alerts.

## Identity and authentication

One device is one MLS leaf. Never share a leaf's signing key, ratchets or
snapshot between devices. Multiple devices of the same account get distinct
leaf keys and agree on the same account identity. The sender's other admitted
devices decrypt the common ciphertext themselves.

Generate fresh MLS signing and HPKE/init keys. The existing device certificate
binds UID, device ID, X25519 and ML-KEM public keys; it does **not** bind an MLS
signing key. Add a separately versioned, domain-separated account endorsement
covering UID, device ID, existing device-certificate hash, MLS signature
algorithm/public key, profile and certificate validity/generation. Verify
both existing account-signature components. Keep the account's long-term
signing keys out of the MLS signer API.

An MLS BasicCredential can carry the canonical public binding and certificate
references. It is not self-authenticating identity assurance. On every Add,
Welcome and key change, Fireplace must verify the endorsement, current device
status, identity pin, uniqueness of `(uid, deviceId)` and the actual leaf key.
Use one canonical encoding with published cross-language fixtures.

Before creating or approving a changed group, compare all known identities
with account-scoped pins. First contact remains TOFU and visibly unverified.
Pause sends on an identity change; an administrator cannot silently accept a
changed identity on everybody's behalf. Keep the existing pairwise safety
numbers. A separate group verification value may identify the group instance,
profile, epoch and canonical roster, but does not replace verifying members.

Account identity secrets currently reach linked devices. Revoking a device
does not erase an identity key already copied to it. Recovery from compromise
of that key requires identity replacement, fresh verification and removal of
the old leaves; the normal device-revocation claim must remain narrower.

## Delivery service and Firestore schema

Use one authenticated HTTPS group-operation endpoint in the existing Cloud
Functions backend and Firestore for reads. The app can use `dart:io` HTTP
with its Firebase ID token and the configured App Check policy; no new Flutter
networking package is necessary. Do not weaken enforcement for this endpoint.
Unlike the native crypto library, the delivery service owns all server writes
for groups. Firestore rules deny client mutations to those collections.

This adds one function invocation per publish. In return, one transaction
enforces ordering, quotas, reverse membership indexes, idempotency and
revocation fences. Direct client writes would need to prove all those
cross-document invariants in security rules, including that one send-clock
increment cannot authorize a batch of group messages. That approach can be
revisited if measured function cost warrants its additional complexity.

The endpoint receives ciphertext and public control metadata only. It has no
MLS group state or decryption keys and does not generate Commits or Welcomes.
It is an ordering/access service, not a trusted cryptographic authority. It
must explicitly enforce bans, deletion fences, challenges and quotas because
Admin SDK writes bypass security rules.

Proposed collections, with fresh random group IDs:

| Path | Purpose and readable data |
|---|---|
| `groups/{gid}` | Current public membership/roles, admitted-device references, profile, epoch, roster revision and removal fence; members only |
| `groups/{gid}/head/current` | Sequence counter, latest control-event reference, per-group budgets; no directory listener |
| `groups/{gid}/events/{opId}` | Immutable `seq`, kind, epoch, claimed sender/device, ciphertext, public control manifest when applicable, server timestamps and expiry |
| `users/{uid}/groupRefs/{gid}` | Server-maintained membership/discovery reference and join sequence; no message text, unread count or per-message bump |
| `users/{uid}/groupInvites/{inviteId}` | Bounded, expiring invitation/acceptance state; target and inviter access only |
| `users/{uid}/groupWelcomes/{opId}` | Target-device Welcome ciphertexts and join boundary; readable by that account |
| `users/{uid}/devices/{did}/mlsPackages/{ref}` | Bounded one-use public KeyPackages; no private init keys |
| `users/{uid}/devices/{did}/groupPublishState/current` | Server-only monotonic operation counter; cannot be reset by client registration or device-document updates |

An ordinary event does not update every member's `groupRefs` or rewrite the
roster. Listen to the event log once per group/device and feed local history
and the chat list from that shared stream. Separating the changing head from
the roster avoids reevaluating every access rule merely because a counter
advanced. Listener reconnects and dependent rule reads still cost money.

Reads require a live, non-deleting account and current membership. Queries
must start at the account's join boundary; rules are not filters. Firebase
Auth identifies accounts, not individual device key possession. Device-specific
Welcome encryption and MLS authentication supply the cryptographic device
boundary. A revoked device with an old account token must not be described as
unable to download all ciphertext the account can still read.

### Event ordering and publication

Use one total server sequence for application and control events in a small
group. An application event references an epoch and roster revision; a Commit
references its predecessor epoch/control hash and the resulting roster.
Only control events change the MLS epoch. This serializes a group on one head
document, which is acceptable only with the proposed low traffic limits and
contention measurements. Do not claim MLS requires this extra application order.

1. The app catches up to the last control event, validates identities and
   prepares the operation under the shared account lock.
2. It generates a stable operation ID and device operation counter, encrypts
   once, and durably saves the advanced local state and exact ciphertext in
   the outbox **before** making a request.
3. The endpoint checks authentication and public authorization. Its transaction
   reads the group/head, existing event, active sender device, account policy
   and shared send clock. It rejects stale epochs or fences, assigns `seq + 1`,
   and atomically writes the event, head, send clock and device operation
   high-water mark. An unchanged-epoch message need not require the exact
   previous application sequence; other senders may publish in between.
4. The app records server acceptance locally and completes the outbox. A
   Commit stays pending until the accepted event is validated and merged.
   A Welcome is published in the same membership transaction, never before
   its Commit wins.

Bind the stable operation ID and public control-manifest hash into MLS
authenticated data. Validate envelope group ID, profile, epoch and sender
against the decrypted/authenticated MLS content. The assigned server sequence
is a delivery order, not something the sender signs in advance. A malicious
service can withhold or reorder traffic; it must not be able to forge an MLS
membership change or author.

Store an event at the stable operation ID. A repeat with the same sender,
counter and ciphertext hash returns its existing result without another send
charge or event. A different body under that ID is refused. After TTL removes
the event, the persistent per-device high-water mark refuses reuse of old
operation counters. Keep that counter across sign-out/recovery of the same
device; losing it requires a fresh device identity and admission. Counter
gaps are allowed. This prevents retention expiry from turning an old publish
request into a new message.

Transaction callback retries must reuse those exact bytes and contain no
encryption, randomness, external calls or push sends. Bound retry attempts.
A known concurrency refusal allows a pending Commit to be discarded, the
winning Commit processed, and a **new** operation prepared. Burn already used
handshake generations. Do not restore a snapshot after encrypted bytes have
left the device merely because the service refused them.

For a timeout or lost response, keep the advanced state and outbox, show the
existing uncertain-send state, and perform bounded read-only reconciliation
by operation ID. Do not automatically resend an ambiguous operation. A
user-requested retry uses the saved bytes and ID while that operation remains
valid; an explicit resend after rekeying is a new operation with a visible
duplicate risk if the old result cannot be established.

The receiver drains sequence pages in order. It processes all earlier control
events before a later epoch and stops at a missing required Commit. A duplicate
accepted operation has no local effect. Invalid MLS content cannot change live
state. Every event references its latest preceding authenticated control hash
and policy revision. A sequence gap caused by expired or account-deleted
application events can be recorded as missing history only when the next
event still matches the locally verified control state. A missing control
reference requires catch-up or rejoin, even when its MLS epoch is unchanged.
Do not let an absent rename/role event silently preserve an obsolete policy.
Because the endpoint cannot inspect private MLS content, a malicious
authorized uploader can submit an unusable Commit: clients must pause on a
roster/MLS mismatch. This is an availability failure, never grounds for trusting
the server roster or importing server-provided secrets.

### Membership, invites and removal

An administrator obtains the invitee's accepted authorization and one-use
KeyPackages, then prepares an Add Commit and Welcomes. The endpoint transaction
consumes exactly those packages, checks limits/roles and atomically updates
membership, join boundaries, both sides' indexes, the Commit and Welcome
records. A competing use of the same KeyPackage loses. Retain the private init
key until its corresponding Welcome is safely processed or its pending
lifetime expires; never recycle a published/consumed package for another Add.
Propose ten available packages per participating device with a seven-day
lifetime; cap replenishment and claims independently of text sends.

Add at most one account (up to four leaves) per transaction. Bound the total
serialized request and transaction, including all Welcomes, below Firestore's
transaction limit; propose a 4 MiB operation-body cap. Keep the public roster
document below 64 KiB by storing certificate references rather than repeating
whole certificates. This also bounds a 32-group revocation transaction.

Use encrypted MLS handshake messages where supported by the chosen profile.
For backend authorization, each control event also has a public manifest of
account/device/role changes. Bind its canonical hash into the authenticated
MLS event. Clients derive the actual resulting roster from the staged Commit,
check it against the manifest and previous roles, and only then merge. Role
or name changes that do not change leaves still need an authenticated group
control event. Include an UpdatePath in accepted membership-change commits
so new entropy and removal behavior are deliberate.

A member may request departure; another remaining member commits its Remove.
A device must not try to commit removal of its own leaf. Removing an account
means removing **all** its leaves. Administrators authorize account removals;
members may manage only their own certified device additions/removals. An
authorized remaining member may finalize a previously authorized departure
or revocation even if administrators are offline. Last-member departure
closes the group without requiring a nonexistent remaining committer.

Delegated completion needs signed evidence of the original authorized intent:
the departing member's leaf signature, an administrator's removal authorization,
or the account's dual-signed device-revocation statement. Bind the group/device
targets, profile, current control state and a one-use intent ID. Every client
checks that evidence and the actual resulting tree. A server fence or Firebase
login alone is not cryptographic authorization to bypass administrator rules.
If account cleanup or an operator action cannot supply that evidence, the
service can revoke access and pause delivery; a remaining administrator must
authorize the cryptographic removal.

Leave/removal first sets a delivery fence and revokes the departing account's
read/write ACL. Device revocation/account deletion uses the canonical reverse
group index to fence every affected group and block new application events
until a remaining client commits the required removals. The fence and device
revocation must be one atomic backend operation over the bounded 32 groups;
an eventual background trigger is insufficient. Old direct revocation paths
must be adapted to enter the same fence protocol. Account deletion must fence
groups before deleting its device records or reverse index, and be resumable.
The current deletion work is left untouched by this proposal.

Only a Commit that removes all currently fenced leaves may clear the fence.
An ordinary role/name change or competing Add cannot clear it. If nobody
remaining is online, the group waits. The backend cannot manufacture the
new epoch. New messages become cryptographically inaccessible to removed
members after that valid removal Commit; old messages/keys and copies already
held by members cannot be recalled. Device revocation cannot undo compromise
of the account identity signing key.

## Local persistence and the native interface

OpenMLS writes through a StorageProvider throughout an operation; saving one
`MlsGroup` object at the end is insufficient. Implement a small authenticated,
encrypted provider adapter in the Rust integration. Each operation works on a
private copy/overlay of the complete provider records for that local group,
including epoch keys, ratchets, pending proposals/commit, credentials and
KeyPackage lifecycle changes. The default memory provider is not durable
production storage, and its example plaintext persistence is unsuitable.

Protect provider files and journals with AES-256-GCM and fresh nonces, using
a random account-scoped MLS storage master key under the existing Keychain
and passphrase-lock policy. Derive per-device/group storage keys with labeled
HKDF; authenticate UID, device ID, group ID, format and generation as AAD.
Use a self-describing, versioned record encoding, with explicit migrations
for OpenMLS storage changes. Do not export this key in account recovery
backups or use any handshake, MLS epoch or 1:1 ratchet key for file encryption.

Under the existing isolate gate and account file lock, stage the operation,
then write an encrypted journal containing the new provider state, outbox or
received event, history change and cursor. Commit by an atomic replacement
with a versioned, crash-tested recovery procedure. Only after durable success
may the new live handle replace the old one or a publish start. On any storage
failure, discard/reload the staged handle; never keep a partially mutated live
object. Recover the journal before the next group operation. Reuse the current
journal's ordering principles, not its 1:1 snapshot schema.

Do not retain arbitrary old snapshots of group secrets. Complete and erase
journals/old encrypted generations promptly; bound the keys retained for
delayed messages. File deletion cannot promise forensic erasure on flash, so
describe forward secrecy relative to the keys and history retained on-device.
Message history is intentionally retained and remains readable after a later
device unlock/compromise according to the local-storage threat model.

Add explicit group handles/operations behind the existing C ABI pattern:
generate/validate KeyPackage, create, stage/join Welcome, prepare application
message, process event, inspect staged membership, authorize/merge Commit,
save transaction and destroy. These are proposed capabilities, not functions
already exported by version 0.1.1. Keep the current 1:1 APIs and wire bytes.
Bound input/output allocations, wipe returned buffers with `fp_free`, and
retain transient failure budgets in live handles.

Use `model/groups/` for delivery, policy and controllers, and a distinct group
conversation type. Reuse payload/history/rendering primitives where their
semantics match. Do not send group IDs through `peerOf` or duplicate all of
`ChatService`. Extend startup, sync coordination, local search and account
cleanup to own and close group resources explicitly.

## Offline clients and notifications

Keep a server log for about 30 days. Use a distinct event collection/TTL policy
so group control retention is explicit. Every ciphertext-bearing event has a
bounded lifetime; minimal roster/head/index metadata persists while the group
exists. Welcomes and invitations expire too. Removing old server ciphertext
does not delete local history.

A device that has the last epoch can receive messages after a long absence.
A device that missed a required Commit needs that authenticated chain. If the
chain or Welcome has expired, another admitted device must remove its stale
leaf and add a fresh one using a new KeyPackage. Keep its old local history,
mark the gap and do not fetch a full secret-state backup from the server.
First version disables external joins/commits and unconstrained resumption.
Read-only exports of GroupInfo cannot authorize a new device by themselves.

Process catch-up in pages of at most 50 events, with bounded work and a
persisted cursor between pages. Use ten events per notification attempt.
Reject sizes before allocation/decoding. Initial proposed encoded limits are
96 KiB for an application event, 768 KiB for a control/Welcome document and
8 MiB of local provider state per group. Measure PQ tree/certificate overhead
at 64 leaves before freezing these caps; lower the group limit if the profile
cannot fit one Firestore document. No implicit chunking of a Commit.

The iOS extension remains a read-only preview consumer. Initially use generic
group notifications. Later it may decrypt from a copied, already-current
group state only; missing commits, pending journals, lock contention, unknown
credentials or budgets produce `New Message`. It must not pin identities,
join, merge, advance durable ratchets or catch up an unbounded tree. Notification
processing must not suppress the app's eventual history ingestion. Measure on
the iPhone X before enabling MLS previews; preserve the existing deadline and
memory limits. Android background receive uses the same durable group path
as the foreground app under the shared lock.

Keep only the group handles needed for current work in memory, with a bounded
cache. The per-group disk cap is not permission to load all 32 groups at once.

## Post-compromise recovery

Each participating device performs a fresh self-update when it returns to
active use if its last successful update is over 24 hours old, before its
next application send. Coalesce updates with necessary membership work,
but every device must eventually update its own leaf. No timer wakes idle
phones, and text messages do not force an epoch change individually.

MLS recovery depends on which secrets were compromised and fresh updates
from affected, now-clean clients; another member's arbitrary commit is not
a universal recovery event. A stolen live account signing identity requires
identity replacement as described above. A permanently offline compromised
leaf must be removed. Past-epoch retention extends exposure, so total-order
processing starts with zero retained past application epochs, subject to
testing around pending/own messages and the exact OpenMLS APIs. Large unexplained
generation jumps trigger bounded recovery rather than unbounded ratchet work.

## Cost and abuse controls

MLS makes message encryption and stored ciphertext independent of the
recipient count. Device reads, listener authorization checks, initial tree
transfer and pushes still grow with membership. Tree updates commonly have
logarithmic paths, but sparse trees, certificates, Welcome bundles and
membership-index writes prevent a blanket logarithmic total-cost claim.

For an ordinary publish without retries, budget **four writes**: event, head,
shared send clock and device operation high-water mark. Budget **10–12 backend
reads** for membership/head, idempotency, sender/device and policy checks;
the implementation must enumerate and measure them. A new membership
transaction adds package consumption, Welcome, roster and index operations.
No recipient-inbox or per-member chat-list writes occur per text message.

Let `D` be participating listener devices and `N` account recipients. A useful
initial model is:

```text
reads/message = backend publish reads + D event reads
              + dependent rule reads + bounded push lookups
              + optional preview reads + reconnect/catch-up overhead
writes/message = 4 + at most N recipient push-throttle writes
function invocations/message <= 2 (publish + one group push trigger)
eventual TTL deletes/message = 1
```

Actual billed recipient reads occur when devices connect, not necessarily at
send time. Rules can bill dependent reads; do not assume perfect cache reuse.
Use the [Firestore billing rules](https://firebase.google.com/docs/firestore/pricing)
for listeners, empty queries, indexes and reconnects. **TTL deletes do not
receive the free delete quota**; the older backend cost note says otherwise.
Count storage, index overhead and egress separately, and exclude ciphertext,
certificate blobs and expiry fields from unnecessary indexes.

As an operation-count example, 1,000 daily messages in a ten-account group
with two participating devices each produce 20,000 event reads, about
10,000–12,000 publish reads, 4,000 publish writes and 1,000 eventual TTL
deletes, before rules, pushes, previews or reconnects. This is already
30,000–32,000 reads before those extras; it is not a promise to remain free.
At the 64-device cap, event reads alone would be 64,000. Use current regional
prices when the spike is reviewed rather than treating the existing cost
note's dollar figures as a quote.

Proposed policy limits:

- Preserve the shared account allowance across DMs and group events: at most
  20 sends per ten seconds and the existing daily policy, with reactions and
  ordinary control events counted. Existing restriction/challenge decisions remain
  authoritative. No separate per-group allowance multiplies an account cap.
- Cap each group at 20 publish events per ten seconds and 2,000 per day,
  with a separate emergency allowance for authenticated required removals so
  exhausted account or group text quotas cannot prevent rekeying. Propose at
  most four emergency operations per ten seconds and eight per day, per
  account and per group. This narrowly scoped exception needs explicit cost
  review; it cannot carry text, invites, renames or arbitrary self-updates.
- Allow at most five group creations and 20 invitation attempts per account
  per day, with at most 20 pending invites per recipient. Retrying an existing
  invite does not create a second one. Honor blocks before notification.
- Maintain the 16-account/64-device/32-group caps server-side. Bound rejected
  operation sizes, retries, package replenishment and function concurrency.
  Rate-limit request admission as well as successful writes: rejected function
  invocations can still cost money.

Run one push handler per newly accepted application event, not per recipient.
It rechecks live recipients and sends to at most 64 admitted devices using
bounded lookups and multicast. Recheck revocation and removal fences; a delayed
trigger may omit a notification but must not notify someone already removed.
Do not implement this as one recipient-trigger document per member. Use
recipient/conversation throttles so one member's activity does not silence
everyone else's alerts. Retries never recreate an event or multiply sends.

Push text is generic, with the existing opaque conversation key; no name,
roster, key, Welcome or ciphertext in FCM/APNs. A later locally decrypted
preview may show the encrypted group name. Start with no new server mute
collection; measure fan-out first. Function instance limits bound execution
concurrency, not the Firestore bill. Neither budgets nor these application
quotas provide a hard platform spending cap.

## Implementation sequence and acceptance tests

1. **Profile and dependency spike.** Inspect the exact 0.9.2 crate and provider
   dependency graph; check advisories/licences and the remaining storage
   finding. Resolve draft-07 compatibility and authentication policy. Run
   classical MLS interoperability fixtures and actual selected PQ KATs;
   compare another implementation/provider where available. Test two, 16 and
   64 device leaves. Measure wire sizes, persistent-state size, release binary
   growth, memory and latency on the target devices. This gate precedes a
   production dependency approval.
2. **Rust state and storage.** Implement isolated group APIs and encrypted
   provider transactions. Inject failure after every storage mutation,
   journal/rename, encryption, publish and local-history step. Restart a
   second process. Prove no key/nonce reuse, lost accepted event, duplicate
   history entry or state rollback. Invalid decrypt/signature/credential
   operations leave live memory and disk unchanged.
3. **Backend emulator and delivery.** Test every endpoint operation with
   real authentication/rules boundaries. Cover bans/challenges/deletion,
   forged roles, missing device proofs at the client layer, counters,
   replays after event TTL, shared DM/group quota races, duplicate function
   requests, joins and unauthorized reads. Prove clients cannot bypass the
   endpoint or directly modify the reverse index. Measure read/write counts,
   transaction contention and bounded retry behavior.
4. **Group simulation.** Extend the existing service-level simulation with
   devices offline, duplicate/out-of-order events, app/NSE overlap, concurrent
   Add/Remove/rename/self-update, two competing Commits, unknown publish
   outcomes, expired packages/Welcomes/commit chains, new devices and identity
   replacement. Test remove-one-account-with-four-leaves, last admin,
   self-departure, delete-during-send and revocation fence races. A removed
   device fails to decrypt after the valid removal epoch even if it obtains
   later ciphertext. An authorized member's invalid Commit pauses safely.
5. **Mobile feature and push.** Add invitation/admin/history flows behind the
   existing layer boundaries. Test Unicode limits and per-author mutations,
   local unread/search, block semantics and generic notifications. Preserve
   1:1 vectors and all existing app/backend checks. New group receipt UI is
   prohibited. MLS preview support follows device measurements separately.
6. **Review and rollout.** Obtain dependency/profile/product/cost approval,
   complete an independent review of the integration, then owner-deploy rules
   and functions before enabling compatible clients. Disable creation and
   new sends for rollback while retaining a compatible reader for existing
   encrypted groups. Never reinterpret existing groups through the 1:1
   protocol or downgrade their suite to recover availability.

The design can proceed to a bounded spike. Production remains contingent on
the profile compatibility/authentication choice, storage and fence proofs,
measured mobile/resource budgets and owner approval. None of those conditions
is satisfied merely by saving this proposal.

Design and source review assisted by OpenAI Codex.
