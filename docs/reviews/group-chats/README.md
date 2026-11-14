# Group chats: screen previews

Widget renders of the group screens (decision [0050](../../decisions/0050-group-chats.md)),
in both themes, at 390 x 844 points. They are produced by

```sh
bash scripts/build_crypto_host.sh
TZ=UTC flutter test scripts/render/render_groups_test.dart
```

which runs real group services over the Rust MLS core, so times and ids differ
between runs. The names and messages are fictional. These are renders, not device
screenshots.

| State | Light | Dark |
|---|---|---|
| Chat list: groups beside 1:1 chats, with unread counts | [light-list.png](light-list.png) | [dark-list.png](dark-list.png) |
| Conversation: names, avatars and colours per member; lines for changes | [light-conversation.png](light-conversation.png) | [dark-conversation.png](dark-conversation.png) |
| Held message: the 1:1 menu and reactions | [light-conversation-menu.png](light-conversation-menu.png) | [dark-conversation-menu.png](dark-conversation-menu.png) |
| Editing in the composer | [light-conversation-editing.png](light-conversation-editing.png) | [dark-conversation-editing.png](dark-conversation-editing.png) |
| Someone who joined later | [light-joined-later.png](light-joined-later.png) | [dark-joined-later.png](dark-joined-later.png) |
| Group info: mute, members, roles, people invited | [light-info.png](light-info.png) | [dark-info.png](dark-info.png) |

The reaction bar in the held-message previews shows empty boxes: the SDK preview
font has no emoji (see `scripts/render/README.md`).
