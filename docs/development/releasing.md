# Store releases

GitHub releases identify the commit used for a store build and hold release notes
and automatic source archives. No APK or AAB is attached. Builds and uploads stay
on the owner's machine in this phase; CI gets no signing key or passwords.

1. Bump `pubspec.yaml` to `version: X.Y.Z+N` (see *Version numbers* below). **N must
   increase for every upload to either store**, including a rebuilt beta. Commit it
   and merge the reviewed change to `main`; wait for green CI, including the Android
   permission check.
2. In GitHub Actions, choose **Release**, **Run workflow**, branch **main** and
   version `vX.Y.Z`. It must match the version before `+` in `pubspec.yaml`.
   Existing tags or releases are refused. The workflow builds nothing: it
   creates a draft for that commit with generated notes and prints the URL.
   Do not publish it yet. A draft does not create its new tag until publication.
3. On the machine that holds the upload key, check out clean, current `main` and
   run `scripts/build_aab.sh vX.Y.Z` from the repository root. It fetches origin,
   checks the version and tools, requires `android/key.properties`, and builds
   with `-Pfireplace.distribution=true` so debug signing cannot be a fallback.
   It checks the bundle's single signer against `android/upload-cert.sha256`,
   then writes `build/release/fireplace-X.Y.Z+N.aab` and its `.sha256`, printing
   size and checksum. See [Android signing](android-release.md).
4. Upload the `.aab` in **Google Play Console → Testing → Internal testing →
   Create new release**. The first bundle upload also enrols the app in Play
   App Signing: the owner retains the upload key, Google holds the app-signing
   key. Keep the bundle private and upload it only to the store.
5. For iOS/TestFlight, follow the [owner checklist](ios-release.md). The same
   version rules apply: `CFBundleVersion` is the number after `+`; zero padding
   is fine because Apple compares the components as integers. Signing and upload
   require the owner's protected-environment approval.
6. Once the store build is out, review the draft and press **Publish release**.
   This creates the tag at the recorded commit. The `v*` tag protection prevents
   moving or deleting it: a wrongly named tag cannot be undone. Check both the
   version and commit before publication; build from the same commit the draft
   records, rather than a later `main`.

Store delivery uses Google's or Apple's signing identity, so internal-test and
production versions of the same app can replace one another without uninstalling
when the store offers a compatible update. App Check's Play Integrity supports
Play installations after owner registration; see the
[App Check setup](app-check.md), [Play App Signing guide](https://developer.android.com/studio/publish/app-signing)
and [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

## Version numbers

The project stays on `0.x` versions until it is ready to call 1.0, with small,
frequent releases tagged `v0.1.0`, `v0.1.1`, `v0.2.0` and so on (semantic versioning:
patch for fixes, minor for features, major for 1.0 and breaking changes).
The build number after the `+` is derived from the version, so it rises by itself:
major, minor and patch as two digits each, zero-padded, for example
`0.1.0+000100`, `0.1.1+000101`, `0.2.0+000200`, `1.0.0+010000`.
Both stores only need the number to go up. If a build has to be uploaded again for
the same version (a store rejected it, or a fix is needed), bump the patch number
and publish a new version rather than reusing one: tags cannot be moved or deleted.

## Dry run and limits

`scripts/build_aab.sh vX.Y.Z --dry-run` still requires a clean repository root,
`main` equal to fetched `origin/main`, matching version, `flutter` and `keytool`.
It prints the intended build and output paths before checking or reading signing
material; it does not build, sign or upload anything. A normal run without the
key file fails with `signing key missing, see docs/development/android-release.md`.

An AAB stores its merged manifest as protobuf; stock `unzip` exposes those bytes
but does not decode permissions, and `aapt2` expects a different binary XML
format. This script does not install bundletool or widen the permission allowlist.
It prints that bundle manifest decoding is skipped and relies on the existing
CI APK permission check against the same commit. `keytool` checks the bundle
certificate; it does not replace the store's upload validation.

The workflow is manual-only and creates a draft without binaries. It adds no
secrets or environments and uses only the built-in GitHub token for that job.
Future store-upload automation needs a separate owner decision.

iPhone only for now; the app runs scaled on iPad. A wide-screen layout is on the roadmap.
