# Chat list, held-message menu, emoji picker and reply bubbles

This change rebuilds four surfaces against the owner's reference screenshots
(a Telegram chat list and Signal's held-message menu, emoji picker and quoted
replies), keeping Fireplace's colours, protocol and privacy rules. Sizes were
measured from the screenshots pixel by pixel and cross-checked with the
constants in the public Signal-iOS source. No wire format, key handling, rule,
server field or package changed.

## What changed

- **Chat list.** A 104-point row: a 60-point orange avatar with white initials
  (no photos), the name and a short date on one line, a two-line preview, and
  a filled unread count beside the second line. Counts still come from the
  decrypted local history. The row's menu button is gone; mute is a long press,
  a right click, the context-menu key, or a screen-reader action.
- **Held-message menu.** A 320 x 56 reaction bar, the message, and a 250-point
  action list with 50-point rows, twelve points apart and sixteen from the
  edge. A message with room for its menu does not move. One too low for it
  slides up only as far as needed and slides back when the menu closes; the
  conversation underneath never scrolls.
- **Emoji picker.** The "more" button swaps the bar and list for a sheet in
  the same overlay: a search field, recent reactions, eight categories in a
  seven-column grid and a category bar. It rests at about half the screen,
  opens fully when searching or pulled up, and closes when dragged down,
  tapped outside or on Escape. Search runs over a table bundled with the app.
- **Replies.** A reply bubble is as wide as the wider of its quote and its own
  text, so a short reply stays small. The quote is a tinted panel with a
  four-point stripe, the author and up to two lines of the original.

## Renders

Real widgets, fictional fixtures, 375 x 812 points at three pixels per point,
UTC, with the installed Windows emoji font as a test-only fallback.

| State | Screenshot |
| --- | --- |
| Chat list | [Dark](chat-list-dark.png) · [Light](chat-list-light.png) |
| Held message, received | [Dark](message-menu-incoming-dark.png) |
| Held message, sent | [Light](message-menu-outgoing-light.png) |
| Emoji picker with recents | [Dark](emoji-picker-dark.png) |
| Emoji search | [Light](emoji-search-light.png) |
| Replies of different lengths | [Dark](replies-dark.png) · [Light](replies-light.png) |

Side-by-side and overlay comparisons were made with
`scripts/render/compare_reference.py`. They are not in the repository because
the reference screenshots show other people's names, photos and messages.

## Measured values

| Element | Reference | This change |
| --- | --- | --- |
| Chat row height, avatar | 104.2, 60 | 104 + hairline, 60 |
| Avatar and text insets | 16, 86.7 | 16, 86 |
| Name / preview / date type | 21, 20, 19 points | same |
| Preview baselines from row top | 57.5, 84.5 | 57.5, 84.5 |
| Unread count | 26-27 circle, 16 from edge | 26, 16 |
| Reaction bar | 320 x 56, 44-point cells, 6 padding | same |
| Gaps bar / message / list | 12, 12 | 12, 12 |
| Action list | 250 wide, 50-point rows, 22-point label | same |
| Emoji sheet top | 373 of 812 | 372.7 |
| Emoji cell, column and row pitch | 38, 50.8, 48 | 38, 50.83, 48 |
| Category button and pitch | 40, 44 | 40, 44 |
| Quote stripe, corner, inset | 4, 10, 8 | 4, 10, 8 |

## Differences that remain

- **Typeface.** Renders use Roboto; an iPhone uses San Francisco. Positions and
  sizes match, letter shapes and widths do not. On a phone the system font is
  used.
- **Emoji artwork** is the platform's own.
- **Icons** are Cupertino icons, close to but not the same drawings as the
  reference's system symbols. The category bar's food and symbols icons are
  Material ones.
- **Text size.** The references were taken with enlarged text. Their sizes are
  used at the standard text scale; larger system text scales them further.
- **Chat list.** Initials replace photos and the orange replaces per-person
  colours. A conversation with no messages shows "Encrypted chat" where the
  reference row is empty. Muted and security-warning marks sit after the name.
- **Menu actions** are Fireplace's own (Reply, Edit, Forward, Copy, Select
  text, Select, then Delete for everyone or Report); there is no Info or Pin.
- **Emoji picker.** No skin-tone settings button, so the search field spans the
  sheet. 46 emoji that the existing encrypted reaction format rejects are left
  out, as are skin-tone variants. A held message the sheet would cover rises to
  stay visible; in the reference it stays partly covered.
- **Replies.** The time stays on its own line under the text; Signal puts it
  beside the last line.
- **Timeline inset** is now 16 points (was 12) so a held message does not shift
  sideways when lifted.

## Validation

Pinned Flutter 3.47.6, Windows host.

| Check | Result |
| --- | --- |
| `dart format` and `flutter analyze` | Clean |
| Full non-timing suite | 883 passed, 1 existing skip |
| Timing suite, one at a time | 17 passed |
| Render catalog | 180 passed |
| Layer check and checker tests | Passed |

New tests cover row geometry, initials, unread counts from local history,
muting by long press and by screen reader, the date label, menu geometry, a
held message staying put or rising and returning, Back after the menu closes,
the picker's layout, local search, recents, dismissal, keyboard inset and
enlarged text, the emoji table against reaction validation, and reply sizing.

Not done: physical-device acceptance on iOS or Android.

## AI assistance

Claude Code (Anthropic) wrote the implementation, tests and this report. A
human must review it before merge.
