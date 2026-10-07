#!/usr/bin/env bash
# Refusal checks only: temporary repositories, no real key or store build.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
builder="$here/build_aab.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"
for tool in flutter keytool; do
  cat > "$scratch/bin/$tool" <<'STUB'
#!/usr/bin/env bash
echo "unexpected build/signing tool call" >&2
exit 99
STUB
  chmod +x "$scratch/bin/$tool"
done
export PATH="$scratch/bin:$PATH"
git init --quiet --bare -b main "$scratch/origin.git"
git init --quiet -b main "$scratch/repo"
cd "$scratch/repo"
git config user.name 'Release Test'
git config user.email 'release-test@example.invalid'
printf 'version: 1.0.0+1\n' > pubspec.yaml
printf 'android/key.properties\nbuild/\n' > .gitignore
git add pubspec.yaml .gitignore
git commit --quiet -m 'Test fixture'
git remote add origin "$scratch/origin.git"
git push --quiet -u origin main

refuses() {
  local label="$1" expected="$2"
  shift 2
  local status=0
  bash "$builder" "$@" > "$scratch/output" 2>&1 || status=$?
  [ "$status" != 0 ] || { echo "FAIL $label: accepted"; exit 1; }
  grep -Fq "$expected" "$scratch/output" || { echo "FAIL $label: wrong refusal"; cat "$scratch/output"; exit 1; }
  echo "PASS $label"
}
refuses 'bad version string' 'expected version vX.Y.Z' 'v1.0.0;exit'
printf 'dirty\n' > untracked.txt
refuses 'dirty tree' 'working tree must be clean' v1.0.0
rm untracked.txt
refuses 'version mismatch' 'version must match pubspec.yaml' v1.0.1
refuses 'missing key file' 'signing key missing, see docs/development/android-release.md' v1.0.0
git checkout --quiet -b feature/test
refuses 'not on main' 'must be on main' v1.0.0
git checkout --quiet main
mkdir nested
cd nested
refuses 'not at repo root' 'run from the repository root' v1.0.0
cd ..
git checkout --quiet --detach
refuses 'detached HEAD' 'must be on main' v1.0.0
git checkout --quiet main
printf 'stale\n' > tracked.txt
git add tracked.txt
git commit --quiet -m 'Unpushed fixture'
refuses 'main differs from origin' 'main must equal origin/main' v1.0.0
echo 'All app-bundle refusal tests passed.'
