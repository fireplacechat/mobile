# Grouped open-source licences (#118)

Settings opens a Fireplace page with searchable, shared licence cards. A card
lists all its packages and a notice preview; opening it shows the full selectable
notice. Search matches package names without case sensitivity and survives a
visit to the full notice.

Grouping uses the exact original text, including copyright lines. Different
notices remain separate, even for the same package. Flutter's existing paragraph
parser reflows the display without changing its words. Explicit licence headings
supply card names; notices without one use **Licence notice**. No legal terms are
inferred from package names or body clauses.

The page reads the existing local `LicenseRegistry`; it adds no network access,
server operations or dependencies. Failed collectors show a retry rather than
an incomplete catalogue. Keyboard and enlarged-text layouts remain scrollable.

| State | Preview |
| --- | --- |
| Grouped list | [Dark](dark-groups.png), [light](light-groups.png) |
| Package search | [Dark](dark-search.png) |
| Full selectable notice | [Light](light-full.png) |
| 320-wide, 200% text | [List](narrow-light.png), [full notice](narrow-dark-full.png) |

These are real widget renders with deliberately synthetic package notices. Test
fixtures are not shipped as legal notices. Regenerate all ten paired-theme states
with `TZ=UTC flutter test scripts/render/render_screens_test.dart --name licences
--reporter expanded`. Sources are written to `build/renders/`.

Tests cover exact-text grouping, copyright differences, multiple notices for one
package, custom paragraph-only entries, unchanged wording, source failure,
Settings navigation, filtering/clearing, selectable full text, back navigation,
enlarged text, keyboard constraints, retry and disposal during loading.
