# Issue 251: the jump highlight as a full-width band

Each image puts `origin/main` (Before) beside this branch (After), at the
moment the highlight has fully faded in.

| Image | What it shows |
|---|---|
| `light-chat-portrait.png`, `dark-chat-portrait.png` | A 1:1 chat opened at a search result ("Are we still on for Saturday?"), 390 x 780 with a 47 px top inset |
| `light-chat-landscape.png`, `dark-chat-landscape.png` | The same jump at 812 x 375 with 47 px side safe areas |
| `light-group-portrait.png`, `dark-group-portrait.png` | A group jumped to its pinned message from the pinned bar |
| `light-group-landscape.png`, `dark-group-landscape.png` | The same group jump in landscape with side safe areas |

Groups have no search jump yet (that comes with #246), so the group images
use the pinned-message jump, which draws the same highlight.

Made with:

```sh
bash scripts/build_crypto_host.sh
RENDER_EMOJI_FONT=C:/Windows/Fonts/seguiemj.ttf TZ=UTC flutter test scripts/render/render_jump_band_test.dart
```

once on `origin/main` (with the script copied in) and once on this branch.
That writes `build/renders/jump-band/`. A short PIL script then put the two
side by side. The group images use real group services over the Rust MLS core,
so their times are the time of the run and differ slightly between images.
These are widget renders, not device screenshots, and the names are fictional.
