# 0043: Bounded iOS notification service

Status: proposed for review. Follows 0035, the native iOS build (0041), and
shared storage (0042). Production app crypto still defaults to Dart pending
the separate explicit review required by 0035. The extension always calls
the same published Rust core through the C ABI.

## Receive path

The app embeds `com.fireplacechat.app.NotificationService`, deployment target
iOS 15. Its target links only the static Rust core and system frameworks.
It has no Flutter engine, Firebase SDK, database or additional dependency.
Source/project and built-bundle checks guard this separation and reject the
test random-stream exports. The extension's C wrapper has no save API.

The app caches its own Firebase ID/refresh token, expiry and public project
configuration in the shared device-only keychain. ID-token changes refresh
that record. Changes are serialised, old loads are invalidated, and local
credential removal must succeed before Firebase sign-out proceeds. Refresh
events are suspended during sign-out. The existing remote push unregister
remains best-effort; the new mandatory local barrier displays a plain error
and keeps the account signed in if revocation fails. Account deletion's
existing secret-store reset also erases the credential. No token is logged,
put in an App Group file, or sent to another service.

The extension reads this credential, current notification choices, the
existing allowed-chat index and receive cursor. It resolves only the push's
opaque conversation key. Missing keys, an unrecognised chat, disabled
previews, a pending receive journal or a failed lock leaves the original
push body. It never establishes a new identity pin or creates local keys.

The current APNs alert already supplies its opaque key as `aps.thread-id`
and enables `mutable-content`. The extension uses that thread identifier;
it does not require Android's separate data-only payload fields. A legacy
data key is accepted only with its explicit marker. No backend change is
needed.

An expired ID token is refreshed against Google's fixed HTTPS token endpoint,
using that user's refresh token and public API key. The response must name
the same user; the returned token's audience, subject and issuer must match.
Firestore still verifies its signature and enforces the deployed security
rules. No service-account credential is used. The refreshed token is used
only in memory; the extension never updates the keychain.
The request includes the parent app's `X-Ios-Bundle-Identifier`, required by
the existing iOS API-key restriction. Read-only live metadata checks on
2026-11-13 confirmed that restriction and unenforced App Check for Firestore
and Firebase Auth; no setting was changed.

The REST query requests at most ten new documents from one chat, projecting
only sender fields, timestamp and the envelope for this device. Its response
is capped at 512 KB while streaming, before appending an oversized chunk.
Refresh and device-certificate responses have smaller caps. Sessions and
prekeys are copied under the existing isolate-plus-file-lock protocol. The
extension opens existing fcntl read locks only, with a 150 ms lock-wait cap.
It releases each lock before a network request. Choices, credentials and
journals are rechecked after network activity and before posting plaintext.

An existing session must match both users and devices. A new handshake needs
the already pinned peer identity, its verified device certificate, consistent
local device/prekey pairs, and the signed/one-time prekeys named by the
handshake. Its derived session ID must match the envelope. At most two live
session copies are held; the failed-chain budget stays with each handle.
All changes die with those copies. The app receives and persists every
message, journal, session and prekey consumption as before.

## Text, bounds and fallback

Swift parses the existing payload and formats notification text against
fixtures generated from the unchanged Dart implementation. Tests include
Unicode scalars, combining characters, whitespace, reactions, edits/deletes,
quotes and invalid input. Ordinary previews never open message history.

A reaction quote uses only an authenticated snapshot no larger than 512 KB.
A nonempty append log may supersede that snapshot, so it also causes the
generic `Reacted … to a message` body. No log replay/database is added to the
extension. A known target that belongs to the other person or is deleted is
not quoted. When history is unavailable or capped, target ownership cannot
be established; the generic fallback is the memory-bounded exception to
Android's normal own-message-only reaction alerts. This exception needs
particular attention in review and the device checklist.

The work deadline is about 4.2 seconds, with original-content completion at
4.5 seconds or on the system's expiry callback. Completion runs exactly
once, including cancellation and repeated delivery/expiry callbacks. HTTP
requests use ephemeral sessions with no cookies, credential cache or URL
cache. Neither bearer tokens nor refresh bodies follow redirects. There is
no retry loop. Decoder depth, collection sizes and secret/session buffers
are bounded. Rust output buffers are freed/wiped even on errors, and owned
C-input copies are wiped when released.

**iOS mutation limitation:** Apple's ordinary notification service cannot
silence a newly arriving alert. Full parity for edits, deletes, cleared
reactions and other cases with no new alert needs Apple's separately approved
[notification-filtering entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.filtering).
This PR does not request or assume that entitlement. These cases retain the
original push's `New Message`; they do not display a stale decrypted body
from an earlier document in the batch. Existing delivered alerts are not
edited/removed by this first extension. The app's stored mutations continue
unchanged. Release review must assess this stated limitation.

## Memory diagnostics and release gates

The goal is about 12 MB measured process peak against the roughly 24 MB NSE
budget on the target iPhone. Bounds reduce allocation risk; they do not prove
the budget. Debug/explicit TestFlight diagnostic builds record only numeric
timestamps, duration, peak bytes and outcome in a local App Group ring of
twenty runs. The kernel's lifetime physical-footprint peak is used where
available; iOS may reuse the process, so it is conservative across runs.
A zero memory result means unavailable, not a measured zero. An initial
incomplete entry remains if the extension dies before completion; it cannot
by itself establish whether memory, timing or another cause killed it.

Normal Release builds compile out the writer and native reader. The hidden
screen is reached by long-pressing Settings > Privacy and terms in a test
build; it shows local numbers only. The existing manual TestFlight workflow
adds an explicit diagnostic input, false by default. The signing lane checks
the final IPA for the expected flag and app/extension versions before upload.
A diagnostic TestFlight binary must never be selected for App Store release;
upload a separate ordinary build with the input off. The uploaded binary
cannot be changed afterwards.

The manual Mac workflow type-checks native sources early, runs pure Swift
tests, builds device/simulator app and extension, inspects the Release binary,
runs Rust standards/protocol tests with required vectors in a booted
simulator, and runs Swift C ABI/lifecycle/migration tests. A real TestFlight
upgrade on the iPhone X is still required to validate keychain accessibility,
file migration, notification behavior, timing and measured memory.

Cost per attempted preview is bounded by ten message-document reads and at
most two device-certificate reads, plus one token refresh when needed. An
empty Firestore query has its normal minimum read charge. There are no
Firestore writes, new server fields, rules or backend changes. A large
backlog beyond the bounded page can show an earlier unread preview or fall
back; it does not trigger unbounded catch-up. App Check remains the existing
monitoring configuration; if its enforcement is later enabled, REST access
must be revisited rather than weakening enforcement.

Signing setup and uploads remain owner actions. The production Rust switch
and removal of Dart retain their original explicit review/release gates.

Implementation assisted by OpenAI Codex.
