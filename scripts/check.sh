#!/usr/bin/env bash
# The same checks CI runs, in one command. Run it before you push.
#   scripts/check.sh          format, analyze, layer check and all tests
#   scripts/check.sh quick    everything except the tests (about 20 seconds)
set -euo pipefail
cd "$(dirname "$0")/.."
export TZ=UTC

echo "== format"
dart format --output=none --set-exit-if-changed lib test scripts
echo "== analyze"
flutter analyze
echo "== layers"
python3 scripts/check_layout.py .
python3 scripts/test_check_layout.py
bash scripts/test_build_aab.sh
[ "${1:-}" = quick ] && { echo "quick checks passed"; exit 0; }

echo "== tests (parallel)"
flutter test --exclude-tags timing
echo "== tests that measure real time (one at a time)"
scripts/run_timing_tests.sh
echo "all checks passed"
