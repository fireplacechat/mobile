#!/usr/bin/env bash
# Build the crates.io pin for flutter test on Linux or Windows (Git Bash).
set -euo pipefail
cd "$(dirname "$0")/../packages/fireplace_native/rust"

case "$(uname -s)" in
  Linux) library=libfireplace_crypto.so ;;
  MINGW*|MSYS*|CYGWIN*) library=fireplace_crypto.dll ;;
  *) echo "The crypto host build supports Linux and Windows only." >&2; exit 1 ;;
esac

features=()
package=fireplace-crypto
case "${1:-}" in
  '') target=host ;;
  test-rng)
    target=host-test-rng
    package=fireplace-native-build
    features=(--features test-rng)
    library="${library/fireplace_crypto/fireplace_crypto_tests}"
    ;;
  *) echo "usage: bash scripts/build_crypto_host.sh [test-rng]" >&2; exit 64 ;;
esac
[ "$#" -le 1 ] || { echo "Too many build arguments." >&2; exit 64; }

cargo build --package "$package" --lib --release --locked \
  "${features[@]}" --target-dir "../../../build/fireplace_crypto/$target"
test -f "../../../build/fireplace_crypto/$target/release/$library"
