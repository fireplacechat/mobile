#!/usr/bin/env bash
set -euo pipefail
app="${1:?Expected Runner.app}"
diagnostics="${2:-off}"
extension="$app/PlugIns/NotificationService.appex"
test -d "$extension" || { echo 'The notification extension is missing.' >&2; exit 1; }
root="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${3:-}" = signed ]; then
  python3 "$root/scripts/check_ios_upgrade.py" "$app" --signed
else
  python3 "$root/scripts/check_ios_upgrade.py" "$app"
fi
stage="$(mktemp -d "${TMPDIR:-/tmp}/fireplace-preview-check.XXXXXX")"
for bundle in "$app" "$extension"; do
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Info.plist")"
  xcrun strings "$bundle/$executable" > "$stage/strings.txt"
  if [ "$diagnostics" = on ]; then
    grep -qF preview-diagnostics-v1.json "$stage/strings.txt" || { echo 'Diagnostic build flag is missing.' >&2; exit 1; }
  else
    if grep -qF preview-diagnostics-v1.json "$stage/strings.txt"; then
      echo 'Test diagnostics reached a normal Release build.' >&2; exit 1
    fi
  fi
done
binary="$extension/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$extension/Info.plist")"
xcrun otool -L "$binary" > "$stage/links.txt"
if grep -Ei 'Flutter|Firebase|sqlite' "$stage/links.txt"; then
  echo 'The extension links a forbidden runtime or database.' >&2; exit 1
fi
xcrun nm -gU "$binary" > "$stage/symbols.txt"
for symbol in free session_load session_destroy session_decrypt_handle; do
  grep -Eq "[[:space:]]_fp_${symbol}$" "$stage/symbols.txt" || { echo "Missing crypto symbol: $symbol" >&2; exit 1; }
done
if grep -E '_fp_(set|clear)_test_rng|_OBJC_CLASS_\$_FIR|FlutterEngine|sqlite3_' "$stage/symbols.txt"; then
  echo 'Forbidden SDK or test-stream symbols reached the extension.' >&2; exit 1
fi
for key in CFBundleShortVersionString CFBundleVersion; do
  test "$(/usr/libexec/PlistBuddy -c "Print :$key" "$app/Info.plist")" = \
    "$(/usr/libexec/PlistBuddy -c "Print :$key" "$extension/Info.plist")" || { echo 'App and extension versions differ.' >&2; exit 1; }
done
echo 'iOS extension ABI, runtime isolation, versions and diagnostic flag checked'
