#!/usr/bin/env bash
# Runs only the tests tagged `timing`, one at a time, on an otherwise idle machine.
# Passing the files explicitly matters: `flutter test --tags timing` alone still
# compiles every test file just to filter them, which takes minutes.
set -euo pipefail
cd "$(dirname "$0")/.."
export TZ=UTC
files=$(grep -rlE "tags: 'timing'|@Tags\(\['timing'\]\)" test | sort)
[ -n "$files" ] || { echo "no tests are tagged 'timing'"; exit 1; }
echo "timing tests in:"; echo "$files" | sed 's/^/  /'
# shellcheck disable=SC2086
flutter test --tags timing --concurrency=1 $files
