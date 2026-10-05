# Android: building, signing and installing

## What is configured
- Package `com.fireplacechat.app`, label "Fireplace".
- **No backups.** `allowBackup=false` plus `data_extraction_rules.xml` exclude everything from Google backup and phone-to-phone transfer. Keys live in the hardware-backed Keystore and cannot be restored elsewhere, so a restored copy of the app's data would be unreadable, and encrypted history has no business in a cloud backup.
- **Permissions** (the build fails if any other appears; see `scripts/check_apk.sh`): `INTERNET`, `CAMERA` (QR codes; the camera is not required to install), `ACCESS_NETWORK_STATE`, `WAKE_LOCK`, and, from the switched-off push library, `POST_NOTIFICATIONS` and Google's push-receive permissions. The app never asks for notification permission unless push is enabled.
- **CI** (`android-build`) builds a release APK with the *debug* key and runs the permission/backup check. That APK is never to be distributed.

## Signing key
The upload key is `upload-keystore.jks` (RSA 4096, valid to 2056), kept **outside the repository** in a secure location outside the checkout together with `key.properties` (passwords). `android/key.properties` is a git-ignored copy that Gradle reads.
- Certificate SHA-256: `6C:3F:ED:82:FF:8C:6E:79:8C:6C:EF:6D:2F:F5:03:94:A5:D0:44:9E:DD:67:96:B1:B6:9F:F3:39:6B:8E:28:04` (public information; useful when registering the app with Google).
- **Back it up** (keystore file + password) somewhere offline and separate from this computer. If it is lost, phones that installed a build signed with it cannot be *updated* (only reinstalled, losing local keys and history). With Google Play App Signing the upload key can be reset through Google; sideloaded installs cannot.
- Never commit it, paste it, or put it in CI secrets unless you deliberately set up signed CI releases.

## Build
```
flutter build apk --release --split-per-abi
scripts/check_apk.sh build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### Building something to distribute
Plain `flutter build apk --release` falls back to the DEBUG key when `android/key.properties` is missing (fine for checking that it
compiles, which is what CI does). Anything you hand to other people must be built and checked like this instead:
```
flutter build apk --release --split-per-abi -Pfireplace.distribution=true
scripts/check_apk.sh --distribution build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```
- `-Pfireplace.distribution=true` makes the build **fail** if the signing material is missing or incomplete, instead of quietly using
  the debug key.
- `--distribution` makes the checker fail unless the APK's signature verifies, it has exactly one signer, it is not debug-signed, and the
  signer's certificate SHA-256 equals the upload-key fingerprint in `android/upload-cert.sha256` (public information, committed). Use
  `--signer <sha256>` or `EXPECTED_SIGNER_SHA256` to compare against a different fingerprint.
- The ordinary check (no flag) still passes a debug-signed APK, with a note that it is NOT distributable, so CI keeps working.
- `scripts/test_check_apk.sh` tests these rules on re-signed copies of a built APK (throwaway keys; your real key is never used). CI runs it.
Almost all current phones need `app-arm64-v8a-release.apk` (about 28 MB). Older 32-bit phones: `app-armeabi-v7a-release.apk`.

## Install on a phone (no developer programme needed)
1. Copy the APK to the phone (USB, a private cloud link, or `adb install -r <apk>`).
2. Open it on the phone; Android asks to allow installs from that app (Files/Chrome) once.
3. Updates: install a newer APK signed with the same key over the old one; `versionCode` (the number after `+` in `pubspec.yaml`) must go up.

## Not needed yet
- Firebase API-key application restrictions must include the package and the actual signing fingerprint in Firebase. They are only required for Google sign-in, phone auth or Play Integrity (App Check); add the certificate above if you adopt one of those.
- Play Console (US$25 one-off) is only needed to publish on Google Play, not to test.
