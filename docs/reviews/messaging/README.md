# Messaging review

Four stacked draft changes implement the held-message menu, local selection and
deletion, encrypted reactions and sender-requested deletion, and composer/gesture
polish. Merge in that order. This is the requested messaging scope, not a claim of
complete Signal feature parity. The subsequent quoted-reply and editing drafts
extend this stack; attachments remain outside this work.

The implementation extends Fireplace's Flutter widgets and local store. Signal's
[iOS](https://github.com/signalapp/Signal-iOS) and
[Android](https://github.com/signalapp/Signal-Android) applications informed the
interaction reference; no native source text is included. Colors and the send
button use Fireplace's theme. The
[protocol decision](../../decisions/0021-reactions-and-remote-delete.md) describes
compatibility, ordering, linked-device copies, deletion authorization and failure
recovery. Old clients cannot honor the new controls.

## Screenshots

All images are actual Flutter renders of fictional UiFixture data. The first two
stages were captured from their own fresh checkouts; later images show the final
stack. The installed Windows emoji font is a render-only fallback and is not
bundled. Native emoji appearance and gesture feel still need physical iOS/Android
device review.

| State | Render |
| --- | --- |
| Initial menu, light | [Image](01-menu-light.png) |
| Initial menu, dark | [Image](01-menu-dark.png) |
| Multi-select | [Image](02-selection-light.png) |
| Local deletion confirmation | [Image](02-delete-confirmation-dark.png) |
| Shared reactions | [Image](03-reactions-dark.png) |
| Expanded reaction picker | [Image](03-picker-light.png) |
| Enlarged-text reaction picker | [Image](03-picker-large-light.png) |
| Remote deletion confirmation | [Image](03-remote-confirmation-dark.png) |
| Deleted-message placeholder | [Image](03-remote-deleted-light.png) |
| Final held-message menu | [Image](04-menu-light.png) |
| Final text composer | [Image](04-composer-dark.png) |

## Validation

Validation uses pinned Flutter 3.47.6, UTC, and fresh local clones for each draft.

| Check | Result |
| --- | --- |
| Menu draft | Format/analyze clean; 24 targeted tests; 6 renders |
| Local deletion draft | Format/analyze clean; 19 targeted tests; 6 renders |
| Encrypted controls draft | Format/analyze clean; 11 targeted tests |
| Full stack, non-timing suite | 811 passed, 1 existing skip, including randomized chat simulation |
| Timing suite, run alone with concurrency 1 | 16 passed |
| Final bubble/selection/inventory checks | 30 passed after the last placement change |
| Enlarged picker and reaction interactions | 6 passed, including the additional enlarged-text test |
| Render catalog | 152 cases passed; all 152 final PNG hashes matched the fresh checkout |
| Layer checker and its tests | Passed; 10 checker tests passed |
| Android build refusal script | All 8 refusal checks passed; no signing/build performed |
| Separate backend rules suite | 74 passed; no rule changes |

The full suite ran at `a82858e`; subsequent presentation fixes were checked with
the targeted suites above and repeated renders. No protocol code changed after
the full run. Format and `flutter analyze` were also repeated after these fixes.

The backend suite ran from the existing separate backend checkout, with
`firebase emulators:exec --only firestore --project demo-fireplace-test`, a
temporary local config using unused ports, and `npm test` in its `firebase`
directory. No production endpoint, deployment, rule edit or live account was
used. Permission-denied logs are expected from rejection tests.

Render reproduction: set `TZ=UTC` and
`RENDER_EMOJI_FONT=C:/Windows/Fonts/seguiemj.ttf`, then run
`flutter test scripts/render/render_screens_test.dart`. Compare SHA-256 hashes
of `build/renders/*.png` in identical font/SDK environments.
The final catalog hashes are in [render-sha256.csv](render-sha256.csv).

## AI assistance

OpenAI Codex wrote the implementation, tests, design note and review material.
Human review, physical-device acceptance and CLA confirmation remain pending.
Nothing was merged or deployed.
