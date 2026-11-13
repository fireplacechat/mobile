# 0041: Link the pinned core into the iOS app

Status: proposed for review. This is the build foundation for 0035. It does
not enable the Rust production backend or notification previews.

The plugin builds the exact registry pin for arm64 devices, arm64 simulators
and x86_64 simulators. The header comes from that same published package.
Xcode creates a static XCFramework with a universal simulator library.
The approved Rust toolchain and Xcode tools are sufficient; there is no new
package, CocoaPod or remote Swift dependency.

The plugin uses Flutter's existing Swift Package Manager integration. Its
small C anchor retains all production C ABI entry points, and the app exports
them for Dart's process lookup. Swift simulator tests check that the live
session symbols are available, the test random stream is absent, and a C
function returns the expected error for an invalid output pointer.
The build also rejects test-stream symbols in each static library.

The existing manual `ios.yml` workflow builds unsigned device and simulator
apps, runs the Swift tests, and runs the published core's protocol/vector
tests on the simulator. Its source checkout is pinned to the commit used
for the published 0.1.1 crate. Test-only Rust features are confined to that
separate test checkout. TestFlight check/upload jobs build the normal core
before building the app. All macOS triggers remain manual and owner-run.

After this PR is available, the owner can validate it with:

```sh
gh workflow run ios.yml --repo fireplacechat/mobile --ref gpt/ios-crypto
```

Windows can check shell syntax, the C anchor against the published header,
the full Flutter host suite and unchanged renders. It cannot validate Swift,
Apple linking or simulator execution. The owner-dispatched macOS run must
pass before merging. No signing credentials or new Apple identifiers are
needed for this unsigned check.

The extension target, shared keychain migration, App Group, read lock,
bounded REST fetch and device diagnostics follow separately. The extension
will link the static core directly and system frameworks; it will not link
the Flutter plugin or Firebase SDK. Its memory budget remains a measured
peak of about 12 MB, with capped message/history reads and the original
push body as the failure fallback.

No wire, stored JSON, key handling, authentication, permissions, server or
UI behavior changes. No new runtime network access is added.

Implementation assisted by OpenAI Codex.
