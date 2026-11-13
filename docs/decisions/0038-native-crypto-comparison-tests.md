# 0038: The native bridge and comparison tests

Status: proposed for review. Implements the comparison stage of 0035; the
application continues to use the Dart implementation until a separate switch
is explicitly reviewed.

## Bridge and lifetime

The existing native plugin binds the pinned core with `dart:ffi`, without a
binding package or generator. The bridge has fixed, handwritten C signatures.
Each call scopes its allocations: input copies are wiped before libc frees
them, output buffers go through the core's wiping `fp_free`, and returned
arrays are Dart-owned copies. Errors contain a status code, never input data.
No native view escapes a call. JSON remains the existing representation.

The 0.1.0 JSON-only decrypt creates a fresh Rust session for every call. That
resets the failed-new-chain budget, which is intentionally absent from stored
JSON. The compatibility work found this before production integration.
Core 0.1.1 adds opaque live sessions (core PR #2). The bridge owns each handle,
registers its destructor with `NativeFinalizer`, and supports explicit close.
The failed-chain budget remains inside Rust. Loading a saved session resets
only that transient budget, as the Dart implementation does on restart.
The app's exact crate pin is updated in its own PR after owner publication.

## Comparisons

The Dart crypto files remain unchanged. A test-only facade applies the same
existing assertions to each implementation. It preserves the existing data
types and parsers, and maps the core's refusal/rate-limit codes to the existing
session exceptions. It does not add a production backend selection.

- Handshakes, certificates, signatures, prekeys, ratchets, forward secrecy,
  recovery, linking, key consistency, and contributory exchange run through
  both implementations.
- The existing seeded adversarial protocol and delivery schedules run on
  both. Additional mixed pairs initiate and accept in opposite implementations;
  restarts can move saved sessions and unconsumed skipped keys to either.
- The recorded finite stream compares keys, signatures, handshakes, envelopes,
  ratchet state, recovery, linking, fingerprints and public comparison codes
  byte for byte. Only session creation time is normalised, because Dart takes
  the wall clock internally and the C ABI accepts it as an argument.
- NIST and Wycheproof primitive vectors remain in the Dart suite and in the
  core's own required tests. The bridge adds no separate primitive provider.
- Explicit bridge tests exercise errors, allocation bounds, copied outputs,
  snapshot independence, and use after close. A closed handle is never passed
  back into Rust.

The normal host library is built separately from the `test-rng` feature build.
The normal library must not export the test-stream symbols; only test code
looks them up in the separate test library. Missing libraries fail tests.
Both builds come from the same exact registry pin and Cargo lockfile in CI.
Test file sizes stay small enough for the existing three unit shards.

## Scope and cost

No wire, storage, authentication, Firestore, permissions, server reads or
writes change. No new third-party dependency is added. The extra host build
and comparison tests add CI work. Android/iOS packaging, the production
backend seam, notification previews, and the 12 MB extension memory target
remain separate steps in 0035 and the release handoff.

Implementation assisted by OpenAI Codex.
