# Fireplace: guide for contributors and AI coding tools

Read this first. It is the single source of truth for how we work in this repository; `CLAUDE.md` imports it, and Codex reads it as `AGENTS.md`.
Humans: start with [CONTRIBUTING.md](.github/CONTRIBUTING.md). Documentation index: [docs/README.md](docs/README.md).

## What this is
Fireplace is an open-source (AGPL-3.0), end-to-end encrypted 1:1 messenger: Flutter + Firebase (Spark free plan only), iOS first, then Android,
username + password (no phone number or email), hybrid post-quantum cryptography (X25519 + ML-KEM-768, Ed25519 + ML-DSA-65, double ratchet).
Goal: a messenger that feels instantly familiar, built to be free, open, no ads, no tracking, small and dependable.

## Commands
Flutter is pinned in `pubspec.yaml` (`environment: flutter:`); use that version. CI reads the same value.
```sh
flutter pub get
flutter analyze                       # must be clean
dart format --output=none --set-exit-if-changed lib test scripts
scripts/check.sh                      # format, analyze, layers and every test, exactly as CI runs them (add `quick` to skip tests)
TZ=UTC flutter test --exclude-tags timing   # tests in parallel
scripts/run_timing_tests.sh           # tests that measure real time, one at a time; they flake when the machine is busy
TZ=UTC flutter test scripts/render/render_screens_test.dart   # screen previews; output must be byte-identical across runs
scripts/check_apk.sh <apk>               # permissions, backup, signer; scripts/test_check_apk.sh tests the checker
```
Run `flutter analyze` and `dart format` on every file you touch, tests included, before you finish. Both checks must pass.

## Layout
`lib/src/crypto/` protocol, keys and ratchet · `lib/src/model/<feature>/` logic and Firebase access ·
`lib/src/db/` local storage · `lib/src/view/<feature>/` screens · `lib/src/styles/` design · `lib/src/widgets/` shared widgets.
`lib/src/app.dart` selects the first screen. `lib/src/app/providers.dart` wires session resources and providers.
See [architecture](docs/architecture.md); run `python3 scripts/check_layout.py .` to check migrated layers.
Backend rules/operator tooling and website/legal sources are maintained separately in private repositories.

## Rules that are not negotiable
- **Privacy first.** No analytics, no crash reporting, no tracking, no third-party SDKs that phone home. Features that need message text (search,
  unread counts, previews, notices) run on the device from the encrypted local history; they add no server fields and no plaintext on disk.
  No status indicators (typing, read receipts, delivered ticks, online / last seen).
- **Never commit** passwords, private keys, signing material, recovery codes, service-account files, tokens or real user data. Fixtures are fictional.
- **Do not change** wire formats, key handling, authentication or Firestore rules without a design note in `docs/decisions/` and tests.
- **Free plan only.** No paid Firebase features, no new services. Do not add packages without the owner's approval; say why one is needed.
- **No macOS CI runs unless the owner asks for one.** `ios.yml` is manual-only; do not add push, pull-request or schedule triggers to it, and do not dispatch it yourself.
- **The owner deploys production.** Firebase deploys, store submissions, signing and publishing the website are done by the owner, never by an assistant.
- **Public wording** (website, README, store text) is shown to the owner before it is published. Plain, short, neutral. No founder name, no
  commentary about weaknesses, no competitor mentions on the main site, no claim that an audit has finished.
- **Message limit:** 16,384 characters, counted as Unicode characters (`lib/src/model/chat/message_limits.dart`).

## Code conventions
Short version; the details and reasons are in [docs/development/coding-style.md](docs/development/coding-style.md).
- **Riverpod 3.** `AsyncValue.value` (there is no `valueOrNull`); `Notifier` / `NotifierProvider`; check `ref.mounted` after any `await` in a notifier;
  `ref.watch(provider.select(...))` to rebuild on a field only. Account-scoped state must watch the signed-in uid so it resets on sign-out.
- **Immutable state.** State classes have only `final` fields and change through `copyWith` or a new value. Mutable collections stay inside one function.
- **Strong types** over primitives (`Duration`, not `int` milliseconds; enums, not strings).
- **Widgets are classes**, not functions that return widgets (except `builder` callbacks). Do not make a private widget for something used once; do make
  a `StatelessWidget` for anything reused. Keep files focused: when a file passes about 500 lines, split it.
- **Collection `if` / `for`** in widget lists instead of building a list by hand.
- **Single quotes, package imports** (`package:fireplace/...`), trailing commas drive the formatter.
- **Async hygiene.** Cancel every subscription and timer in `dispose`. Never leave an unbounded loop. Bound anything that works on user text or on
  history (a message formatter that was quadratic on nested markers once froze the whole chat list).
- **Errors** shown to people are plain words, never a raw exception. Unknown outcomes (a send that may have reached the server) are never retried
  automatically; the user decides.
- **Comments** explain why, not what; wrap them at the same width as code.

## Tests
- A test that asserts on elapsed time (a stopwatch, a delay, a speed threshold) must be tagged `timing` (`tags: 'timing'` on the test, or `@Tags(['timing'])` on the file). Tagged tests run alone and one at a time; an untagged timing test will flake in the parallel run.
- CI runs `static`, three `unit` shards and `timing` side by side, and a final job named `test` that branch protection requires. Do not rename or remove that job.
- Keep each test file under about 60 seconds. One huge file cannot be shared across shards and sets the length of the whole run.
- Add a test for every fix and every behaviour change. Prefer testing real logic: fake Firebase at its edge (`fake_cloud_firestore`, memory secret
  store), not the service as a whole. `UiFixture` (`test/support/ui_fixture.dart`) is for layout and interaction tests.
- Widget tests wait for isolates with `tester.runAsync`; dialogs need `ensureVisible` before taps; use `pumpAndSettle` after navigation.
- UI changes need a screenshot or the render output from `scripts/render/` in the pull request.
- The randomized chat simulation (`test/model/chat/chat_simulation_test.dart`) and the rules tests protect the protocol; keep them green.

## Working together
- Humans and AI tools both work here. **Disclose AI assistance** in the pull request ([AI_POLICY.md](.github/AI_POLICY.md)); a human must understand and be able to
  explain every change.
- Small, focused pull requests. Work in a branch or a git worktree, never directly on `main` for code. Do not merge or push `main` yourself unless asked.
- Reviews are patches the other side can apply: tests and fixes in separate files, each verified in a fresh clone.
- Commit messages say what and why in plain words. Add the attribution trailer your tool is configured to add.
