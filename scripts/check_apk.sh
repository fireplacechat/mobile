#!/usr/bin/env bash
# Checks a built APK: package id, no backup, that it asks for NO permission outside an allowlist
# (so a plugin update cannot quietly add one), and who signed it.
#   scripts/check_apk.sh build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
#   scripts/check_apk.sh --distribution build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
#
# Signing:
#  * the signature must verify, always;
#  * ordinary mode (CI compile check): a debug-signed APK is allowed but flagged as NOT distributable;
#  * --distribution: the APK must be signed by exactly ONE signer whose certificate SHA-256 equals the
#    expected upload-key fingerprint, and must not be debug-signed. The expected fingerprint is
#    --signer <sha256>, else $EXPECTED_SIGNER_SHA256, else android/upload-cert.sha256 (public
#    information, safe to commit). With no expected fingerprint, distribution mode FAILS.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
distribution=0
expected="${EXPECTED_SIGNER_SHA256:-}"
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --distribution) distribution=1 ;;
    --signer) expected="${2:?--signer needs a SHA-256 fingerprint}"; shift ;;
    *) args+=("$1") ;;
  esac
  shift
done
apk="${args[0]:?usage: check_apk.sh [--distribution] [--signer <sha256>] <apk>}"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android}}"
aapt2="$(ls -d "$sdk"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)"
apksigner="$(ls -d "$sdk"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
[ -x "$aapt2" ] || { echo "aapt2 not found under $sdk/build-tools"; exit 2; }
[ -x "$apksigner" ] || { echo "apksigner not found under $sdk/build-tools"; exit 2; }
if [ -z "$expected" ] && [ "$distribution" = 1 ] && [ -f "$here/../android/upload-cert.sha256" ]; then
  expected="$(head -1 "$here/../android/upload-cert.sha256")"
fi
normalize() { tr 'A-F' 'a-f' <<<"$1" | tr -d ': \t\r\n'; }

allowed='
android.permission.INTERNET
android.permission.CAMERA
android.permission.ACCESS_NETWORK_STATE
android.permission.WAKE_LOCK
android.permission.POST_NOTIFICATIONS
com.google.android.c2dm.permission.RECEIVE
com.google.android.providers.gsf.permission.READ_GSERVICES
com.fireplacechat.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
'
badging="$("$aapt2" dump badging "$apk")"
fail=0
grep -q "^package: name='com.fireplacechat.app'" <<<"$badging" || { echo "FAIL wrong package id"; fail=1; }
for p in $(sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p" <<<"$badging"); do
  grep -qx "$p" <<<"$allowed" || { echo "FAIL unexpected permission: $p"; fail=1; }
done
for p in android.permission.INTERNET android.permission.CAMERA; do
  grep -q "name='$p'" <<<"$badging" || { echo "FAIL missing permission: $p"; fail=1; }
done
tree="$("$aapt2" dump xmltree --file AndroidManifest.xml "$apk")"
grep -q "allowBackup.*=false" <<<"$tree" || { echo "FAIL backups are not disabled"; fail=1; }
grep -q "dataExtractionRules" <<<"$tree" || { echo "FAIL data extraction rules missing"; fail=1; }

# ---- signer ----
if certs="$("$apksigner" verify --print-certs "$apk" 2>&1)"; then
  # apksigner's wording varies by version: "Signer #1 certificate ...", "Signer (minSdkVersion=N,
  # maxSdkVersion=M) certificate ..." and "V3.0 Signer: certificate ..." (one block per signature scheme).
  # Accept all of them, and count signers by distinct certificate digest so the same signer listed for
  # several schemes or SDK ranges is still one signer.
  digests="$(sed -n 's/^\(V[0-9.]* \)\{0,1\}Signer.* certificate SHA-256 digest: //p' <<<"$certs")"
  signers="$(sort -u <<<"$digests" | grep -c . || true)"
  fp="$(normalize "$(head -1 <<<"$digests")")"
  dn="$(sed -n 's/^\(V[0-9.]* \)\{0,1\}Signer.* certificate DN: //p' <<<"$certs" | head -1)"
  if [ -z "$fp" ]; then
    echo "NOTE could not read a signer fingerprint from apksigner; its output starts with:"; head -6 <<<"$certs" | sed 's/^/     /'
  fi
  is_debug=0
  [[ "$dn" == *"CN=Android Debug"* ]] && is_debug=1
  if [ -n "$expected" ] && [ "$(normalize "$expected")" != "$fp" ]; then
    echo "FAIL signed by $fp, expected $(normalize "$expected")"; fail=1
  fi
  if [ "$distribution" = 1 ]; then
    [ "$signers" = 1 ] || { echo "FAIL distribution needs exactly one signer, found $signers"; fail=1; }
    [ "$is_debug" = 0 ] || { echo "FAIL signed with the Android DEBUG key: not distributable"; fail=1; }
    [ -n "$expected" ] || { echo "FAIL no expected signer fingerprint (--signer, EXPECTED_SIGNER_SHA256 or android/upload-cert.sha256)"; fail=1; }
  elif [ "$is_debug" = 1 ]; then
    echo "NOTE signed with the Android DEBUG key: fine for a compile check, NOT distributable (use --distribution)"
  fi
  [ $fail = 0 ] && echo "signer: $fp ($dn)"
else
  echo "FAIL the APK signature does not verify: $(head -1 <<<"$certs")"; fail=1
fi
[ $fail = 0 ] && echo "APK checks passed: $apk" || exit 1
