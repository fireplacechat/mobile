# Offline screen catalog

Run from the app worktree:

```sh
TZ=UTC flutter test scripts/render/render_screens_test.dart --reporter expanded
```

The real widgets render into `build/renders/`; `manifest.json` lists each state,
theme, viewport and fixture time. These files are development artifacts and are
ignored by Git. The test resolves fonts from the installed Flutter SDK through
the package configuration; no user-specific SDK path is embedded. The renderer uses actual blurred shadows rather than the widget-test hard-outline default, and restores that test setting before invariant checks. SDK preview fonts may lack emoji or symbol glyphs; phone font fallback remains a separate acceptance check.

Fixtures in `test/support/ui_fixture.dart` use an in-memory message store and
recording service fakes. Device identifiers, fingerprints, usernames and messages
are fictional. These fakes cannot validate crypto, Firebase rules or native
plugins. There is no Firebase SDK instance or live account connection.

The catalog has 56 states in each theme, including shared components, temporary chat color settings, narrow/enlarged signup and list views, and conversation layouts with keyboard/landscape insets. The core inventory covers: list/data/empty/loading/error,
conversation/data/empty/error, request, requests list, details, verification,
settings, devices, recovery, linking, new device, deletion, resumed deletion,
sign-in, sign-up, startup and auth error. Each test disposes its widget tree and
session and fails on rendering exceptions. Fixture time and pump durations are
fixed; use `TZ=UTC` to keep time labels identical across machines.

Review images visually as well as running tests. Do not accept a screenshot update
as evidence that navigation, selection, focus, sending or accessibility works.

The seven-feature continuation adds formatted messages, muted/unread controls, the back-arrow total, forwarding, global search and message location, name-only/text foreground cards, and device linking at narrow enlarged-text and landscape sizes. Searches use the real isolate scanner over fictional local history; asynchronous search is fully settled before capturing. Every state still has paired light/dark renders.
