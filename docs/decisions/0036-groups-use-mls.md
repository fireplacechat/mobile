# 0036: Group chats will use MLS

Status: **accepted in principle** (owner, 2026-11-13). Group chats are not
scheduled: the next release is the Rust core and iOS previews (0035), and
OpenMLS is **not** part of that work. This records the direction so nobody
designs a group protocol of our own meanwhile.

## Decision

Encrypted group conversations will use **Messaging Layer Security** (MLS,
RFC 9420), not a group protocol of Fireplace's own. **OpenMLS** (Rust) is
the preferred implementation, subject to dependency, security and
compatibility review when the group work starts. It joins the 1:1 protocol
in the shared Rust core (0035), behind the same FFI.

| Part | Decision |
|---|---|
| 1:1 chats | Fireplace's hybrid protocol, ported to Rust (0035) |
| Groups | MLS, through a reviewed OpenMLS release |
| Membership and key changes | MLS epochs and commits |
| Transport | Firestore, as for 1:1 at first |
| Post-quantum | A requirement; hybrid suites evaluated before release |
| Apps and iOS extension | The shared Rust core through FFI |

## Why

- **A standard** with forward secrecy, post-compromise security and member
  changes in its design, reviewed by many, instead of a sender-key scheme we
  would design and maintain alone.
- **Tree-based key management:** adding or removing someone does not mean
  re-establishing a session with every member.
- **An audited implementation:** SRLabs audited OpenMLS (funded by the
  Sovereign Tech Agency) and reported eight issues, one rated High; when the
  results were announced all but one Low-severity issue were fixed. The
  version chosen must include the fixes; check the remaining one then.

## Post-quantum

Fireplace's 1:1 chats are hybrid post-quantum today (X25519 + ML-KEM-768 for
key exchange, Ed25519 + ML-DSA-65 for identity). For groups:

- OpenMLS has experimental support for **X-Wing** (X25519 combined with
  ML-KEM) since 2024, as a cipher suite without a registered code point, so
  interoperability is not guaranteed.
- The IETF MLS working group's draft **draft-ietf-mls-pq-ciphersuites**
  ("ML-KEM and Hybrid Cipher Suites for MLS") is in progress; version 04 is
  from March 2026.
- **Gap:** X-Wing covers key exchange only. MLS signatures would stay
  Ed25519, while our 1:1 identities also sign with ML-DSA. Groups would start
  with weaker post-quantum *authentication* than 1:1 chats. That matters
  against a quantum attacker active at the time, not for decrypting recorded
  traffic later. Look again at post-quantum signature suites for MLS before
  release.
- Experimental suites need their own evaluation before production use.

## What MLS does not solve (ours to design)

- **Identity:** binding MLS credentials to Fireplace accounts and devices
  (the device certificates of 0002 and 0014), safety numbers for groups,
  linked devices.
- **Delivery and ordering:** MLS needs commits applied in one order per
  epoch; the server (Firestore transactions and rules) must sequence them,
  and concurrent commits must be resolved.
- **Metadata:** the rules need to know who may post to a group, so the server
  will see group membership, as it sees 1:1 pairs today. Minimise it, and do
  not claim more.
- **Storage:** MLS group state in the encrypted stores, crash safety and the
  account lock (0030), as for 1:1 sessions.
- **Abuse and cost:** invitations, request limits, the send window per group
  message, fan-out reads and writes.
- **The product rules stay:** no read receipts, delivery ticks, typing or
  presence in groups either.

## When the group work starts

A design note covering the above, the OpenMLS version and audit status,
features and licence (MIT), a test plan (interop with OpenMLS's test vectors,
epoch and commit races, membership changes, device revocation), cost per
group message, and the owner's approval of the dependency.

Sources: RFC 9420; the OpenMLS audit announcement; Cryspen, "Post-Quantum
OpenMLS" (2024); draft-ietf-mls-pq-ciphersuites (IETF datatracker).

Recorded by Claude Code; direction proposed with GPT, chosen by the owner.
