#!/usr/bin/env bash
set -euo pipefail
selection="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; ds=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d["name"].startswith("iPhone") and d.get("isAvailable",False)]; ds.sort(key=lambda d:d["state"]!="Booted"); d=ds[0]; print(d["udid"]+"\t"+d["state"])')"
IFS=$'\t' read -r uuid state <<< "$selection"
[[ "$uuid" =~ ^[A-Fa-f0-9-]{36}$ ]] || { echo "No valid iPhone simulator." >&2; exit 1; }
if [ "$state" != Booted ]; then xcrun simctl boot "$uuid"; fi
xcrun simctl bootstatus "$uuid" -b
case "$(uname -m)" in
  arm64) target=aarch64-apple-ios-sim ;;
  x86_64) target=x86_64-apple-ios ;;
  *) echo "Unsupported simulator host." >&2; exit 1 ;;
esac
printf 'FP_IOS_SIMULATOR=%s\nFP_IOS_SIM_TARGET=%s\n' "$uuid" "$target" >> "$GITHUB_ENV"
upper="$(tr '[:lower:]-' '[:upper:]_' <<< "$target")"
printf 'CARGO_TARGET_%s_RUNNER=xcrun simctl spawn %s\n' "$upper" "$uuid" >> "$GITHUB_ENV"
