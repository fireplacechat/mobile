# Chat UI features: status and priorities

Written 2026-10-05 from a read of the code on the UI follow-up branch (`feature/ui-review-followup`, `c73361b`) and the owner's decisions. "Today" describes what the code does now; nothing here has been tested on a phone.

## Decisions already made

- **No status indicators at all.** No typing indicators, read receipts, delivered ticks, or "online" / "last seen". (The existing "Message not confirmed" and "sent, could not save on this device" warnings are error states about the user's own send, not status indicators, and stay. Confirm this reading.)
- **Emoji work** through the phone keyboard. Messages are sent as UTF-8 text, so any character that can be typed arrives intact.
- **Everything below stays on the device where possible.** The server only stores ciphertext, so anything that needs message text (search, previews, counts) runs on the phone, from the encrypted local history.

## Owner decisions (2026-10-05)

- **Message length limit: 16,384 characters**, counted as Unicode code points (surrogate pairs count once; combining marks count separately). Enforced when typing, when sending and when forwarding; receivers defend against longer messages from other clients.
- **In-app notifications show the sender's name and the message by default.** A setting switches them to just "New message".
- **First run without a preferences file baselines old history as read; reset does the same:** messages already on the phone count as read; only later arrivals are unread.
- **Blocked contacts' chats are hidden** from the list, search, forwarding, notices and unread counts.
- **Backslash handling in formatting stays as it is.**

## Priority

### 1. Text formatting (Markdown-style)

| Syntax | Result |
|---|---|
| `**text**` | **bold** |
| `_text_` | *italics* |
| `~~text~~` | ~~strikethrough~~ |

- **Today:** none. Messages are plain text.
- **How:** the sender types the symbols; the receiving app styles them when it draws the bubble. The message on the wire is still plain text, so there is no protocol change and older builds simply show the symbols.
- **To decide / watch:** a single `_` on each side is the convention most chat apps use for italics. Handle unmatched markers, nesting (bold inside italics), underscores inside words and names (`snake_case`, `some_file_name`, a username such as `@jo_smith` must not turn into italics, so only treat `_` as a marker at the edge of a word), an escape for a literal `**` or `_`, text that stays selectable and copyable, and screen readers (they should read the words, not the symbols). Not applied to the composer preview unless wanted.

### 2. Page text and the "Link a new device" page

- **Today:** page titles and body text are left-aligned and the same size as other screens.
- **Link a new device (whole page):** centre the main text and make the page title larger. The page reads poorly at the moment, so treat it as a redesign of that page, not a tweak.
- **"Settings" and other pages:** the owner flagged text on "several pages like Settings". **Needs a list from the owner** of which headings and text should change (size, alignment, wording). Until then, plan an audit of every page title for size and alignment so they are consistent.

### 3. Unread counts

- **Today:** none. The chat list shows no badges.
- **What:** a number on each conversation in the chat list for incoming messages not yet seen, and a total on the **back arrow in a chat** (the "return to chats" icon) for unread messages in the other conversations.
- **How:** counted locally from the encrypted history against the time the chat was last opened; nothing is sent to the server and the other person never learns whether you read anything. This fits the no-status-indicators decision.
- **To decide:** whether message requests count; what happens to a count when the chat is open on another linked device; a count cap such as "99+".

### 4. Muting chats

- **Needed because of unread counts.** Per-conversation mute, set from the chat menu and from the list.
- **Today:** none.
- **To decide:** a muted chat still counts unread (shown in a quieter style) but never raises an in-app notification; whether muted chats are included in the back-arrow total (recommendation: no). Mute is stored on this device only. Un-muting needs to be easy to find.

### 5. In-app notifications

- **What:** when a message arrives while you are in the app but not looking at that chat, a box slides in at the top with the sender's name and the message text. Tapping it opens the chat. It goes away by itself after a few seconds and can be swiped away.
- **Not shown for:** the chat you are in, muted chats, a contact whose security code change is on hold, and message requests you have not accepted (their text stays hidden until accepted, as it is today).
- **To decide:** a setting to hide the message text in the box (name only); how several arrivals stack; a screen-reader announcement.
- **Separate from this:** notifications while the app is closed or in the background (operating-system push). The code for that is compiled in but turned off (`PUSH_ENABLED`); it needs a server-side sender and Apple push set up. See docs/push/README.md. Not part of this item.

### 6. Forwarding

- **What:** forward a message to another conversation, for **your own messages and other people's**. Long-press a message, choose Forward, pick one or more recipients.
- **Prerequisite:** a per-message menu. Today long-press only selects text. The same menu will later hold edit and delete, and Copy.
- **How:** the forwarded text is sent as a new message from you, encrypted separately for each recipient. Nothing about the original conversation is revealed to the server.
- **To decide:** show a "Forwarded" label; a confirmation when forwarding someone else's message ("you are sharing text @name wrote to you"); recipients limited to people who can currently receive (not blocked, not on identity hold; the 3-message request cap still applies to new contacts).

### 7. Global search

- **Today:** search on the chat list matches usernames only.
- **What:** one search that covers **the text of every message in every conversation**, with results showing the conversation, a snippet with the match highlighted, and the date; tapping a result opens the chat at that message.
- **How:** the server cannot search (it only holds ciphertext), so this is local, over the encrypted history on the phone. Start with decrypting and scanning in memory; consider an encrypted index only if histories get large. Do not write a plaintext search index to disk.
- **To decide:** whether searching also keeps the current username filter; case and accent handling; matching emoji; performance on very long histories; excluding or flagging undecryptable messages.

## Not a priority

- **Editing and deleting messages.** To be considered later. Decide what "delete" promises first (the recipient's phone keeps its own copy; server cleanup is operated separately).
- **Stickers and GIFs.**
- **Groups.** Chats are 1:1 only.
- **Voice and video calls.**

## Not yet decided

These came up in the review but the owner has not said either way.

| Item | Today | Note |
|---|---|---|
| Links | Plain text, not tappable, no previews | Tappable links need a link-opening package (the owner decides) and an "Open this link?" confirmation. Previews mean a phone fetches the page, which tells that site who is looking; if previews are ever added, make them opt-in. |
| Photos, files, voice notes, video | Not supported | The largest missing feature. Needs encrypted storage design and a size budget on the free plan. |
| Reply / quote | Not supported | Could share the per-message menu with forwarding. |
| Reactions | Not supported | |
| Pin and archive chats | Not supported | |
| Save the half-written message | Not saved when you leave the chat or restart | |
| Disappearing messages per chat | Not supported | No automatic server-deletion period is promised; local history is separate. |
| Past messages on a new phone | Not restored; a recovery key restores identity only | This is by design; keep the wording clear in the app. |
| Notifications when the app is closed | Compiled in, off | See item 5. |

## Implemented on `feature/chat-ui-features` (2026-10-05)

All seven priorities now have implementation, local tests and paired theme previews. The “Today” rows above describe the earlier reviewed base; they are retained as the original request.

Implementation choices and exact interaction details are in the code spec. Counts, muting and preview preferences are encrypted on this device; no Firebase fields or plaintext search index were added. Requests stay separate, muted chats are excluded from the back-arrow total, previews default to name and message; switching them off shows only “New message”, and forwarded messages contain only the existing raw message text. Existing publish-uncertainty warnings are retained as own-send errors, consistent with the no-status-indicators decision.

The review and validation report records adversarial checks and test evidence. Phone acceptance checks remain pending; no phone test or iOS compilation is claimed.

The owner decisions and C01–C04 review fixes continue on `feature/chat-ui-review`. See the follow-up review. No additional Firebase fields or storage were added.
