# Round speech bubbles everywhere

Every speech bubble icon in the app is now the round bubble, with its tail at the lower left, in place of Material's square ones. Where a bubble carries a mark, the mark sits inside the round bubble (`RoundBubbleIcon`). There are seven places:

| Image | Place |
| --- | --- |
| `*-empty.png` | The empty chat list's picture (the default for empty pages) |
| `*-new-chat.png` | New chat: "Message @name" |
| `*-profile.png` | The profile: Message, and Report Spam (a round bubble with "!") |
| `*-notices.png` | Notifications and sounds: In-App Notifications |
| `*-menu.png` | The chat row menu: Mark read (a round bubble with a tick) |

The push settings' message-preview row uses the round bubble with lines; it shows only when push notifications are set up, so it is not pictured. The new-chat button was already a round bubble.

`test/styles/round_bubbles_test.dart` fails if a square speech-bubble icon is used anywhere in `lib/`.

`TZ=UTC flutter test scripts/render/round_bubbles_render_test.dart` (on #260's branch and on this one) writes to `build/round-bubbles/`.
