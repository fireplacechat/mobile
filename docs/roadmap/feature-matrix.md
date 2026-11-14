# Feature status

Checked against mobile source on 2026-11-14. "Implemented" describes code on
`main`, not a store release or completed phone acceptance testing.

| Feature | Status and limits | Source or design |
|---|---|---|
| 1:1 encrypted text, linked devices | Implemented; a new device starts with empty history | [Chat service](../../lib/src/model/chat/chat_service.dart) |
| Reply, forward, reactions, edit, delete | Implemented; deletion cannot erase a recipient's screenshots or other copies | [Message controls](../../lib/src/model/chat/message_controls.dart), [message actions](../../lib/src/view/chat/message_actions.dart) |
| Formatting | `**bold**`, `_italic_`, `~~strike~~`; no link fetching | [Formatter](../../lib/src/model/chat/message_format.dart) |
| Global message search | Local history only; no plaintext disk index | [Search](../../lib/src/model/search/message_search.dart) |
| Unread counts, mute, in-app notices | Local state; no read receipts | [Chat activity](../../lib/src/model/notifications/chat_activity.dart) |
| System notification previews | Decrypted on the device; generic fallback when unavailable | [Preview design](../decisions/0030-notification-previews.md), [iOS extension](../decisions/0043-ios-notification-service.md) |
| Drafts | Account-scoped memory across routes; lost on restart/sign-out | [Drafts](../../lib/src/model/chat/chat_drafts.dart) |
| Pinned messages | Device-local message pins, not pinned conversations | [Pins](../../lib/src/model/chat/pinned_messages.dart) |
| Bubble colours and theme | Implemented; saved on the device | [Appearance](../../lib/src/app/chat_color_preference.dart) |
| Block and report | Implemented; reports exclude message text; unblock waits for acknowledgement | [Safety service](../../lib/src/model/safety/safety_service.dart), [0051](../decisions/0051-block-unblock-confirmation.md) |
| Recovery key | Restores account identity, not old message history | [Key service](../../lib/src/model/keys/key_service.dart) |
| Groups | Specified, not implemented; MLS with one leaf per participating device | [Version 1 specification](../protocol/group-chats-v1.md) |
| Tappable links, attachments, disappearing timers, chat archive/pin, offline state | Not implemented | [Roadmap](../ROADMAP.md) |
| Calls, stickers, GIFs | Not planned | [Roadmap](../ROADMAP.md) |
| Typing, delivered/read status, online/last seen, analytics, crash reporting, tracking | Excluded by policy | [Repository rules](../../AGENTS.md) |

Message text stays on the phones except as encrypted envelopes. Account, device
and chat metadata remain visible to the service; see the
[threat model](../protocol/threat-model.md). Historical UI requests and rationale
are in [the original review](chat-ui-features.md); current work belongs in issues.
