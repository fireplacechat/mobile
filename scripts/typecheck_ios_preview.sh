#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
headers="$root/packages/fireplace_native/ios/fireplace_native/Frameworks/FireplaceCrypto.xcframework/ios-arm64_x86_64-simulator/Headers"
case "$(uname -m)" in
  arm64) target=arm64-apple-ios15.0-simulator ;;
  x86_64) target=x86_64-apple-ios15.0-simulator ;;
  *) echo 'Unsupported Apple simulator host.' >&2; exit 1 ;;
esac
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find ios/NotificationService -name '*.swift' -type f | sort)
xcrun swiftc -typecheck -swift-version 5 -target "$target" \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -I "$headers" \
  -D PREVIEW_DIAGNOSTICS "${sources[@]}"
