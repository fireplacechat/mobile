# Search inside a conversation (#246)

The profile's **Search** tile (1:1) or Group info's **Search** row opens a bar in place of the conversation's title. It has:

- the field;
- the count ("1 of 2");
- **↑** for an older match and **↓** for a newer one;
- a close button. Back also closes the search.

Typing jumps to the newest match. Steps load older history when a match is outside it, scroll the conversation in place and light the match up. The matching words are marked in the bubbles.

| Image | What it shows |
| --- | --- |
| `*-profile.png` | The profile opened from the chat, with Search beside Message and Mute |
| `*-match.png` | "garden": the newest of two matches, marked and lit up |
| `*-older.png` | After ↑: the older match, from beyond the history loaded at first |
| `*-none.png` | No matches |
| `jump.gif` | The step to the older match |

`TZ=UTC flutter test scripts/render/conversation_search_render_test.dart`, then `python scripts/render/frames_to_gif.py build/frames/conversation-search`. These are widget renders with fictional messages.
