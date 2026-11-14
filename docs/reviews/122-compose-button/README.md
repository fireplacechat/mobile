# Round compose button (#122)

The owner selected the classic speech-bubble-plus icon from their reference,
replacing the pencil originally proposed in the issue. The outline is traced
into a 24-point vector; the round button is 50 points across, uses the selected
theme accent, and keeps the accessible name **New chat**. Navigation is unchanged.

These are real Flutter widget renders using fictional accounts and messages.
The supplied private screenshot and generated design concepts are not included.

| Theme | Reference-size screen | 320-wide screen, 200% text |
| --- | --- | --- |
| Light | [Light](light.png) | [Narrow light](narrow-light.png) |
| Dark | [Dark](dark.png) | [Narrow dark](narrow-dark.png) |

Regenerate with `TZ=UTC flutter test scripts/render/render_screens_test.dart
--name chat-list --reporter expanded`. Sources are in `build/renders/`;
the reference-size cases use 375 × 812 points at three pixels per point.

The compose-button tests cover both themes, the default and Ocean accents,
the labelled 48-point Android tap-target guideline, enlarged text, and starting
the existing chat flow. Physical-device verification remains pending.
