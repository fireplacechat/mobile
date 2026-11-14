# One colour per person, the reply bar, and smaller changes: previews

Widget renders at 390 x 844 points, in both themes, with fictional names.

| State | Light | Dark |
|---|---|---|
| Settings, *Your color*: one choice, with "They see" and "You see" | [light-accent-ocean-chat-colors.png](light-accent-ocean-chat-colors.png) | [dark-accent-ocean-chat-colors.png](dark-accent-ocean-chat-colors.png) |
| The same with the default colour | [light-chat-colors.png](light-chat-colors.png) | [dark-chat-colors.png](dark-chat-colors.png) |
| Replying in a 1:1 chat (the other person's colour has not arrived, so the default) | [light-reply-1to1.png](light-reply-1to1.png) | [dark-reply-1to1.png](dark-reply-1to1.png) |
| Replying in a group, in that member's colour | [light-reply-group.png](light-reply-group.png) | [dark-reply-group.png](dark-reply-group.png) |
| New group: round tick boxes | [light-new-group.png](light-new-group.png) | [dark-new-group.png](dark-new-group.png) |
| Invite friends: tickets with the slight rounding of the theme boxes | [light-invite-tickets.png](light-invite-tickets.png) | [dark-invite-tickets.png](dark-invite-tickets.png) |

Made by:

```sh
TZ=UTC flutter test scripts/render/render_screens_test.dart --plain-name chat-colors
TZ=UTC flutter test scripts/render/render_screens_test.dart --plain-name reply-composing
TZ=UTC flutter test scripts/render/render_groups_test.dart     # needs scripts/build_crypto_host.sh
TZ=UTC flutter test scripts/render/render_invites_test.dart
```
