# A profile for any person (#244)

Chat details becomes the person's profile, the one page for a person. It shows:

- their avatar and name;
- **Message** and, when you already chat, **Mute**, as large tiles;
- the security code;
- Block and, when you already chat, Report.

Opened from a group's member list by an administrator, it also offers **Make or Remove administrator** and **Remove from group**. Those choices used to sit in a bottom sheet on Group info.

| Image | What it shows |
| --- | --- |
| `*-from-chat.png` | Before: Chat details. After: the profile, opened from your chat with fred |
| `*-new.png` | Someone you have never chatted with: Message starts a chat, as New chat does |
| `*-blocked.png` | Blocked: Unblock takes Message's place |
| `*-group-admin.png` | A member's profile as a group administrator sees it |
| `*-large.png` | 320 wide with 200% text |

Commands:
- `TZ=UTC flutter test scripts/render/profile_test.dart`
- `TZ=UTC flutter test scripts/render/render_screens_test.dart --plain-name chat-details` (on main and on this branch)
- `TZ=UTC flutter test scripts/render/render_groups_test.dart`

These are widget renders with fictional names.
