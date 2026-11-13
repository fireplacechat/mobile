# 0039: Package the pinned core for Android

Status: proposed for review. Follows 0035 and the host comparison work in
0038. This packages the library; the production backend remains Dart until
the owner explicitly reviews the switch.

The in-repo plugin builds the exact registry pin for `arm64-v8a`,
`armeabi-v7a`, and `x86_64`, using the approved Rust toolchain and installed
Android NDK. No cargo-ndk, build package, native provider or binding generator
is added. The builder can install the approved Rust standard-library targets.
It uses the NDK's clang directly with the matching Android target and API 26,
and requests 16 KB load-segment alignment. It enables no test-only features.

Gradle declares the manifest, lockfile, toolchain and builder as inputs, and
registers generated JNI directories with the Android variant source API.
The normal APK build therefore runs the native build before packaging, and
rebuilds it when the pin or builder changes.

The APK checker verifies all three ELF architectures, 16 KB alignment, the
live-session C ABI, and absence of both test-RNG exports. Its regression
tests reject mismatched, truncated, misaligned and feature-enabled libraries.
The existing APK checker continues to verify the package, permission
allowlist, backup settings and signer. A debug APK built on this machine is
a local compile check; it is not a distribution artifact.

No wire, storage, key handling, authentication, Firestore, permission or UI
changes. No new dependency or runtime network call is added. Build time
grows by three target compiles; the existing Android CI workflow installs
the pinned Rust toolchain and validates the packaged libraries on Linux.

Implementation assisted by OpenAI Codex.
