# 0035: The cryptographic core in Rust, and the iOS notification extension

Status: **accepted** (owner, 2026-11-13): port Fireplace's own protocol to
Rust. The next release is about two things only: the Rust core, and
notification previews on iOS, without breaking anything already built.
Follows decision 0030 (previews decrypted on the phone) and issue #87.

## Why

Android shows message previews from v0.3.6: a data push wakes the app's own
code, which decrypts and posts the notification (0030). iOS runs no app code
for a closed app. The only way to a decrypted preview is a Notification
Service Extension: a separate process iOS starts for each push, with about
**24 MB** of memory and about **30 seconds** (Apple's limit, for every app).

Fireplace's protocol (hybrid X25519 + ML-KEM-768 ratchet, Ed25519 + ML-DSA-65
identities; decisions 0002, 0003) is about 1,900 lines of Dart on the
`cryptography` and `pqcrypto` packages. Inside the app that is fine; outside
it, an extension would have to carry a Dart runtime.

Signal solves this with one native library, libsignal (Rust), linked by the
app and its extension alike: one implementation everywhere. We do the same
with **our own** protocol.

## Options considered

1. A minimal Dart runtime in the extension: one implementation, no rewrite,
   but compiled Dart still needs its runtime, and whether it fits 24 MB was
   unknown. Not pursued.
2. A second implementation of receiving in Swift: two implementations of a
   cryptographic protocol to keep identical forever. **Rejected.**
3. **Our protocol, ported to one Rust library. Chosen.** Same design, wire
   format and stored sessions, so nothing changes for people.
4. Adopting libsignal: AGPLv3 and widely scrutinised, but its README says "Use
   outside of Signal is unsupported", with bridge layers that change without
   notice; it is a different protocol (a migration of sessions and
   identities); and it lowers protocol-design risk, not integration risk. Not
   chosen.

## What "without breaking anything" means

- **The wire format, stored sessions and keys do not change.** A message
  encrypted by the Dart code decrypts with the Rust code and the other way
  round; a session saved by one loads in the other; existing installs need no
  migration and existing chats continue.
- **Cryptographic correctness is proven by comparison.** The Dart code stays
  as the reference while the port is built. Every existing protocol test
  (decision 0008), the known-answer vectors, and randomized differential
  tests run against both, and both directions are checked (Dart sends, Rust
  receives, and back). The chat simulation runs with the Rust core.
- **One switch, then removal.** The app moves to the Rust core in one change
  once the comparisons pass; the Dart implementation is removed only after a
  release has run on Rust.
- Everything around the protocol stays as it is: the receive journal, history,
  the account lock, sends (0032), Android previews (0030).

## Shape

- **Its own repository, `fireplacechat/fireplace-crypto`** (owner,
  2026-11-13), as Signal keeps libsignal apart from its apps: AGPL-3.0, its
  own tests and CI, and the crate `fireplace-crypto` on crates.io. It holds
  the protocol only (key agreement, the hybrid ratchet, envelopes,
  signatures, prekeys, fingerprints, the recovery key) and a small C ABI. No
  networking, storage or UI.
- **The app pins an exact version** and builds the library from it in the
  in-repo plugin (`packages/fireplace_native`). A new version reaches the app
  only through a reviewed PR that changes the pin.
- **Claiming the name:** the owner creates the repository (private until the
  owner decides) and publishes `0.1.0` from the first real code, after review
  of the package contents. crates.io does not allow crates that only reserve
  a name, and a publish cannot be deleted after 72 hours.
- **Dart** calls it through `dart:ffi` (part of the SDK; no binding package).
  **Swift** (the extension) calls the same C ABI.
- **Builds:** Android libraries for each ABI and an iOS XCFramework, built by
  the in-repo plugin from the pinned version; a host library for
  `flutter test` on Linux CI and Windows. Both repositories' CI gain a pinned
  Rust toolchain.

## The iOS extension

- Fetches the chat's new message documents through **Firestore's REST API**
  with the person's own ID token, so the existing security rules apply; no
  Firestore SDK in the extension. Token refresh from the shared keychain is
  part of the work.
- Decrypts with the Rust core on a **read-only copy** of the session to build
  the preview, and **saves nothing**: no session, journal or history writes.
  The app still receives and saves every message exactly as today. This
  avoids a second storage implementation and any write coordination between
  processes. The extension only reads, under the cross-process file lock
  (0030), so it never sees a half-written session.
  - Cost: each message is decrypted twice (preview, then app), and its
    message key exists briefly in the extension's memory as well. Nothing is
    written; the ratchet advances only in the app, as now.
- Uses the App Group and keychain access group, with keys readable "after
  first unlock" for every install (#85, owner's decision), migrated with
  tests. The formats are the ones Android uses (#100), and the fallback is
  the push's own "New Message".
- Signing: a new extension identifier and refreshed profiles (owner).

## Dependencies (approved by the owner, 2026-11-13, with conditions)

The Rust toolchain and these crates may be used for the core; the first PR
lists their exact versions for the record: `x25519-dalek`, `ed25519-dalek`,
`ml-kem`, `ml-dsa`, `aes-gcm`, `hkdf`, `sha2`, `zeroize`, `getrandom` /
`rand_core`. Mostly MIT or Apache-2.0, compatible with AGPLv3. Conditions:

- **Exact versions, feature flags, licences and advisories** listed in the
  first PR; `Cargo.lock` committed; the toolchain pinned; `cargo audit` and a
  licence check in CI; no `hazmat` or other unneeded features.
- **Patched versions only.** `ml-dsa` had a timing side channel in signing
  (RUSTSEC-2025-0144, CVE-2026-22705), fixed from `0.1.0-rc.3`; use the
  current release (0.1.2 when this was written) or later.
- **Zeroisation enabled in each crate** (`ml-kem` and `ml-dsa` have it as an
  optional `zeroize` feature); depending on `zeroize` alone is not enough.
- **Be accurate about audits.** `aes-gcm` was audited by NCC Group;
  `ml-kem` and `ml-dsa` say "never been independently audited" (as is the
  Dart package the app uses today). Before the switch, compare them with
  `libcrux` (formally verified ML-KEM and ML-DSA, with advisories of its own)
  and record the choice. Memory safety is not side-channel safety.
- **Exact compatibility with the Dart code** (key formats, parameter sets,
  signature encodings, HKDF inputs, AES-GCM nonces, ratchet derivation,
  stored sessions), proven by the differential tests before the switch.
- The switch to Rust in production needs its own explicit review.

## Order of work

Grok builds, one PR per step; Claude reviews each PR against this decision
and the whole at the end.

1. The `fireplace-crypto` repository: the crate and the C ABI, with the
   known-answer vectors; the owner publishes `0.1.0`.
2. Differential tests against the Dart reference, in both directions.
3. The app on the Rust core, behind one switch, with the chat simulation.
4. The iOS extension, measured on the oldest supported iPhone (iOS 15).
5. Remove the Dart implementation after a release on Rust.

## What it costs

No server change and no new reads or writes. The extension's fetch is the
same reads as the Android handler: about one per new message in the chat
(0030). Build time grows by the Rust compile.

Implementation assisted by Claude Code; alternatives reviewed with GPT.
