# Settings redesign (issue 249)

Settings now opens on a profile card and six categories. Each category opens
its own page with the same rows as before, in rounded cards with plain outline icons
and the current value on the row. Open-source licences are back under Help and
about.

All images are renders of the real widgets with fictional data, 390 × 780
points (320 × 640 for the large-text ones) at 2× density, with a 47-point top
inset. They are not device screenshots.

| Image | What it shows |
| --- | --- |
| `light-main-before-after.png`, `dark-main-before-after.png` | The main page on `main` (left) and on this branch (right) |
| `light-narrow-large-before-after.png`, `dark-narrow-large-before-after.png` | The same at 320 points wide with 200% text |
| `ios-{light,dark}-main.png` | The main page |
| `ios-{light,dark}-{account,privacy,notifications,appearance,devices,help}.png` | Each category page |
| `ios-{light,dark}-notifications-scrolled.png` | A page scrolled: the large title has gone and the bar shows it small |
| `ios-light-licences.png` | Flutter's licence page, opened from Help and about. A test has no licences registered, so the list is empty here; the app lists every package |
| `android-{light,dark}-{main,privacy}.png` | The same on Android (back arrow, Android wording) |
| `narrow-large-light-*.png`, `narrow-large-dark-main.png` | Every page at 320 points with 200% text. At this size the icons step aside so whole words fit |
| `moving-through-pages.gif` | Opening Privacy and security, Appearance and Help and about, and going back |

Made with:

```sh
TZ=UTC flutter test scripts/render/settings_redesign_test.dart
python scripts/render/frames_to_gif.py build/frames/settings-pages
```

The renders are written to `build/settings-redesign/` and the frames to
`build/frames/settings-pages/`. The "before" images were rendered the same
way from `origin/main` and placed side by side with Pillow.
