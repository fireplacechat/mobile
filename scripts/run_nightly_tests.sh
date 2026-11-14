#!/usr/bin/env bash
# Runs only the tests tagged `nightly`: ones that repeat what every pull
# request already checks, at more screen sizes or against the reference crypto.
# The files are passed explicitly, as in run_timing_tests.sh, so the rest of
# the suite is not compiled just to be filtered out.
set -euo pipefail
cd "$(dirname "$0")/.."
export TZ=UTC
files=$(grep -rlE "'nightly'" test | sort)
[ -n "$files" ] || { echo "no tests are tagged 'nightly'"; exit 1; }
echo "nightly tests in:"; echo "$files" | sed 's/^/  /'
# shellcheck disable=SC2086
flutter test --tags nightly $files
