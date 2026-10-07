#!/usr/bin/env bash
# Build the signed Google Play bundle on the owner's machine, never in CI.
set -euo pipefail

fail() { echo "$1" >&2; exit 1; }
version="${1:-}"
dry_run=0
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || fail "usage: scripts/build_aab.sh <vX.Y.Z> [--dry-run]"
if [ "$#" = 2 ]; then
  [ "$2" = --dry-run ] || fail "usage: scripts/build_aab.sh <vX.Y.Z> [--dry-run]"
  dry_run=1
fi
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "expected version vX.Y.Z"
root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "run from the repository root"
[ "$(pwd -P)" = "$(cd "$root" && pwd -P)" ] || fail "run from the repository root"
tree=$(git status --porcelain)
[ -z "$tree" ] || fail "working tree must be clean"
branch=$(git symbolic-ref --quiet --short HEAD) || fail "must be on main"
[ "$branch" = main ] || fail "must be on main"
git fetch --quiet origin
current=$(git rev-parse HEAD)
upstream=$(git rev-parse --verify origin/main)
[ "$current" = "$upstream" ] || fail "main must equal origin/main"
package_version=$(awk '$1 == "version:" { print $2 }' pubspec.yaml)
[ "$version" = "v${package_version%%+*}" ] || fail "version must match pubspec.yaml"
[[ "$package_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]] || fail "pubspec.yaml must use X.Y.Z+N"
build_number="${package_version##*+}"
if [ "$dry_run" = 0 ]; then
  [ -f android/key.properties ] || fail "signing key missing, see docs/development/android-release.md"
fi
command -v keytool >/dev/null || fail "keytool is required"
command -v flutter >/dev/null || fail "flutter is required"

if [ "$dry_run" = 1 ]; then
  echo "Dry run: root, clean main, origin/main, version and tools checked."
  echo "No signing material read; no build or upload performed."
  echo "Would build: flutter build appbundle --release -Pfireplace.distribution=true"
  echo "Would write: build/release/fireplace-${version#v}+$build_number.aab and its .sha256"
  exit 0
fi
if command -v sha256sum >/dev/null; then
  hash_tool=sha256sum
elif command -v shasum >/dev/null; then
  hash_tool=shasum
else
  fail "sha256sum or shasum is required"
fi

flutter build appbundle --release -Pfireplace.distribution=true
bundle=build/app/outputs/bundle/release/app-release.aab
[ -f "$bundle" ] || fail "release app bundle is missing"
# Fix the certificate output language, without reading the keystore or passwords.
certs=$(keytool -J-Duser.language=en -J-Duser.country=US -printcert -jarfile "$bundle") || fail "could not read the bundle signer"
signers=$(grep -Ec '^Signer #[0-9]+:' <<<"$certs" || true)
[ "$signers" = 1 ] || fail "bundle must have exactly one signer"
fingerprint=$(awk '
  /^Certificate #[0-9]+:/ { leaf = ($0 == "Certificate #1:") }
  leaf && /^[[:space:]]*SHA256:/ { sub(/^[[:space:]]*SHA256:[[:space:]]*/, ""); print }
' <<<"$certs")
normalize() { tr 'A-F' 'a-f' | tr -d ': \t\r\n'; }
actual=$(printf '%s' "$fingerprint" | normalize)
expected=$(head -1 android/upload-cert.sha256 | normalize)
[[ "$actual" =~ ^[0-9a-f]{64}$ ]] && [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || fail "invalid signer fingerprint"
[ "$actual" = "$expected" ] || fail "bundle signer does not match android/upload-cert.sha256"

# AAB manifests use protobuf, not the binary XML aapt2 reads. No bundletool is
# installed/ downloaded here; the existing CI APK gate checks the allowlist.
echo "Bundle permissions: rely on the existing CI APK permission check; AAB manifest decoding is skipped."
mkdir -p build/release
output="build/release/fireplace-${version#v}+$build_number.aab"
cp "$bundle" "$output"
if [ "$hash_tool" = sha256sum ]; then
  checksum=$(sha256sum "$output")
else
  checksum=$(shasum -a 256 "$output")
fi
printf '%s\n' "$checksum" > "$output.sha256"
echo "Bundle: $output"
echo "Size: $(wc -c < "$output" | tr -d ' ') bytes"
echo "SHA-256: ${checksum%% *}"
echo "upload this file in Google Play Console, Internal testing, Create new release"
