# Message requests redesign (#248)

Each image shows main on the left and this change on the right.

| Image | What it shows |
| --- | --- |
| `*-list-1`, `*-list-3`, `*-list-5` | The chat list with one, three and five people waiting. The old envelope is replaced by their faces: one fills the avatar's place, two or three overlap in a small cluster, and past three the last place counts the rest. Below the title the row names who is waiting, and a count sits at the end. |
| `*-page` | Requests with a group invitation and four people, as rows in the chat list's style. |
| `*-empty` | The empty page, with places drawn for faces instead of the envelope. |
| `*-page-large` | 320 wide, 200% text. |

`TZ=UTC flutter test scripts/render/requests_redesign_test.dart` (the same script on main and on this branch) writes to `build/requests/`.

The test fixture has no group service, so Join and Decline show disabled in these renders. These are widget renders with fictional names.
