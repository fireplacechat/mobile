#!/usr/bin/env bash
# Build the crates.io pin for flutter test on Linux or Windows (Git Bash).
set -euo pipefail
cd "$(dirname "$0")/../packages/fireplace_native/rust"

case "$(uname -s)" in
  Linux) library=libfireplace_crypto.so ;;
  MINGW*|MSYS*|CYGWIN*) library=fireplace_crypto.dll ;;
  *) echo "The crypto host build supports Linux and Windows only." >&2; exit 1 ;;
esac

cargo build --package fireplace-crypto --lib --release --locked \
  --target-dir ../../../build/fireplace_crypto/host
test -f "../../../build/fireplace_crypto/host/release/$library"
