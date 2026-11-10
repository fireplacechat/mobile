# Chat list size, search pill, one accent colour, saved colours

Follow-up to the [messaging layout](../messaging-fidelity/README.md) after the
owner tried it on a phone. No wire format, key handling, rule, server field or
package changed. One new key is written to the device's secret store.

## What changed

- **Chat list size.** The row sizes (21, 20 and 19 point text, 104-point row)
  had been measured from a reference screenshot taken with the largest
  ordinary system text size, then used as the sizes at the standard scale, so
  a phone with that setting enlarged them a second time. The code now holds
  the unscaled sizes (16, 15 and 14 point text, a 77-point row, a 20-point
  count) and the system setting scales them. At a scale of 1.35 the row is 104
  points again.
- **Search.** A pill with a centred magnifier and "Search". When it is tapped
  the icon and hint move to the start and a one-point outline in the accent
  colour appears. It is 48 points tall at the standard text size so it remains
  an easy target.
- **One accent colour.** The colour chosen for "Your messages" under Chat
  colors is the theme's primary colour: avatars, sent bubbles, the send
  button, unread counts, New chat, filled buttons and the outline of a
  focused text box. Links and text buttons use a lighter tint in the dark
  theme (and a darker ember in the light one) so they keep 4.5:1 contrast on
  the page and on panels. The logo keeps its own orange.
- **Colour picker.** Each choice is a block of the colour with its name
  inside, three across (fewer with enlarged text). The chosen block has a
  ring; its space is always reserved, so choosing does not move anything.
- **Colours are kept.** The two colour names are saved in the device's secret
  store under `ui:chat-colors`, beside the theme (`ui:theme-mode`), and read
  when the app starts. Nothing is sent to the server. A failed save says so in
  plain words and the choice still lasts until the app closes.
- **Composer.** The message box shows a one-point outline in the accent
  colour while focused.
- **Latest messages.** The button has a half-point black outline, so it stays
  distinct over a bubble of the same colour.
- **Times.** "3:03 pm", not "3:03 PM", in the chat list, in bubbles and in
  edit history.

## A decision to review

Chat colours used to be an in-memory choice tied to the signed-in account:
they reset on sign-out and when another account signed in (review R07). They
now belong to the installation, as the theme does: they survive a restart,
signing out and a change of account, and they colour the signed-out screens.
Account deletion still clears them with the rest of the secret store. The
tests for the old behaviour are replaced by
`test/view/settings/chat_colors_persistence_test.dart`.

## Renders

Real widgets, fictional fixtures, UTC. The `reference` states are 375 x 812
points at three pixels per point with a text scale of 1.35; the others are
390 x 844 at two. The `accent-*` states start from a secret store that already
holds a saved colour, as an earlier run of the app would have left it.

| State | Screenshot |
| --- | --- |
| Chat list at the reference text size, default colour | [Dark](chat-list-reference-dark.png) · [Light](chat-list-reference-light.png) |
| Chat list, standard text size, other colours | [Ocean](chat-list-ocean-dark.png) · [Forest](chat-list-forest-light.png) · [Plum](chat-list-plum-dark.png) |
| Search while typing (outline) | [Dark](search-typing-ocean-dark.png) · [Light](search-typing-ocean-light.png) |
| Chat colors, default | [Dark](chat-colors-dark.png) |
| Chat colors, Ocean and Forest chosen | [Dark](chat-colors-ocean-dark.png) · [Light](chat-colors-ocean-light.png) |
| Conversation, default colour | [Dark](conversation-dark.png) |
| Conversation while typing (outline, send button, sent bubbles) | [Dark](conversation-typing-ocean-dark.png) · [Light](conversation-typing-ocean-light.png) |
| Latest messages button | [Dark](latest-messages-ocean-dark.png) |
| Sign-in while typing (outline, button, link) | [Light](sign-in-typing-ocean-light.png) |

## Differences that remain

- **Search height.** 48 points at the standard text size; the reference is
  about 36 scaled to 44. The taller pill keeps the tap-target guideline that
  the accessibility tests enforce.
- **First frame.** The saved colour is read just after the app starts, so the
  splash is drawn with the default colour and the theme eases to the saved one
  within a fraction of a second.
- **Dark theme, Stone.** As an outline, the grey Stone colour is faint on dark
  panels. It is the colour as chosen; only text uses a lighter tint.
- **Typeface and icons** differ from a phone's, as in the earlier report.
- **Other screens' sizes** (bubbles, menus, the picker) are unchanged.

## Validation

Pinned Flutter 3.47.6, Windows host.

| Check | Result |
| --- | --- |
| `scripts/check.sh` (format, analyze, layers, all tests, timing tests) | Passed |
| Render catalog | 196 passed, twice, with identical file hashes |

On Windows `scripts/check_layout.py` needs `PYTHONUTF8=1` to read the sources;
the script is unchanged.

New or changed tests cover the row geometry at the standard scale and at
1.35, the lower-case times, the search pill at rest, focused, filled, cleared
and with enlarged text, the theme built from each colour and its contrast, the
running app recolouring when a colour is chosen, the picker's blocks and ring,
the composer outline, the Latest messages outline, and saving, restoring,
resetting, damaged values, an unreadable store, a failed save and a change of
account for the saved colours.

Not done: physical-device acceptance on iOS or Android.

## AI assistance

Claude Code (Anthropic) wrote the implementation, tests and this report. A
human must review it before merge.
