#!/usr/bin/env bash
# macOS only, run by the owner or an owner-dispatched workflow. The library
# and header both come from the plugin's exact registry pin, never a sibling.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[ "$(uname -s)" = Darwin ] || { echo "The iOS build requires macOS and Xcode." >&2; exit 1; }
cd "$root/packages/fireplace_native/rust"
export IPHONEOS_DEPLOYMENT_TARGET=15.0
targets=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios)
rustup toolchain install 1.98.1 --profile minimal --no-self-update
rustup +1.98.1 target add "${targets[@]}"
target_dir="$root/build/fireplace_crypto/ios"
for target in "${targets[@]}"; do
  cargo build --package fireplace-crypto --lib --release --locked \
    --target "$target" --target-dir "$target_dir"
done
crate_dir="$(cargo metadata --locked --format-version 1 | python3 -c 'import json,pathlib,sys; p=next(p for p in json.load(sys.stdin)["packages"] if p["name"]=="fireplace-crypto"); print(pathlib.Path(p["manifest_path"]).parent)')"
stage="$(mktemp -d "$target_dir/xcframework.XXXXXX")"
mkdir -p "$stage/headers" "$stage/simulator"
cp "$crate_dir/include/fireplace_crypto.h" "$stage/headers/"
cat > "$stage/headers/module.modulemap" <<'MODULE'
module FireplaceCrypto {
  header "fireplace_crypto.h"
  export *
}
MODULE
xcrun lipo -create \
  "$target_dir/aarch64-apple-ios-sim/release/libfireplace_crypto.a" \
  "$target_dir/x86_64-apple-ios/release/libfireplace_crypto.a" \
  -output "$stage/simulator/libfireplace_crypto.a"
frameworks="$root/packages/fireplace_native/ios/fireplace_native/Frameworks"
mkdir -p "$frameworks"
output="$frameworks/FireplaceCrypto.xcframework"
if [ -e "$output" ]; then
  mv "$output" "$stage/previous.xcframework"
fi
xcodebuild -create-xcframework \
  -library "$target_dir/aarch64-apple-ios/release/libfireplace_crypto.a" -headers "$stage/headers" \
  -library "$stage/simulator/libfireplace_crypto.a" -headers "$stage/headers" \
  -output "$output"
# A normal app/extension build must contain no test-stream exports.
for target in "${targets[@]}"; do
  if xcrun nm -gU "$target_dir/$target/release/libfireplace_crypto.a" | grep -E ' _fp_(set|clear)_test_rng$'; then
    echo "A test random-stream symbol reached the iOS library." >&2
    exit 1
  fi
done
