# 0035: The cryptographic core and the iOS notification extension

Status: proposed, for the owner to decide, 2026-11-13. Docs only: nothing
changes in the app, the protocol or the keys. Follows decision 0030 (previews
decrypted on the phone) and issue #87.

## The problem

Android shows message previews from v0.3.6: a data push wakes the app's own
code, which decrypts and posts the notification (0030). iOS does not run app
code for a closed app. The only way to show a decrypted preview is a
Notification Service Extension: a separate small process iOS starts for each
push, with about **24 MB** of memory and about **30 seconds**. That limit is
Apple's, for every app.

Fireplace's protocol (hybrid X25519 + ML-KEM-768 ratchet, Ed25519 + ML-DSA-65
identities; decisions 0002, 0003) is written in **Dart**. Inside the app that
is fine. Anything outside the app, such as an extension, has to bring a Dart
runtime with it, or use another implementation.

## What Signal does

Signal-iOS is native Swift. Its extension opens the app's database in a shared
App Group, reads keys from the keychain ("after first unlock"), fetches every
waiting message, decrypts it with the same code as the app, and posts its own
notifications (read for decision 0030). That works because Signal's protocol
lives in one native library, **libsignal** (Rust, with Swift, Java and
TypeScript bindings), linked by the app and the extension alike. One
implementation runs everywhere; nothing is duplicated.

## Options

1. **A minimal Dart runtime in the extension.** The receive code only: no UI,
   no Riverpod. One implementation of the protocol, no rewrite. Compiled Dart
   still needs its runtime, and Flutter's usual engine is not made for a
   process this small, so whether it fits is unknown until measured on a
   phone.
2. **A second implementation of receiving, in Swift.** Two implementations of
   a cryptographic protocol to keep identical, with every test vector run
   against both, forever. **Rejected.**
3. **Our protocol, ported to one native library (Rust).** The same design,
   wire format and stored sessions, so nothing changes for people. Flutter
   calls it through FFI; the extension links it directly. One implementation
   again, now usable outside Dart. A large port, with every test vector and
   the randomized simulation run against both versions during the switch.
   It improves reuse and gives room for stronger implementation checks; it
   does not answer questions about the protocol's design.
4. **Adopt libsignal.** Widely deployed and scrutinised, with public
   specifications, AGPLv3 like Fireplace, and already proven inside an iOS
   extension. But:
   - Signal's README says "Use outside of Signal is unsupported", and that its
     APIs and the JNI, C and Node bridge layers may change without notice.
     There is no Flutter binding: we would write and maintain the FFI glue,
     pin versions, and possibly keep a fork.
   - It is Signal's protocol, not ours: a different wire format, session store
     and identity scheme (no ML-DSA identity signatures; its own post-quantum
     key agreement). Moving means a controlled migration: new sessions,
     identity-verification changes, linked devices, and a period where both
     run.
   - It lowers the risk of the protocol's design, not of our integration:
     authentication, identity handling, persistence, the FFI boundary and
     recovery still need their own review. Using it does not make Fireplace
     audited.
   - A new third-party dependency, which needs the owner's approval.

## Decision (proposed)

- **Now:** keep Flutter, Dart and the existing protocol. iOS notifications stay
  "New Message" with the sender's name, which is no worse than today.
- **Next evidence:** run option 1 as a spike on the **oldest supported iPhone**
  (iOS 15 is the deployment target), in a Release build: peak memory, start to
  the first fetch, and time to a posted notification, over several runs, with
  the phone locked and unlocked. Pass if it stays under about 18 MB and posts
  within about 5 s, with margin. The spike needs a Mac; the owner or whoever
  has one runs it. The plan is on issue #87.
- **If option 1 fails:** compare options 3 and 4 in their own decision before
  any code. Neither is chosen now. That comparison must cover migration,
  security review of the integration, upstream maintenance, licensing,
  interoperability, ratchet-state persistence, crash recovery, linked devices,
  and a rollout and rollback plan, and must show them working before release.
- **Option 2 is rejected** whatever the spike shows.
- Replacing working cryptography is a much larger change than a notification
  feature. It needs its own case, and is not justified by previews alone.

Whatever runs in the extension uses what 0030 already prepared: the account
lock with its generation counter (to which the extension adds the file lock
between processes), the App Group storage, keys readable "after first
unlock" for every install (#85, owner's decision, applied with the
extension), `mutable-content` on every iOS push (backend 0019), and the
fallback to the push's own "New Message".

## For the owner

- The spike: when a Mac and the oldest supported iPhone are available.
- If the spike fails: a decision between a Rust port of our protocol and
  libsignal, after its own design note.

Implementation assisted by Claude Code; alternatives reviewed with GPT.
