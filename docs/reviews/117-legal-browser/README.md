# Privacy and terms (#117)

Settings now has separate Privacy policy and Terms of use rows inside About,
using the same ListTile layout, section dividers and chevrons as the other
settings. Each row opens its URL directly in the phone's browser. There is no
intermediate page from Settings. An unavailable browser leaves both rows in
place and shows an error beside them for retry.

| State | Light | Dark |
| --- | --- | --- |
| Settings rows | ![Light Settings links](ready-light.png) | ![Dark Settings links](ready-dark.png) |
| Browser unavailable | ![Light browser error](error-light.png) | ![Dark browser error](error-dark.png) |
| Narrow, enlarged text | ![Light enlarged legal page](large-light.png) | ![Dark enlarged legal page](large-dark.png) |

These are real Flutter widget renders with fictional in-memory fixtures. The
error case injects an unavailable browser; rendering never launches a browser.
They are not physical-device screenshots.

```sh
TZ=UTC flutter test scripts/render/render_screens_test.dart --name=settings-legal-links
```
