# Quoted replies and sent-message editing

These two drafts extend the messaging stack from PRs 45–48. The reply draft adds
encrypted quote snapshots, a cancellable composer preview, Reply menu and
accessibility actions, swipe-right composition, and sent quotes. The editing
draft adds double-tap/menu editing, an independent edit draft, checkmark save,
cancel restoring the ordinary draft, an Edited label and version history. It
also makes quote taps scroll within the full timeline, including lazy rows.

The interaction reference is Signal iOS. Fireplace keeps its colors, protocol,
privacy rules and attachment-free scope. This report does not claim exhaustive
pixel or feature parity. Physical iOS/Android gesture and native-font acceptance
remains a human review step.

Read [decision 0022](../../decisions/0022-quoted-replies-and-message-edits.md)
for v3 content payloads, bounded snapshots/history, author validation, concurrent
linked-device ordering, deletion dominance, compatibility and failure recovery.
Ordinary text remains v1. No new Firestore fields, rules, keys or packages.

## Renders

Actual Flutter screenshots, fictional fixtures, UTC and the installed Windows
emoji font as a test-only fallback. No font is bundled.

| State | Screenshot |
| --- | --- |
| Reply composer | [Dark](reply-compose-dark.png) |
| Sent quote | [Light](reply-sent-light.png) |
| Tap to original | [Dark](reply-original-dark.png) |
| Enlarged reply composer | [Light](reply-large-light.png) |
| Editing | [Dark](edit-compose-dark.png) |
| Edited bubble | [Light](edit-saved-light.png) |
| Edit history | [Light](edit-history-light.png) |
| Enlarged edit composer | [Dark](edit-large-dark.png) |

## Validation

Pinned Flutter 3.47.6. Each draft was checked in a fresh local clone.
The reply draft passed format/analyze, 58 targeted tests, nine menu/accessibility
edge tests and eight reply renders. The additional accessibility inventory now
includes Reply.

| Check | Result |
| --- | --- |
| Final format and `flutter analyze` | Clean |
| Full non-timing suite, including chat simulations | 834 passed, 1 existing skip |
| Timing suite, run alone with concurrency 1 | 16 passed |
| Render catalog | 168 passed; every PNG hash matched the fresh checkout |
| Layer check and checker tests | Passed; 10 checker tests |
| Android build refusal checks | All 8 passed; no signing or app build |
| Separate Firestore emulator rules suite | 74 passed, unchanged rules |

The rules run used a demo project and unused local emulator ports in the separate
backend checkout. No production endpoint or deployment was used. Tests use
fictional data. Existing long-file warnings concern the original crypto source
and the chat screen at approximately 500 lines.

Reproduce the catalog with `TZ=UTC`,
`RENDER_EMOJI_FONT=C:/Windows/Fonts/seguiemj.ttf`, and
`flutter test scripts/render/render_screens_test.dart`.
The final catalog hashes are in [render-sha256.csv](render-sha256.csv).

The earlier messaging PRs were merged during validation. The new branches were
rebased onto that main revision; Git tree hashes confirmed no source changes.

## AI assistance

OpenAI Codex wrote the implementation, design note, tests and review material.
Human review, physical-device acceptance and CLA confirmation remain pending.
Nothing was merged or deployed.
