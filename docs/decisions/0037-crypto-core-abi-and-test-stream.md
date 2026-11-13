# 0037: The C ABI, the libcrux comparison, and a test-only random stream

Status: **proposed** with the first `fireplace-crypto` pull request. Decision
0035 (accepted by the owner, 2026-11-13) left these three choices to that PR.

## C ABI

The core speaks C, not Dart and not Swift. `include/fireplace_crypto.h` in
`fireplace-crypto` is the whole surface. The header is written by hand.
There is no binding generator and no `dart:ffi` package beyond `dart:ffi`
itself, which the app will use in a later step.

- Inputs and outputs are JSON in the same field order the Dart code already
  stores, or raw byte strings where the Dart API already uses bytes (a
  recovery key, a signature, a fingerprint).
- The library allocates every returned buffer. The caller frees it with
  `fp_free`. A null pointer is ignored.
- A panic inside an export is caught and returned as a code. It does not
  unwind into the caller. Release builds keep panic set to unwind so that
  catch works.
- Codes are 0 ok, 1 invalid, 2 protocol refusal, 3 rate limited, 4 panic,
  5 the generator failed, 6 a bad argument. A verify that returns false is
  still 0, with the flag set to 0.
- `fp_session_decrypt` takes the clock from the caller when the pointer is
  non-null, and uses the system clock otherwise. A null or empty one-time
  prekey means there is none.
- The test stream (`fp_set_test_rng`) is process-global and for one thread.
  Production builds do not call it.

The app does not call this ABI yet. That is a later step, after 0.1.0 is on
crates.io. Publishing that version makes the crate's source public even
while the GitHub repository stays private. The owner reviews
`cargo package --list` before publishing.

## libcrux

Stay with the crates 0035 approved: `ml-kem` 0.3.4 and `ml-dsa` 0.1.2, with
each crate's `zeroize` feature on, and no `hazmat` feature. `ml-dsa` 0.1.2
includes the fix for RUSTSEC-2025-0144 / CVE-2026-22705.

libcrux is formally verified and is not on the approved list. Its own
advisories (panics, an AVX2 verification bug, a wrong norm check) are listed
in `fireplace-crypto`'s `docs/dependencies.md`. Formal verification has not
meant an absence of defects. `ml-kem` and `ml-dsa` say they have not been
independently audited. `aes-gcm` was audited by NCC Group. This port does
not call the result audited.

## Test-only random stream

Some steps draw fresh bytes inside the library (an X25519 key pair, ML-KEM
coins, an ML-DSA seed or hedge, an AES-GCM nonce). Byte-for-byte comparison
needs both sides to draw the same bytes. Elsewhere the tests cross-check:
one side opens what the other produced.

`installTestRng` in `lib/src/crypto/codec.dart` installs a finite stream.
The body sits inside `assert`, which release builds strip, so a release call
cannot turn the stream on. When the stream is off, every call site uses the
same operating-system or library generator it used before. When it is on,
those call sites take seeds, coins and nonces from the stream, in the same
order as the Rust core.

`dart run` on this machine does not enable asserts unless asked. The export
script is:

```
dart run --enable-asserts scripts/export_crypto_vectors.dart <directory>
```

`flutter test` enables asserts, which is what the unit test uses. The app's
own tests cannot depend on the crate until 0.1.0 is published, because CI
cannot read the private repository. Until then, Dart opens a Rust result by
decrypting `test/crypto/vectors/rust_session.json`, a fixture the Rust tests
can regenerate.
