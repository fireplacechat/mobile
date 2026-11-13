# 0040: App crypto backend selection

Status: proposed for review. Follows 0035, the C ABI comparisons (0038), and
Android packaging (0039). The production default remains Dart. Selecting
Rust by default requires the owner's separate explicit review.

The public crypto API delegates to the existing Dart reference or the pinned
Rust C ABI. The original protocol files remain unchanged. App services and
views import the public seam; immutable data, keys and wire/storage JSON keep
their existing shapes. No existing key is regenerated or migrated.

`FIREPLACE_RUST_CRYPTO=true` selects the native backend for a test build.
With no define, release workflows retain the Dart default. Scoped overrides
let tests exercise both engines, including through asynchronous callbacks.
Mutable sessions retain the implementation they were loaded with; changing
the scope cannot swap an active ratchet or discard its refusal budget.
Native sessions can close explicitly and also use rooted native finalizers.

The existing chat-service simulation runs on both backends, covering its
multi-device, restart, shared-account-lock, receive-journal, deferred-message
and send-window schedules. Direct tests protect public API error types,
snapshot independence and the exact stored session fields. The protocol
comparison suite remains tied directly to the unchanged Dart reference.

The Android emulator benchmark measures send and receive time after warm-up,
including changes of ratchet direction. It prints only aggregate timing
values. It is tagged `timing` and run separately. Emulator results are
reported with the PR, not treated as a prediction of iPhone performance.

No server, wire, storage, key handling, permission, notification or UI behavior
changes. No new dependency is added. The remaining release work is the iOS
extension and signing, owner review of the production switch, a release on
Rust, and only then owner-authorised removal of the Dart implementation.

Implementation assisted by OpenAI Codex.
