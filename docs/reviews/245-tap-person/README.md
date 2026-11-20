# Tap a person's avatar or name (#245)

At the top of a 1:1 chat, next to someone else's message in a group, and in a group's member list, the avatar and the name open the person's profile (#244).

- **What responds:** only those two. The rest of the app bar or row does not.
- **While pressed:** each gets a slight shade of its own: a circle over the avatar, a soft rounded patch around the words.

`light-pressed.png` and `dark-pressed.png` show the top of a 1:1 chat while a finger is down, on iOS and on Android. The group rows use the same two widgets (`lib/src/widgets/person_tap.dart`).

`TZ=UTC flutter test scripts/render/person_tap_test.dart` writes them to `build/person-tap/`. These are widget renders with fictional names.
