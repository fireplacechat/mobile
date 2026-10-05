#!/usr/bin/env bash
# Tests scripts/check_apk.sh's signer checks against fixture APKs made from a base APK (re-signed
# with THROWAWAY keys; the real upload key is never used or needed).
#   scripts/test_check_apk.sh [base.apk]      (default: build/app/outputs/flutter-apk/app-release.apk)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
base="${1:-$here/../build/app/outputs/flutter-apk/app-release.apk}"
[ -f "$base" ] || { echo "no base APK at $base (build one first)"; exit 2; }
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android}}"
apksigner="$(ls -d "$sdk"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
[ -x "$apksigner" ] || { echo "apksigner not found"; exit 2; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; failn=0

key() { # key <name> <dn>
  keytool -genkeypair -keystore "$work/$1.jks" -alias k -storepass password -keypass password \
    -dname "$2" -keyalg RSA -keysize 2048 -validity 10000 >/dev/null 2>&1
}
sign() { # sign <keystore-name> <out.apk>
  cp "$base" "$work/in.apk"
  "$apksigner" sign --ks "$work/$1.jks" --ks-pass pass:password --key-pass pass:password --out "$2" "$work/in.apk"
}
fp() { "$apksigner" verify --print-certs "$1" | sed -n 's/^\(V[0-9.]* \)\{0,1\}Signer.* certificate SHA-256 digest: //p' | head -1; }

key upload 'CN=Test upload key,O=Fireplace,C=US'
key impostor 'CN=Test upload key,O=Fireplace,C=US'          # same name, different key
key debug 'CN=Android Debug,O=Android,C=US'
sign upload "$work/upload.apk"; sign impostor "$work/impostor.apk"; sign debug "$work/debug.apk"
cp "$work/upload.apk" "$work/tampered.apk"; echo x > "$work/junk.txt"; (cd "$work" && zip -q tampered.apk junk.txt)
UP="$(fp "$work/upload.apk")"; UP_COLONS="$(tr 'a-f' 'A-F' <<<"$UP" | sed 's/../&:/g; s/:$//')"

expect() { # expect <exit> <must-contain-or-empty> <description> -- <command...>
  local want="$1" needle="$2" desc="$3"; shift 4
  local out; out="$("$@" 2>&1)"; local got=$?
  if [ "$got" = "$want" ] && { [ -z "$needle" ] || grep -qF -- "$needle" <<<"$out"; }; then
    pass=$((pass+1)); echo "ok   $desc"
  else
    failn=$((failn+1)); echo "FAIL $desc (exit $got, wanted $want${needle:+, containing: $needle})"; echo "$out" | sed 's/^/     /'
  fi
}
check="$here/check_apk.sh"

expect 0 "signer: $UP"      "properly signed APK passes in ordinary mode"            -- "$check" "$work/upload.apk"
expect 0 "APK checks passed" "distribution passes with the matching fingerprint"      -- "$check" --distribution --signer "$UP" "$work/upload.apk"
expect 0 "APK checks passed" "the fingerprint may be written with colons and capitals" -- "$check" --distribution --signer "$UP_COLONS" "$work/upload.apk"
EXPECTED_SIGNER_SHA256="$UP" expect 0 "APK checks passed" "the fingerprint may come from the environment" -- "$check" --distribution "$work/upload.apk"
expect 0 "NOTE signed with the Android DEBUG key" "ordinary mode flags a debug-signed APK but allows it (CI compile check)" -- "$check" "$work/debug.apk"
expect 1 "DEBUG key: not distributable" "distribution refuses a debug-signed APK"     -- "$check" --distribution --signer "$(fp "$work/debug.apk")" "$work/debug.apk"
expect 1 "expected"         "distribution refuses an impostor key with the right name" -- "$check" --distribution --signer "$UP" "$work/impostor.apk"
expect 1 "expected"         "ordinary mode also fails when a fingerprint is given and does not match" -- "$check" --signer "$UP" "$work/impostor.apk"
expect 1 "does not verify"  "a tampered APK fails in ordinary mode"                   -- "$check" "$work/tampered.apk"
expect 1 "does not verify"  "a tampered APK fails in distribution mode"               -- "$check" --distribution --signer "$UP" "$work/tampered.apk"

# No expected fingerprint anywhere (no flag, no env, no android/upload-cert.sha256): distribution must fail.
mkdir -p "$work/bare/scripts" "$work/bare/android"; cp "$check" "$work/bare/scripts/check_apk.sh"
expect 1 "no expected signer fingerprint" "distribution fails when no fingerprint is configured" -- env -u EXPECTED_SIGNER_SHA256 "$work/bare/scripts/check_apk.sh" --distribution "$work/upload.apk"

# The committed fingerprint file is a single SHA-256 (64 hex characters).
f="$here/../android/upload-cert.sha256"
expect 0 "" "android/upload-cert.sha256 holds one 64-character hex fingerprint" -- bash -c "[ \"\$(wc -l < '$f')\" = 1 ] && grep -Eq '^[0-9a-f]{64}\$' '$f'"

echo; echo "$pass passed, $failn failed"
[ "$failn" = 0 ]
