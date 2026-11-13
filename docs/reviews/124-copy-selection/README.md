# Copy selected messages — issue #124

The production selection bar adds the held-message menu's copy icon immediately
left of Forward. Delete, Forward, Cancel, Delete All and the centered selected
count keep their positions. Copying leaves the selection active.

These are actual Flutter widget renders with fictional local fixtures, captured
on Windows. Each column explicitly targets the named platform, with phone safe
areas and 135% text. Latin text uses the SDK's Roboto preview font; emoji use an
installed preview fallback. No font is added to the app. These are not physical
Android or iPhone screenshots.

| State | Android, 360 × 800 | iOS, 375 × 812 |
| --- | --- | --- |
| One selected, light | ![Android single selection](android-single-light.png) | ![iOS single selection](ios-single-light.png) |
| Multiple selected, light | ![Android multiple selection](android-multiple-light.png) | ![iOS multiple selection](ios-multiple-light.png) |
| Copied, light | ![Android copy feedback](android-copied-light.png) | ![iOS copy feedback](ios-copied-light.png) |
| One selected, dark | ![Android single selection in dark theme](android-single-dark.png) | ![iOS single selection in dark theme](ios-single-dark.png) |
| Multiple selected, dark | ![Android multiple selection in dark theme](android-multiple-dark.png) | ![iOS multiple selection in dark theme](ios-multiple-dark.png) |
| Copied, dark | ![Android copy feedback in dark theme](android-copied-dark.png) | ![iOS copy feedback in dark theme](ios-copied-dark.png) |

The platform render cases assert the actual target platform. Interaction tests
check plain text and display order, unreadable/deleted exclusions, empty copy,
failure and retry, retained selection and exact held-menu icon reuse. Geometry
checks cover both platforms and a 320-point phone at 200% text, including 48-point
targets and the unchanged center and outer controls.
