#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk_dir" && -f "$project_dir/android/local.properties" ]]; then
  sdk_dir="$(sed -n 's/^sdk.dir=//p' "$project_dir/android/local.properties")"
fi
if [[ -z "$sdk_dir" || ! -x "$sdk_dir/emulator/emulator" ]]; then
  echo 'Set ANDROID_HOME to your Android SDK directory.' >&2
  exit 1
fi

# SwiftShader in Emulator 37.2.12 crashes on this Fedora machine during boot.
# Use host OpenGL, disable Vulkan, and avoid loading a stale snapshot.
exec "$sdk_dir/emulator/emulator" -avd "${FIREPLACE_AVD:-fireplace}" \
  -memory 2560 -gpu host -feature -Vulkan -no-snapshot -no-boot-anim \
  -no-audio "$@"
